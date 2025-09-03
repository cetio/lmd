module llmd.model;

import std.json;
import std.net.curl;
import std.conv;
import llmd.response;

public struct Options
{
    float temperature;
    float topP;
    int n = 0;
    string stop;
    int maxTokens = -1;
    float presencePenalty;
    float frequencyPenalty;
    int[string] logitBias;
    // TODO: bool noThink;
}

public struct Model
{
    string scheme = "http";
    string address;
    uint port;
    /// API key, may be empty if not required.
    string key;
    /// The name of the model which this represents.
    string name;
    JSONValue[] messages;
    Options options;

    void setSystemPrompt(string prompt)
    {
        messages = [buildMessage("system", prompt)]~messages;
    }

package:
    JSONValue buildMessage(string role, string content)
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["role"] = role;
        json.object["content"] = content;
        return json;
    }

    JSONValue buildLogitBias(int[string] logit_bias)
    {
        JSONValue json = JSONValue.emptyObject;
        foreach (k; logit_bias.keys)
            json.object['"'~k~'"'] = JSONValue(logit_bias[k]);
        return json;
    }

    bool sanity()
    {
        foreach (msg; messages)
        {
            if ("role" !in msg || "content" !in msg)
                return false;
        }
        return true;
    }

public:
    Response send(string prompt)
    {
        // This is sort of unsafe since we don't sanity check but I don't care.
        if (messages.length > 0 && messages[0]["role"].str == "system")
            messages = messages[0..1]~buildMessage("user", prompt);
        else
            messages = [buildMessage("user", prompt)];

        return completions!Response();
    }

    T completions(T)()
        if (is(T == Response) || is(T == JSONValue))
    {
        if (!sanity()) 
            throw new Exception("Failed sanity check. Message contents are invalid!");
            
        string url = scheme~"://"~address
            ~((port != 0 && port != 80 && port != 443) ? ':'~port.to!string : "")
            ~"/v1/chat/completions";
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
        HTTP http = HTTP(url);
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
