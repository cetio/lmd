module lmd.model;

import lmd.response;
import lmd.endpoint;
import lmd.context;
import lmd.options;
import lmd.exception;

/// Represents a model instance associated with a specific endpoint.
class Model
{
    string key;
    IEndpoint endpoint;
    string name;
    string owner;
    Options options;
    Context context;

    this(IEndpoint endpoint,
        string name = null,
        string owner = "organization_owner",
        Options options = Options.init,
        Context context = Context.init)
    {
        this.endpoint = endpoint;
        this.owner = owner;
        this.name = name;
        this.options = options;
        this.context = context;
        options["model"] = name;
    }

    Response completions(string prompt)
    {
        context.clear();
        context.add("user", prompt);
        return endpoint.completions(this);
    }

    Response embeddings(string prompt)
    {
        context.clear();
        context.add("user", prompt);
        return endpoint.embeddings(this);
    }

    ResponseStream stream(string prompt, void delegate(Response) callback = null)
    {
        context.clear();
        context.add("user", prompt);
        return endpoint.stream(this, callback);
    }
}