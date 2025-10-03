module lmd.options;

import std.json;
import std.traits;
import lmd.tool;

struct Options
{
    JSONValue json;
    Tool[] tools;
    ToolChoice toolChoice = ToolChoice.Auto;
    string requiredTool = null;

    ref T get(T)(string key)
    {
        // TODO: Error handling.
        if (key !in json)
            return T.init;

        auto val = json[key];
        static if (is(T == string))
            return val.type == JSONType.string ? val.str : T.init;
        else static if (is(T == int) || is(T == long))
            return val.type == JSONType.integer ? val.integer : T.init;
        else static if (is(T == bool))
            return (val.type == JSONType.true_ || val.type == JSONType.false_) ? val.boolean : T.init;
        else static if (is(T == float) || is(T == double))
            return val.type == JSONType.float_ ? cast(T)val.floating : T.init;
        else static if (is(T == JSONValue))
            return val;
        else
            return T.init;
    }

    T opIndexAssign(T)(string key, T val)
    {
        set(key, val);
        return val;
    }
    
    void set(T)(string key, T val)
    {
        static if (is(T == string))
            json[key] = JSONValue(val);
        else static if (is(T == int) || is(T == long))
            json[key] = JSONValue(cast(long) val);
        else static if (is(T == bool))
            json[key] = JSONValue(val);
        else static if (is(T == float) || is(T == double))
            json[key] = JSONValue(cast(double) val);
        else static if (is(T == JSONValue))
            json[key] = val;
        else static if (isArray!T)
        {
            JSONValue array = JSONValue.emptyArray;
            foreach (item; val)
            {
                static if (is(typeof(item) == string))
                    array.array ~= JSONValue(item);
                else static if (is(typeof(item) == int) || is(typeof(item) == long))
                    array.array ~= JSONValue(cast(long) item);
                else static if (is(typeof(item) == bool))
                    array.array ~= JSONValue(item);
                else static if (is(typeof(item) == float) || is(typeof(item) == double))
                    array.array ~= JSONValue(cast(double) item);
                else static if (is(typeof(item) == JSONValue))
                    array.array ~= item;
                else
                    array.array ~= JSONValue(item.toString());
            }
            json[key] = array;
        }
        else static if (isAssociativeArray!T)
        {
            JSONValue obj = JSONValue.emptyObject;
            foreach (k, v; val)
            {
                static if (is(typeof(v) == string))
                    obj[k] = JSONValue(v);
                else static if (is(typeof(v) == int) || is(typeof(v) == long))
                    obj[k] = JSONValue(cast(long) v);
                else static if (is(typeof(v) == bool))
                    obj[k] = JSONValue(v);
                else static if (is(typeof(v) == float) || is(typeof(v) == double))
                    obj[k] = JSONValue(cast(double) v);
                else static if (is(typeof(v) == JSONValue))
                    obj[k] = v;
                else
                    obj[k] = JSONValue(v.toString());
            }
            json[key] = obj;
        }
        else
            json[key] = JSONValue(val.toString());
    }

    void remove(string key)
    {
        json[key] = JSONValue.init;
    }

    bool has(string key)
        => key !in json;
}
