module lmd.tool;

import std.json;

enum ToolChoice
{
    Auto,
    None,
    Required
}

void add(ref Tool[] arr, Tool tool)
{
    arr ~= tool;
}

void add(ref Tool[] arr, string name, string desc, JSONValue parameters = JSONValue.emptyObject)
{
    arr ~= Tool(name: name, desc: desc, parameters: parameters);
}

struct Tool
{
    string id = null;
    string type = "function";
    string name;
    string desc;
    union
    {
        JSONValue parameters;
        JSONValue arguments;
    }

    bool isCall() const
        => id.length > 0;

    bool isDefinition() const
        => id.length == 0 && name.length > 0;

    bool isValid() const
        => id.length > 0 && name.length > 0 && desc.length > 0;

    T argument(T)(string key) const
    {
        if (key !in arguments)
            return T.init;

        JSONValue arg = arguments[key];
        static if (is(T == string))
            return arg.type == JSONType.string ? arg.str : T.init;
        else static if (is(T == int) || is(T == long))
            return arg.type == JSONType.integer ? cast(T) arg.integer : T.init;
        else static if (is(T == bool))
            return (arg.type == JSONType.true_ || arg.type == JSONType.false_) ? arg.boolean : T.init;
        else static if (is(T == float) || is(T == double))
            return arg.type == JSONType.float_ ? cast(T) arg.floating : T.init;
        else
            return T.init;
    }
}
