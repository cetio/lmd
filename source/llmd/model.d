module llmd.model;

import std.json;
import std.net.curl;
import std.conv;
import std.algorithm;
import std.datetime;
import std.array;
import llmd.response;
import llmd.endpoint;

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
}

// TODO: Allow this to be abstracted.
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
    JSONValue[] setSystemPrompt(string prompt) => messages = [message("system", prompt)]~messages;

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

    JSONValue message(string role, string content) => ep.message(role, content);

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
        if (!think)
            prompt ~= "/no-think";
        // This is sort of unsafe since we don't sanity check but I don't care.
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = messages[0..1]~message("user", prompt);
        else
            messages = [message("user", prompt)];

        return ep.completions(this);
    }
}
