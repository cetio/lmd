module lmd.model;

import std.json;
import std.net.curl;
import std.conv;
import std.algorithm;
import std.datetime;
import std.array;
import lmd.response;
import lmd.endpoint;

/// Represents a model instance associated with a specific endpoint.
public struct Model
{
    /// API key used for authentication, may be empty if not required.
    string key;
    /// Endpoint which this model is bound to.
    IEndpoint ep;
    /// The name of the model.
    string name;
    /// The organization or owner of the model.
    string owner;
    /// The message history associated with this model.
    JSONValue[] messages;

package:
    /// Options used for generation.
    JSONValue _options;

    this(A : IEndpoint)(A ep, 
        string name = null, 
        string owner = "organization_owner", 
        JSONValue options = JSONValue.emptyObject,
        JSONValue[] messages = [])
    {
        if (name in ep.models)
            this = ep.load(name, owner, options, messages);
        this.ep = ep;
        this.name = name;
        this.owner = owner;
        this._options = options;
        this.messages = messages;
    }

    JSONValue message(string role, string content) => 
        ep.message(role, content);

    bool sanity()
    {
        if (name !in ep.models)
            ep.models[name] = this;
        return true;
    }

public:
    /// Sets the system prompt at the beginning of the conversation.
    JSONValue[] setSystemPrompt(string prompt)
    {
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = [message("system", prompt)]~messages[1..$];
        else
            messages = [message("system", prompt)]~messages;
        return messages;
    }

    // NOTE: Should this sanity check?
    JSONValue[] choose(Choice choice) =>
        messages ~= message("assistant", choice.content);

    /// Adds a tool message to the conversation.
    JSONValue[] addToolMessage(string toolCallId, string content) => 
        messages ~= ep.message("tool", content, toolCallId);

    JSONValue lastUserMessage() =>
        messages.filter!(m => m["role"].str == "user").front;

    /// Resets the current message stream (ignoring the first system prompt) and sends a new message
    /// using `prompt` and returns the response of the model. 
    /// 
    /// If `think` is false then `"/no-think"` will be appended to the user prompt.
    Response send(string prompt, bool think = true)
    {
        // TODO: Redundancy.
        if (!think)
            prompt ~= "/no-think";
        // This is sort of unsafe since we don't sanity check but I don't care.
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = messages[0..1]~message("user", prompt);
        else
            messages = [message("user", prompt)];

        return ep.completions(this);
    }

    /// Sends a streaming request and returns a ResponseStream object that can be used to get streaming data.
    /// 
    /// If `think` is false then `"/no-think"` will be appended to the user prompt.
    ResponseStream stream(string prompt, void delegate(Response) callback = null, bool think = true)
    {
        if (!think)
            prompt ~= "/no-think";
        // This is sort of unsafe since we don't sanity check but I don't care.
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = messages[0..1]~message("user", prompt);
        else
            messages = [message("user", prompt)];

        return ep.stream(this, callback);
    }

    /// Requests embeddings for the given text using the current model.
    Response embeddings(string prompt)
    {
        // TODO: This actually breaks the way I do it everywhere else, but I'm not sure yet...
        messages ~= message("user", prompt);
        return ep.embeddings(this);
    }

    /// Converts this model into a human-readable JSON string.
    string toString()
    {
        JSONValue json = JSONValue.emptyObject;
        json["id"] = name;
        json["owned_by"] = owner;
        return json.toPrettyString;
    }
}
