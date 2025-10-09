module lmd.common.openai.model;

import std.json;
import std.variant;
import std.conv : to;
import lmd.model;
import lmd.response;
import lmd.context;
import lmd.tool;

/// This should be accessed through `OpenAI.Model` rather than directly.
class OpenAIModel : IModel
{
    string _key;
    string _name;
    string _owner;

    double temperature = double.nan;
    double topP = double.nan;
    long maxTokens = 0;
    string[] stop;
    double presencePenalty = double.nan;
    double frequencyPenalty = double.nan;
    long n = 1;
    bool stream = false;
    long[long] logitBias;
    long seed = 0;
    string encodingFormat = "float";
    long dimensions = 0;
    Tool[] _tools;

    this(string name, string owner = null, string key = null)
    {
        _name = name;
        _owner = owner;
        _key = key;
    }

    ref string key()
        => _key;

    ref string name()
        => _name;

    ref string owner()
        => _owner;

    ref Tool[] tools()
        => _tools;

package:
    JSONValue toChatJSON(Variant data)
    {
        JSONValue json = JSONValue.emptyObject;
        json["model"] = JSONValue(_name);

        // This logic is very dense but I cannot be assed.
        if (temperature !is double.nan) json["temperature"] = JSONValue(temperature);
        if (topP !is double.nan) json["top_p"] = JSONValue(topP);
        if (maxTokens > 0) json["max_tokens"] = JSONValue(maxTokens);
        if (stop.length > 0)
        {
            JSONValue arr = JSONValue.emptyArray;
            foreach (s; stop) arr.array ~= JSONValue(s);
            json["stop"] = arr;
        }
        if (presencePenalty !is double.nan) json["presence_penalty"] = JSONValue(presencePenalty);
        if (frequencyPenalty !is double.nan) json["frequency_penalty"] = JSONValue(frequencyPenalty);
        if (n > 1) json["n"] = JSONValue(n);
        if (stream) json["stream"] = JSONValue(stream);
        if (logitBias.length > 0)
        {
            JSONValue bias = JSONValue.emptyObject;
            foreach (k, v; logitBias) bias[k.to!string] = JSONValue(v);
            json["logit_bias"] = bias;
        }
        if (seed > 0) json["seed"] = JSONValue(seed);
        if (_tools.length > 0)
        {
            JSONValue tools = JSONValue.emptyArray;
            foreach (tool; _tools)
            {
                JSONValue t = JSONValue.emptyObject;
                t["type"] = JSONValue(tool.type);
                t["function"] = JSONValue.emptyObject;
                t["function"]["name"] = JSONValue(tool.name);
                t["function"]["desc"] = JSONValue(tool.desc);
                t["function"]["parameters"] = tool.parameters;
                tools.array ~= t;
            }
            json["tools"] = tools;
        }

        JSONValue messages = JSONValue.emptyArray;
        // TODO: Better type support.
        if (data.type == typeid(Context))
        {
            Context ctx = data.get!Context;
            foreach (msg; ctx.messages)
            {
                JSONValue m = JSONValue.emptyObject;
                m["role"] = JSONValue(cast(string)msg.role);
                if (msg.isText())
                    m["content"] = JSONValue(msg.text());
                messages.array ~= m;
            }
        }
        else if (data.type == typeid(string))
        {
            JSONValue m = JSONValue.emptyObject;
            m["role"] = JSONValue("user");
            m["content"] = JSONValue(data.get!string);
            messages.array ~= m;
        }
        json["messages"] = messages;
        return json;
    }

    JSONValue toEmbeddingsJSON(Variant data)
    {
        JSONValue json = JSONValue.emptyObject;
        json["model"] = JSONValue(_name);
        if (data.type == typeid(string))
            json["input"] = JSONValue(data.get!string);
        else
            json["input"] = JSONValue("");
        if (encodingFormat != "float") json["encoding_format"] = JSONValue(encodingFormat);
        if (dimensions > 0) json["dimensions"] = JSONValue(dimensions);
        return json;
    }

    Response parseChatResponse(JSONValue json)
    {
        Response ret;
        ret.model = ("model" in json) ? json["model"].str : _name;
        ret.kind = ResponseKind.ChatCompletions;

        if ("error" in json)
        {
            ret.error = new Exception(("message" in json["error"]) ? json["error"]["message"].str : "error");
            return ret;
        }

        Completion[] comps;
        if ("choices" in json)
        {
            foreach (c; json["choices"].array)
            {
                Completion comp;
                Context ctx;
                JSONValue msg = ("message" in c) ? c["message"] : c["delta"];

                // TODO: If reasoning or think tag is present, it the content should be an array of strings.
                string content = ("content" in msg && !msg["content"].isNull) ? msg["content"].str : null;
                if (content !is null)
                    ctx.add(Role.Assistant, content);
                
                if ("tool_calls" in msg && msg["tool_calls"].type == JSONType.array)
                {
                    foreach (tc; msg["tool_calls"].array)
                    {
                        // TODO: I don't like this.
                        Tool tool = Tool(
                            id: ("id" in tc) ? tc["id"].str : null, 
                            type: ("type" in tc) ? tc["type"].str : "function"
                        );
                        
                        if ("function" in tc)
                        {
                            JSONValue func = tc["function"];
                            tool.name = ("name" in func) ? func["name"].str : null;
                            if ("arguments" in func)
                                tool.arguments = func["arguments"].str.parseJSON();
                        }
                        
                        ctx.add(Role.Tool, tool);
                    }
                }
                
                comp.context = ctx;
                comp.finishReason = ("finish_reason" in c && !c["finish_reason"].isNull)
                    ? cast(FinishReason)c["finish_reason"].str
                    : FinishReason.Unknown;
                comp.logProbs = float.nan;
                comps ~= comp;
            }
        }
        ret.data = Variant(comps);
        return ret;
    }

    Response parseEmbeddingsResponse(JSONValue json)
    {
        Response ret;
        ret.model = ("model" in json) ? json["model"].str : _name;
        ret.kind = ResponseKind.Embedding;

        if ("error" in json)
        {
            ret.error = new Exception(("message" in json["error"]) ? json["error"]["message"].str : "error");
            return ret;
        }

        Embedding emb;
        if ("data" in json && json["data"].array.length > 0)
        {
            JSONValue data = json["data"].array[0];
            emb.index = ("index" in data) ? data["index"].integer : 0;
            if ("embedding" in data)
            {
                foreach (v; data["embedding"].array)
                    emb.value ~= cast(float)v.floating;
            }
        }
        ret.data = Variant(emb);
        return ret;
    }
}

