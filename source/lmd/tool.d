module lmd.tool;

import std.json;

enum ToolChoice
{
    Auto,
    None,
    Required
}

struct Tool
{
    string type = "function";
    string name;
    string description;
    JSONValue parameters;

    // Call-specific fields.
    string id = "";
    JSONValue arguments;

package:
    // TODO: Verify that the library is safe.
    // TODO: Tool workflows using D functions.
    this(JSONValue json)
    {
        id = "id" in json ? json["id"].str : "";
        type = "type" in json ? json["type"].str : "function";
        if ("function" in json)
        {
            name = "name" in json["function"] ? json["function"]["name"].str : "";
            if ("arguments" in json["function"])
            {
                auto args = json["function"]["arguments"];
                if (args.type == JSONType.string)
                    arguments = parseJSON(args.str);
                else
                    arguments = args;
            }
            else
            {
                arguments = JSONValue.emptyObject;
            }
        }
    }

public:
    this(string name, string description, JSONValue parameters = JSONValue.emptyObject)
    {
        this.name = name;
        this.description = description;
        this.parameters = parameters;
    }

    bool isCall() const
        => id.length > 0;

    bool isDefinition() const
        => id.length == 0 && name.length > 0;

    bool isValid() const
        => id.length > 0 && name.length > 0 && description.length > 0;

    T argument(T)(string key) const
    {
        if (key !in arguments.object)
            return T.init;

        auto arg = arguments[key];
        static if (is(T == string))
            return arg.type == JSONType.string ? arg.str : T.init;
        else static if (is(T == int) || is(T == long))
            return arg.type == JSONType.integer ? cast(T) arg.integer : T.init;
        else static if (is(T == bool))
            return (arg.type == JSONType.true_ || arg.type == JSONType.false_) ? arg.boolean
                : T.init;
        else static if (is(T == float) || is(T == double))
            return arg.type == JSONType.float_ ? cast(T) arg.floating : T.init;
        else
            return T.init;
    }


    JSONValue toJSON() const
    {
        if (isCall())
        {
            JSONValue json = JSONValue.emptyObject;
            json.object["id"] = JSONValue(id);
            json.object["type"] = JSONValue(type);
            json.object["function"] = JSONValue.emptyObject;
            json.object["function"].object["name"] = JSONValue(name);
            json.object["function"].object["arguments"] = arguments;
            return json;
        }
        else
        {
            JSONValue json = JSONValue.emptyObject;
            json.object["type"] = JSONValue(type);
            json.object["function"] = JSONValue.emptyObject;
            json.object["function"].object["name"] = JSONValue(name);
            json.object["function"].object["description"] = JSONValue(description);
            json.object["function"].object["parameters"] = parameters;
            return json;
        }
    }
}

struct ToolRegistry
{
    Tool[] tools;
    ToolChoice toolChoice = ToolChoice.Auto;
    string requiredTool = "";

    Tool[] add(Tool tool) =>
        tools ~= tool;

    Tool[] add(string name, string description, JSONValue parameters = JSONValue.emptyObject) =>
        tools ~= Tool(name, description, parameters);

    JSONValue toJSON() const
    {
        if (toolChoice == ToolChoice.Auto)
            return JSONValue.init;
        else if (toolChoice == ToolChoice.None)
            return JSONValue("none");
        else if (toolChoice == ToolChoice.Required)
        {
            JSONValue json = JSONValue.emptyObject;
            json.object["type"] = JSONValue("function");
            json.object["function"] = JSONValue.emptyObject;
            json.object["function"].object["name"] = JSONValue(requiredTool);
            return json;
        }
        return JSONValue.init;
    }

    package JSONValue getToolsJSON() const
    {
        if (tools.length == 0)
            return JSONValue.init;

        JSONValue toolsArray = JSONValue.emptyArray;
        foreach (tool; tools)
        {
            toolsArray.array ~= tool.toJSON();
        }
        return toolsArray;
    }
}
