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
    void setSystemPrompt(string prompt)
    {
        messages = [buildMessage("system", prompt)]~messages;
    }

    /// Converts this model into a human-readable JSON string.
    string toString()
    {
        JSONValue json = JSONValue.emptyObject;
        json["id"] = name;
        json["owned_by"] = owner;
        return json.toPrettyString;
    }

package:
    /// Alias for the endpoint API key.
    alias key = ep.key;

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

    /// Builds a chat message object with the specified role and content.
    JSONValue buildMessage(string role, string content)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["role"] = role;
        json.object["content"] = content;
        return json;
    }

    /// Builds a JSON representation of logit bias mappings.
    JSONValue buildLogitBias(int[string] logit_bias)
    {
        JSONValue json = JSONValue.emptyObject;
        foreach (k; logit_bias.keys)
            json.object['"'~k~'"'] = JSONValue(logit_bias[k]);
        return json;
    }

    /// Performs basic message validation and registers the model with the endpoint if missing.
    bool sanity()
    {
        if (name !in ep.models)
            ep.models[name] = this;

        foreach (msg; messages)
        {
            if ("role" !in msg || "content" !in msg)
                return false;
        }
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
            messages = messages[0..1]~buildMessage("user", prompt);
        else
            messages = [buildMessage("user", prompt)];

        return completions!Response();
    }

    /// Requests a completion from the model using the current state and options.
    T completions(T)()
        if (is(T == Response) || is(T == JSONValue))
    {
        if (!sanity()) 
            throw new Exception("Failed sanity check. Message contents are invalid!");

        JSONValue json = JSONValue.emptyObject;
        json.object["model"] = JSONValue(name);
        json.object["messages"] = messages;
        if (options.temperature !is float.nan) json.object["temperature"] = JSONValue(options.temperature);
        if (options.topP !is float.nan) json.object["top_p"] = JSONValue(options.topP);
        if (options.n != 0) json.object["n"] = JSONValue(options.n);
        if (options.stop != null) json.object["stop"] = JSONValue(options.stop);
        if (options.presencePenalty !is float.nan) json.object["presence_penalty"] = JSONValue(options.presencePenalty);
        if (options.frequencyPenalty !is float.nan) json.object["frequency_penalty"] = JSONValue(options.frequencyPenalty);
        if (options.logitBias != null) json.object["logit_bias"] = JSONValue(options.logitBias);
        json.object["max_tokens"] = JSONValue(options.maxTokens);
        // Streaming is not currently supported.
        json.object["stream"] = JSONValue(false);

        // This is the worst networking I have seen in my entire life.
        HTTP http = HTTP(ep.url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) { resp = cast(string)data; return data.length; });

        static if (is(T == Response))
            return http.perform() == 0 ? Response(resp.parseJSON) : Response.init;
        else static if (is(T == JSONValue))
            return http.perform() == 0 ? resp.parseJSON : JSONValue.emptyObject;
    }
}
