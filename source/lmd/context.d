module lmd.context;

import std.variant;
import core.exception;
import lmd.tool;

enum Role : string
{
    System = "system",
    User = "user",
    Assistant = "assistant",
    Tool = "tool",
    Function = "function"
}

struct Message
{
    Role role;
    Variant content;
    
    this(Role role, Variant content)
    {
        this.role = role;
        this.content = content;
    }
    
    string text()
    {
        return content.get!string;
    }
    
    Tool tool()
    {
        return content.get!Tool;
    }
    
    bool isText()
    {
        return content.type == typeid(string);
    }
    
    bool isTool()
    {
        return content.type == typeid(Tool);
    }
}

struct Context
{
    Message[] messages;
    
    this(Message[] messages)
    {
        this.messages = messages;
    }
    
    void add(T)(Role role, T val)
    {
        Variant var = val;
        messages ~= Message(role, var);
    }
    
    void add(T)(string role, T val)
    {
        add(cast(Role) role, val);
    }
    
    void clear()
    {
        messages = [];
    }

    Context merge(Context context)
    {
        messages ~= context.messages;
        return this;
    }
    
    Message first()
    {
        if (messages.length == 0)
            throw new RangeError();
        return messages[0];
    }
    
    Message last()
    {
        if (messages.length == 0)
            throw new RangeError();
        return messages[$-1];
    }
}