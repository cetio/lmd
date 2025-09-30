module lmd.common.openai.context;

public import lmd.context;
import lmd.options;
import lmd.response;
import std.json;

class Context : IContext
{
    JSONValue[] messages;

    this(JSONValue[] messages = [])
    {
        this.messages = messages;
    }

    JSONValue toJSON()
    {
        JSONValue json = JSONValue.emptyObject;
        json.object["messages"] = JSONValue(messages);
        return json;
    }

    JSONValue completions(Options options)
    {
        JSONValue json = options.toJSON();
        json.object["messages"] = JSONValue(messages);
        return json;
    }

    JSONValue embeddings(Options options)
    {
        JSONValue json = options.toJSON();
        return json;
    }

    void add(string role, string content, string toolCallId = null)
    {
        JSONValue msg = JSONValue.emptyObject;
        msg.object["role"] = JSONValue(role);
        msg.object["content"] = JSONValue(content);
        if (toolCallId != null)
            msg.object["tool_call_id"] = JSONValue(toolCallId);
        messages ~= msg;
    }

    JSONValue[] getMessages()
    {
        return messages;
    }

    void clear()
    {
        messages = [];
    }
    
    void choose(Choice choice)
    {
        add("assistant", choice.content);
    }
}
