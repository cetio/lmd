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
    ref string key();

    ref Model[string] models();
    
    Model[] available();

    // TODO: Load by model variety, not just name.
    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        IContext context = null);
    
    Response completions(Model model);

    ResponseStream stream(Model model, void delegate(Response) callback = null);

    Response legacyCompletions(Model model);

    Response embeddings(Model model);
}