module llmd.endpoint;

import llmd.model;
import std.conv;
import std.json;
import std.algorithm;
import std.net.curl;
import std.array;
import llmd.exception;
import llmd.response;

/// Represents a generic interface for interacting with a language model API endpoint.
interface IEndpoint
{
    /// API key used for authentication, may be empty if not required.
    static string key;
    /// Cache of loaded models keyed by their name.
    static Model[string] models;

    /// Creates a chat message object with the specified role and content.
    JSONValue message(string role, string content);
    
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api);

    /// Loads a model from this endpoint, optionally creating it if not cached.
    ///
    /// This will send a completion to the model with no content to validate if the model may be loaded.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        JSONValue[] messages = []);
    
    /// Requests a completion from the model provided.
    Response completions(Model model);

    /// Queries for the list of available models from `/v1/models`.
    Model[] available();
}

/// Represents a strongly-typed OpenAI-style model endpoint for a given scheme, address, and port.
// TODO: Completions here.
class Endpoint(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;

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

public:
    /// Builds a chat message object with the specified role and content.
    JSONValue message(string role, string content)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["role"] = role;
        json.object["content"] = content;
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

    /// Requests a completion from the model provided.
    Response completions(Model model)
    {
        if (!model.sanity) 
            throw new Exception("Failed sanity check. Message contents are invalid!");

        JSONValue json = JSONValue.emptyObject;
        json.object["model"] = JSONValue(model.name);
        json.object["messages"] = model.messages;

        Options options = model.options;
        if (options.temperature !is float.nan) json.object["temperature"] = JSONValue(options.temperature);
        if (options.topP !is float.nan) json.object["top_p"] = JSONValue(options.topP);
        if (options.n != 0) json.object["n"] = JSONValue(options.n);
        if (options.stop != null) json.object["stop"] = JSONValue(options.stop);
        if (options.presencePenalty !is float.nan) json.object["presence_penalty"] = JSONValue(options.presencePenalty);
        if (options.frequencyPenalty !is float.nan) json.object["frequency_penalty"] = JSONValue(options.frequencyPenalty);
        if (options.logitBias != null) json.object["logit_bias"] = logitBias(options.logitBias);
        json.object["max_tokens"] = JSONValue(options.maxTokens);
        // Streaming is not currently supported.
        json.object["stream"] = JSONValue(false);

        // This is the worst networking I have seen in my entire life.
        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 ? Response(resp.parseJSON) : Response.init;
    }

    /// Queries for the list of available models from `/v1/models`.
    Model[] available()
    {
        HTTP http = HTTP(url("/v1/models"));
        http.method = HTTP.Method.get;
        if (key !is null)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        return http.perform() == 0 
            ? fromJSON(resp.parseJSON)
            : null;
    }
}

/// Helper function for creating endpoints as IEndpoint objects.
IEndpoint endpoint(string SCHEME, string ADDRESS, uint PORT)()
{
    return cast(IEndpoint)(new Endpoint!(SCHEME, ADDRESS, PORT));
}