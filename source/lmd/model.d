module lmd.model;

import std.json;
import std.net.curl;
import std.conv;
import std.algorithm;
import std.datetime;
import std.array;
import lmd.response;
import lmd.endpoint;

public struct Options
{
    /// Sampling temperature (higher = more random). Use `float.nan` to omit.
    float temperature;
    /// Nucleus sampling parameter. Use `float.nan` to omit.
    float topP;
    /// Number of completions to request.
    int n = 0;
    /// Stop sequence.
    string stop;
    /// Maximum number of tokens to generate. Use `-1`` to omit.
    int maxTokens = -1;
    /// Presence penalty scalar.
    float presencePenalty;
    /// Frequency penalty scalar.
    float frequencyPenalty;
    /// Per-token logit bias map. Keys are token ids (as strings) and values
    /// are bias integers.
    int[string] logitBias;
    /// Available tools for the model to use.
    Tool[] tools;
    /// Tool choice configuration.
    ToolChoice toolChoice;
    /// Enable streaming responses.
    bool stream = false;
}

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
    /// Options used for generation.
    Options options;
    /// The message history associated with this model.
    JSONValue[] messages;

    /// Sets the system prompt at the beginning of the conversation.
    JSONValue[] setSystemPrompt(string prompt)
    {
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = [message("system", prompt)]~messages[1..$];
        else
            messages = [message("system", prompt)]~messages;
        return messages;
    }

    // TODO: Should this sanity check?
    JSONValue[] choose(Choice choice) =>
        messages ~= message("assistant", choice.content);

    /// Adds a tool message to the conversation.
    JSONValue[] addToolMessage(string toolCallId, string content) => 
        messages ~= ep.message("tool", content, toolCallId);

    /// Converts this model into a human-readable JSON string.
    string toString()
    {
        JSONValue json = JSONValue.emptyObject;
        json["id"] = name;
        json["owned_by"] = owner;
        return json.toPrettyString;
    }

package:
    this(T)(T ep, 
        string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init, 
        JSONValue[] messages = [])
    {
        if (name in ep.models)
            this = ep.load(name, owner, options, messages);
        this.ep = ep;
        this.name = name;
        this.owner = owner;
        this.options = options;
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

    /// Sends a streaming request and yields chunks as they arrive.
    /// 
    /// If `think` is false then `"/no-think"` will be appended to the user prompt.
    void stream(void delegate(StreamChunk) F)(string prompt, bool think = true)
    {
        if (!think)
            prompt ~= "/no-think";
        // This is sort of unsafe since we don't sanity check but I don't care.
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = messages[0..1]~message("user", prompt);
        else
            messages = [message("user", prompt)];

        ep.stream!F(this);
    }
}
