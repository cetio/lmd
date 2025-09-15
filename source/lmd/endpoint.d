module lmd.endpoint;

import std.json;
import lmd.model;
import lmd.exception;
import lmd.response;

// TODO: code from model.d should be moved here.
// TODO: Claude

/// Represents a generic interface for interacting with a language model API endpoint.
interface IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;
    /// API key for this endpoint.
    static string key;
    /// Whether this endpoint supports streaming.
    // TODO: Streaming definitely varies by endpoint and Response should be more modular.
    enum bool supportsStreaming = false;

    /// Creates a chat message object with the specified role and content.
    JSONValue message(string role, string content);
    
    /// Creates a tool message object with the specified content and tool call ID.
    JSONValue message(string role, string content, string toolCallId);
    
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api);

    /// Loads a model from this endpoint, optionally creating it if not cached.
    ///
    /// This will send a completion to the model with no content to validate if the model may be loaded.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        JSONValue[] messages = []);
    
    /// Requests a completion from '/v1/chat/completions' for `model`.
    Response completions(Model model);

    /// Requests a streaming completion from '/v1/chat/completions' for `model'.
    ResponseStream stream(void delegate(Response) callback)(Model model);

    /// Internal function to commence streaming for a ResponseStream.
    void _commence(ResponseStream stream);

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model);

    /// Requests embeddings for the given text using the specified model.
    Response embeddings(Model model);
    
    /// Queries for the list of available models from `/v1/models`.
    Model[] available();

}