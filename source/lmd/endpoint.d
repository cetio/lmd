module lmd.endpoint;

import std.json;
import lmd.model;
import lmd.exception;
import lmd.response;

// TODO: This file is short and kind of lame.

/// Represents a generic interface for interacting with a language model API endpoint.
interface IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;
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

    /// Requests a streaming completion from '/v1/chat/completions' for `model`.
    void stream(void delegate(StreamChunk) F)(Model model);

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model);

    /// Queries for the list of available models from `/v1/models`.
    Model[] available();
}