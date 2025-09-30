module lmd.context;

import std.json;
import lmd.model;
import lmd.options;
import lmd.response;

interface IContext
{
    ref JSONValue[] messages();

    void choose(Choice choice);
    
    void add(string role, string content, string toolCallId = null);

    void clear();

    JSONValue completions(Options options);
    
    JSONValue embeddings(Options options);
}