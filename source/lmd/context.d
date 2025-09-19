module lmd.context;

import std.json;
import lmd.model;
import lmd.options;

interface IContext
{
    /// Serializes the context to JSON
    JSONValue toJSON();
    
    /// Builds a completions request JSON with options
    JSONValue completions(IOptions options);
    
    /// Builds an embeddings request JSON with options  
    JSONValue embeddings(IOptions options);
    
    /// Adds a message to the conversation
    void add(string role, string content, string toolCallId = null);
    
    /// Gets all messages in the context
    JSONValue[] getMessages();
    
    /// Clears all messages
    void clear();
}