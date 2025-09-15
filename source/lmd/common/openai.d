module lmd.common.openai;

// So many imports :(
import std.conv;
import std.algorithm;
import std.net.curl;
import std.array;
import std.json;
import std.string;
public import lmd.endpoint;
public import lmd.model;
public import lmd.response;
import lmd.exception;
import mink.sync.atomic;

/// Represents a strongly-typed OpenAI-style model endpoint for a given scheme, address, and port.
class OpenAI(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;
    /// API key for this endpoint.
    static string key;
    /// Whether this endpoint supports streaming.
    enum bool supportsStreaming = true;

package:
    /// Converts the `/v1/models` JSON response into a list of `Model` objects.
    Model[] fromJSON(JSONValue json)
    {
        Model[] ret;
        if ("data" in json)
        {
            foreach (model; json["data"].array)
            {
                ret ~= Model(
                    this,
                    "id" in model ? model["id"].str : null, 
                    "owned_by" in model ? model["owned_by"].str : null
                );
            }
        }
        return ret;
    }

    /// Builds a JSON representation of logit bias mappings.
    JSONValue logitBias(int[string] logitBias)
    {
        JSONValue json = JSONValue.emptyObject;
        foreach (k; logitBias.keys)
            json.object['"'~k~'"'] = JSONValue(logitBias[k]);
        return json;
    }

    /// Builds the JSON request for completions.
    JSONValue buildRequest(Model model, bool streaming = false)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["model"] = JSONValue(model.name);
        json.object["messages"] = model.messages;

        Options options = model.options;
        if (options.temperature !is float.nan) json.object["temperature"] = JSONValue(options.temperature);
        if (options.topP !is float.nan) json.object["top_p"] = JSONValue(options.topP);
        if (options.n != 0) json.object["n"] = JSONValue(options.n);
        if (options.stop != null) json.object["stop"] = JSONValue(options.stop);
        if (options.presencePenalty !is float.nan) 
            json.object["presence_penalty"] = JSONValue(options.presencePenalty);
        if (options.frequencyPenalty !is float.nan) 
            json.object["frequency_penalty"] = JSONValue(options.frequencyPenalty);
        if (options.logitBias != null) 
            json.object["logit_bias"] = logitBias(options.logitBias);
        json.object["max_tokens"] = JSONValue(options.maxTokens);
        json.object["stream"] = JSONValue(streaming);
        
        // Add tools if provided
        if (options.tools.length > 0)
        {
            JSONValue toolsArray = JSONValue.emptyArray;
            foreach (tool; options.tools)
            {
                JSONValue toolJson = JSONValue.emptyObject;
                toolJson.object["type"] = tool.type;
                toolJson.object["function"] = JSONValue.emptyObject;
                toolJson.object["function"].object["name"] = tool.name;
                toolJson.object["function"].object["description"] = tool.description;
                toolJson.object["function"].object["parameters"] = tool.parameters;
                toolsArray.array ~= toolJson;
            }
            json.object["tools"] = toolsArray;
        }
        
        // Add tool_choice if provided and not auto
        if (options.toolChoice.type != "auto")
        {
            JSONValue toolChoiceJson = JSONValue.emptyObject;
            toolChoiceJson.object["type"] = options.toolChoice.type;
            if (options.toolChoice.type == "function" && options.toolChoice.name.length > 0)
            {
                toolChoiceJson.object["function"] = JSONValue.emptyObject;
                toolChoiceJson.object["function"].object["name"] = options.toolChoice.name;
            }
            json.object["tool_choice"] = toolChoiceJson;
        }

        return json;
    }

    string selectKey(Model model) =>
        model.key == null && model.name != null ? key : model.key;

public:
    /// Builds a chat message object with the specified role and content.
    JSONValue message(string role, string content)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["role"] = role;
        json.object["content"] = content;
        return json;
    }

    /// Builds a tool message object with the specified content and tool call ID.
    JSONValue message(string role, string content, string toolCallId)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["role"] = role;
        json.object["content"] = content;
        json.object["tool_call_id"] = toolCallId;
        return json;
    }

    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api)
    {
        return SCHEME~"://"~ADDRESS
            ~((PORT != 0 && PORT != 80 && PORT != 443) ? ':'~PORT.to!string : "")
            ~api;
    }

    /// Loads a model from this endpoint, optionally creating it if not cached.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        JSONValue[] messages = [])
    {
        if (name != null && available.filter!(m => m.name == name).empty)
            throw new ModelException(
                "model_not_found", 
                "Model is not available.", 
                "model", 
                "invalid_request_error"
            );

        Model m = name in models 
            ? models[name] 
            : (models[name] = Model(this, name, owner, options, messages));
        return m;
    }

    /// Requests a completion from '/v1/chat/completions' for `model`.
    Response completions(Model model)
    {
        // Temporarily does not do message validation. Restore later!
        model.sanity();

        JSONValue json = buildRequest(model, false);

        // This is the worst networking I have seen in my entire life.
        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer "~selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 
            ? Response(model, resp.strip.parseJSON) 
            : Response(model, JSONValue.emptyObject);
    }

    /// Requests a streaming completion from '/v1/chat/completions' for `model'.
    ResponseStream stream(void delegate(Response) callback)(Model model)
    {
        if (!supportsStreaming)
            throw new ModelException(
                "not_supported", 
                "Streaming is not supported by this model.", 
                "streaming", 
                "invalid_request_error"
            );

        model.sanity();
        JSONValue json = buildRequest(model, true);

        ResponseStream stream = new ResponseStream(callback);
        stream.model = model;
        stream.requestJson = json;
        stream._commence = (ResponseStream rs) => _commence(rs);
        return stream;
    }

    void _commence(ResponseStream stream)
    {
        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(stream.requestJson.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(stream.model) != null)
            http.addRequestHeader("Authorization", "Bearer "~selectKey(stream.model));

        string buffer;
        http.onReceive((ubyte[] data) 
        { 
            buffer ~= cast(string)data;
            
            // Process complete JSON objects from the buffer
            while (true)
            {
                size_t newlinePos = buffer.indexOf('\n');
                if (newlinePos == -1) break;
                
                string line = buffer[0..newlinePos];
                buffer = buffer[newlinePos + 1..$];
                
                // Skip empty lines and data: prefix
                if (line.length == 0) continue;
                if (line.startsWith("data: ")) line = line[6..$];
                if (line == "[DONE]") continue;
                
                try
                {
                    JSONValue jsonChunk = line.parseJSON;
                    Response response = Response(stream.model, jsonChunk);
                    stream.response.store(response);
                    if (stream.callback !is null)
                        stream.callback(response);
                }
                catch (Exception e)
                {
                    // Skip malformed JSON chunks
                    continue;
                }
            }
            
            return data.length; 
        });

        http.perform();
    }

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["model"] = JSONValue(model.name);
        json.object["prompt"] = JSONValue(model.messages[$-1]["content"]);

        Options options = model.options;
        if (options.temperature !is float.nan) json.object["temperature"] = JSONValue(options.temperature);
        if (options.topP !is float.nan) json.object["top_p"] = JSONValue(options.topP);
        if (options.n != 0) json.object["n"] = JSONValue(options.n);
        if (options.stop !is null) json.object["stop"] = JSONValue(options.stop);
        if (options.presencePenalty !is float.nan) json.object["presence_penalty"] = JSONValue(options.presencePenalty);
        if (options.frequencyPenalty !is float.nan) 
            json.object["frequency_penalty"] = JSONValue(options.frequencyPenalty);
        if (options.logitBias !is null) 
            json.object["logit_bias"] = logitBias(options.logitBias);
        json.object["max_tokens"] = JSONValue(options.maxTokens);
        json.object["stream"] = JSONValue(false);

        HTTP http = HTTP(url("/v1/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        // TODO: This may be incorrect for OpenAI API endpoints, validate they use the Authorization header in this format.
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer "~selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 ? Response(model, resp.parseJSON) : Response(model, JSONValue.emptyObject);
    }

    /// Requests embeddings for the given text using the specified model.
    Response embeddings(Model model)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["model"] = JSONValue(model.name);
        json.object["input"] = model.lastUserMessage()["content"];

        HTTP http = HTTP(url("/v1/embeddings"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 
            ? Response(model, resp.strip.parseJSON) 
            : Response(model, JSONValue.emptyObject);
    }

    /// Queries for the list of available models from `/v1/models`.
    Model[] available()
    {
        HTTP http = HTTP(url("/v1/models"));
        http.method = HTTP.Method.get;
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 
            ? fromJSON(resp.parseJSON)
            : null;
    }
}

/// Helper function for creating an OpenAI-style endpoint as an IEndpoint.
IEndpoint openai(string SCHEME, string ADDRESS, uint PORT)()
{
    return cast(IEndpoint)(new OpenAI!(SCHEME, ADDRESS, PORT));
}