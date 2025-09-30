module lmd.model;

// Note: This module requires many imports due to its central role in the library
import std.net.curl;
import std.conv;
import std.algorithm;
import std.datetime;
import std.json;
import std.array;
import lmd.response;
import lmd.endpoint;
import lmd.context;
import lmd.options;
import lmd.exception;

/// Represents a model instance associated with a specific endpoint.
struct Model
{
    /// API key used for authentication, may be empty if not required.
    string key;
    /// Endpoint which this model is bound to.
    IEndpoint ep;
    /// The name of the model.
    string name;
    /// The organization or owner of the model.
    string owner;
    /// Options for this model.
    Options options;
    /// Context for this model.
    IContext context;

package:
    this(IEndpoint ep,
        string name = null,
        string owner = "organization_owner",
        Options options = Options.init,
        IContext context = null)
    {
        if (name in ep.models)
            this = ep.load(name, owner, options, context);
        this.ep = ep;
        this.name = name;
        this.owner = owner;
        this.options = options;
        this.context = context;
    }

public:
    /// Resets the current message stream (ignoring the first system prompt) and sends a new message
    /// using `prompt` and returns the response of the model.
    Response send(string prompt)
    {
        context.clear();
        context.add("user", prompt);
        return ep.completions(this);
    }

    /// Sends a streaming request and returns a ResponseStream object that can be used to get streaming data.
    ResponseStream stream(string prompt, void delegate(Response) callback = null)
    {
        context.clear();
        context.add("user", prompt);
        return ep.stream(this, callback);
    }

    /// Requests embeddings for the given text using the current model.
    Response embeddings(string prompt)
    {
        context.clear();
        context.add("user", prompt);
        return ep.embeddings(this);
    }

    /// Converts the model to a JSON string representation.
    string toString() const
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["name"] = JSONValue(name);
        json.object["owner"] = JSONValue(owner);
        return json.toString();
    }
}
