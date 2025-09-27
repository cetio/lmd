module lmd.common.openai;

public import lmd.endpoint;
public import lmd.model;
public import lmd.response;
public import lmd.context;
public import lmd.options;
import lmd.exception;
import core.atomic;
// So many imports :(
import std.conv;
import std.algorithm;
import std.net.curl;
import std.array;
import std.json;
import std.string;

/// Represents a strongly-typed OpenAI-style model endpoint for a given scheme, address, and port.
class OpenAI(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
    class Options : IOptions
    {
        alias Owner = OpenAI;
        /// Sampling temperature (higher = more random). Use `float.nan` to omit.
        float temperature;
        /// Nucleus sampling parameter. Use `float.nan` to omit.
        float topP;
        /// Number of completions to request.
        int n = 0;
        /// Stop sequence.
        string stop;
        /// Maximum number of tokens to generate. Use `-1`` to omit.
        int maxTokens = -1;
        /// Presence penalty scalar.
        float presencePenalty;
        /// Frequency penalty scalar.
        float frequencyPenalty;
        /// Per-token logit bias map. Keys are token ids (as strings) and values
        /// are bias integers.
        int[string] logitBias;
        /// Available tools for the model to use.
        Tool[] tools;
        /// Tool choice configuration.
        ToolChoice toolChoice;
        /// Enable streaming responses.
        bool stream = false;
        // TODO: Support variables and refer to think as reasoning (add reasoning effort and stuff?) (OpenAI options)

        /// Builds a JSON representation of logit bias mappings.
        JSONValue calcLogitBias(int[string] logitBias)
        {
            JSONValue json = JSONValue.emptyObject;
            foreach (k; logitBias.keys)
                json.object['"'~k~'"'] = JSONValue(logitBias[k]);
            return json;
        }

        JSONValue toJSON()
        {
            JSONValue json = JSONValue.emptyObject;
            if (temperature !is float.nan) json.object["temperature"] = JSONValue(temperature);
            if (topP !is float.nan) json.object["top_p"] = JSONValue(topP);
            if (n != 0) json.object["n"] = JSONValue(n);
            if (stop != null) json.object["stop"] = JSONValue(stop);
            if (presencePenalty !is float.nan) 
                json.object["presence_penalty"] = JSONValue(presencePenalty);
            if (frequencyPenalty !is float.nan) 
                json.object["frequency_penalty"] = JSONValue(frequencyPenalty);
            if (logitBias != null) 
                json.object["logit_bias"] = calcLogitBias(logitBias);
            json.object["stream"] = JSONValue(stream);
            json.object["max_tokens"] = JSONValue(maxTokens);
            
            // TODO: Audit tools and make sure that it all works. Make it agnostic?
            if (tools.length > 0)
            {
                JSONValue toolsArray = JSONValue.emptyArray;
                foreach (tool; tools)
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
            if (toolChoice.type != "auto")
            {
                JSONValue toolChoiceJson = JSONValue.emptyObject;
                toolChoiceJson.object["type"] = toolChoice.type;
                if (toolChoice.type == "function" && toolChoice.name.length > 0)
                {
                    toolChoiceJson.object["function"] = JSONValue.emptyObject;
                    toolChoiceJson.object["function"].object["name"] = toolChoice.name;
                }
                json.object["tool_choice"] = toolChoiceJson;
            }
            return json;
        }
    }

    class Context : IContext
    {
        alias Owner = OpenAI;
        JSONValue[] messages;
        
        this(JSONValue[] messages = [])
        {
            this.messages = messages;
        }
        
        JSONValue toJSON()
        {
            JSONValue json = JSONValue.emptyObject;
            json.object["messages"] = JSONValue(messages);
            return json;
        }
        
        JSONValue completions(IOptions options)
        {
            JSONValue json = options.toJSON();
            json.object["messages"] = JSONValue(messages);
            return json;
        }
        
        JSONValue embeddings(IOptions options)
        {
            JSONValue json = options.toJSON();
            return json;
        }
        
        void add(string role, string content, string toolCallId = null)
        {
            JSONValue msg = JSONValue.emptyObject;
            msg.object["role"] = JSONValue(role);
            msg.object["content"] = JSONValue(content);
            if (toolCallId != null)
                msg.object["tool_call_id"] = JSONValue(toolCallId);
            messages ~= msg;
        }
        
        JSONValue[] getMessages()
        {
            return messages;
        }
        
        void clear()
        {
            messages = [];
        }
    }

    /// Cache of loaded models keyed by their name.
    static Model[string] models;
    /// API key for this endpoint.
    static string key;

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

    string selectKey(Model model) =>
        model.key == null && model.name != null ? key : model.key;

public:
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api)
    {
        return SCHEME~"://"~ADDRESS
            ~((PORT != 0 && PORT != 80 && PORT != 443) ? ':'~PORT.to!string : "")
            ~api;
    }

    Model load(string name = null, 
        string owner = "organization_owner", 
        IOptions options = null,
        IContext context = null)
    {
        if (name != null && available.filter!(m => m.name == name).empty)
            throw new ModelException(
                "model_not_found", 
                "Model is not available.", 
                "model", 
                "invalid_request_error"
            );

        if (options is null)
            options = new Options();
        if (context is null)
            context = new Context();

        Model m = name in models 
            ? models[name] 
            : (models[name] = Model(this, name, owner, options, context));
        return m;
    }


    /// Requests a completion from '/v1/chat/completions' for `model`.
    Response completions(Model model)
    {
        // TODO: Sanity checks.
        JSONValue json = model.context.completions(model.options);

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
    ResponseStream stream(Model model, void delegate(Response) callback)
    {
        // throw new ModelException(
        //     "not_supported", 
        //     "Streaming is not supported by this model.", 
        //     "streaming", 
        //     "invalid_request_error"
        // );

        ResponseStream stream = new ResponseStream(model, callback);
        stream._commence = &_commence;
        return stream;
    }

    void _commence(ResponseStream stream)
    {
        // TODO: Really ugly.....
        bool tmp = (cast(Options)stream.model.options).stream;
        scope (exit) (cast(Options)stream.model.options).stream = tmp;
        // TODO: Force IOptions and IContext to be compatible with the IEndpoint.
        (cast(Options)stream.model.options).stream = true;

        JSONValue json = stream.model.context.completions(stream.model.options);

        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
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
                    Response response = Response(stream.model, line.parseJSON);
                    stream.updateResponse(response);
                    if (stream.callback !is null)
                        stream.callback(response);
                }
                catch (Exception e)
                    // Skip malformed JSON chunks
                    continue;
            }
            
            return data.length; 
        });

        int result = http.perform();
        if (result != 0 || buffer.length == 0)
        {
            // Create an error response if the HTTP request failed or no data received
            JSONValue errorJson = JSONValue.emptyObject;
            errorJson["error"] = JSONValue([
                "code": JSONValue(result != 0 ? "connection_failed" : "no_data_received"),
                "message": JSONValue(result != 0 ? "Failed to connect to the server" : "No data received from server"),
                "param": JSONValue("stream"),
                "type": JSONValue("connection_error")
            ]);
            Response err = Response(stream.model, errorJson);
            stream.updateResponse(err);
            if (stream.callback !is null)
                stream.callback(err);
        }
    }

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model)
    {
        JSONValue json = model.context.completions(model.options);

        HTTP http = HTTP(url("/v1/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer "~selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 ? Response(model, resp.parseJSON) : Response(model, JSONValue.emptyObject);
    }

    /// Requests embeddings for the given text using the specified model.
    Response embeddings(Model model)
    {
        JSONValue json = model.context.embeddings(model.options);

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