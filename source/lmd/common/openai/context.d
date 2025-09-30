module lmd.common.openai.context;

public import lmd.context;
import lmd.options;
import lmd.response;
import std.json;

class Context : IContext
{
    JSONValue[] _msgs;

    this(JSONValue[] messages = [])
    {
        _msgs = messages;
    }

    ref JSONValue[] messages()
        => _msgs;
    
    void choose(Choice choice)
        => add("assistant", choice.content);

    void add(string role, string content, string toolCallId = null)
    {
        JSONValue msg = JSONValue.emptyObject;
        msg.object["role"] = JSONValue(role);
        msg.object["content"] = JSONValue(content);
        if (toolCallId != null)
            msg.object["tool_call_id"] = JSONValue(toolCallId);
        _msgs ~= msg;
    }

    void clear()
    {
        _msgs = [];
    }

    JSONValue completions(Options options)
    {
        // TODO: Sanity checking.
        JSONValue json = options.toJSON();
        json.object["messages"] = JSONValue(_msgs);
        return json;
    }

    JSONValue embeddings(Options options)
    {
        JSONValue json = options.toJSON();
        return json;
    }
}
