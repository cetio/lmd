module lmd.context;

import std.json;
import lmd.model;
import lmd.options;
import lmd.response;

interface IContext
{
    /// Serializes the context to JSON
    JSONValue toJSON();
    
    /// Builds a completions request JSON with options
    JSONValue completions(Options options);
    
    /// Builds an embeddings request JSON with options  
    JSONValue embeddings(Options options);
    
    /// Adds a message to the conversation
    void add(string role, string content, string toolCallId = null);
    
    /// Gets all messages in the context
    JSONValue[] getMessages();
    
    /// Clears all messages
    void clear();
    
    /// Chooses a choice and adds it to the context
    void choose(Choice choice);
}