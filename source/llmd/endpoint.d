module llmd.endpoint;

import llmd.model;
import std.conv;
import std.json;
import std.algorithm;
import std.net.curl;
import std.array;
import llmd.exception;

/// Represents a generic interface for interacting with a language model API endpoint.
interface IEndpoint
{
    /// API key used for authentication, may be empty if not required.
    static string key;
    /// Cache of loaded models keyed by their name.
    static Model[string] models;

    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api);

    /// Loads a model from this endpoint, optionally creating it if not cached.
    ///
    /// This will send a completion to the model with no content to validate if the model may be loaded.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        JSONValue[] messages = []);

    /// Queries for the list of available models from `/v1/models`.
    Model[] available();
}

/// Represents a strongly-typed OpenAI-style model endpoint for a given scheme, address, and port.
// TODO: Completions here.
class Endpoint(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
    /// API key used for authentication, may be empty if not required.
    static string key;
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

public:
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api)
    {
        return SCHEME~"://"~ADDRESS
            ~((PORT != 0 && PORT != 80 && PORT != 443) ? ':'~PORT.to!string : "")
            ~api;
    }

    /// Loads a model from this endpoint, optionally creating it if not cached.
    ///
    /// This will send a completion to the model with no content to validate if the model may be loaded.
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
        m.send("", true).bubble();
        return m;
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