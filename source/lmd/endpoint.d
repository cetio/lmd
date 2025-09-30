module lmd.endpoint;

import std.json;
import lmd.model;
import lmd.exception;
import lmd.response;
import lmd.context;
import lmd.options;

// TODO: Add Claude endpoint support.

/// Represents a generic interface for interacting with a language model API endpoint.
interface IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;
    /// API key for this endpoint.
    static string key;
    
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api);

    /// Loads a model from this endpoint, optionally creating it if not cached.
    ///
    /// This will send a completion to the model with no content to validate if the model may be loaded.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        IContext context = null);
    
    /// Requests a completion from '/v1/chat/completions' for `model`.
    Response completions(Model model);

    /// Requests a streaming completion from '/v1/chat/completions' for `model'.
    ResponseStream stream(Model model, void delegate(Response) callback = null);

    /// Internal function to commence streaming for a ResponseStream.
    void _commence(ResponseStream stream);

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model);

    /// Requests embeddings for the given text using the specified model.
    Response embeddings(Model model);

    /// Queries for the list of available models from `/v1/models`.
    Model[] available();
}