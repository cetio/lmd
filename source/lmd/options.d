module lmd.options;

import std.json;
import std.traits;
import lmd.tool;

struct Options
{
package:
    JSONValue _json = JSONValue.emptyObject;

public:
    T get(T)(string key)
    {
        if (key !in _json.object)
            return T.init;

        auto value = _json[key];
        static if (is(T == string))
            return value.type == JSONType.string ? value.str : T.init;
        else static if (is(T == int) || is(T == long))
            return value.type == JSONType.integer ? cast(T) value.integer : T.init;
        else static if (is(T == bool))
            return (value.type == JSONType.true_ || value.type == JSONType.false_) ? value.boolean : T.init;
        else static if (is(T == float) || is(T == double))
            return value.type == JSONType.float_ ? cast(T) value.floating : T.init;
        else static if (is(T == JSONValue))
            return value;
        else
            return T.init;
    }

    void set(T)(string key, T value)
    {
        static if (is(T == string))
            _json.object[key] = JSONValue(value);
        else static if (is(T == int) || is(T == long))
            _json.object[key] = JSONValue(cast(long) value);
        else static if (is(T == bool))
            _json.object[key] = JSONValue(value);
        else static if (is(T == float) || is(T == double))
            _json.object[key] = JSONValue(cast(double) value);
        else static if (is(T == JSONValue))
            _json.object[key] = value;
        else static if (isArray!T)
        {
            JSONValue array = JSONValue.emptyArray;
            foreach (item; value)
            {
                static if (is(typeof(item.toJSON())))
                    array.array ~= item.toJSON();
                else static if (is(typeof(item) == string))
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
            _json.object[key] = array;
        }
        else static if (isAssociativeArray!T)
        {
            JSONValue obj = JSONValue.emptyObject;
            foreach (k, v; value)
            {
                static if (is(typeof(v) == string))
                    obj.object[k] = JSONValue(v);
                else static if (is(typeof(v) == int) || is(typeof(v) == long))
                    obj.object[k] = JSONValue(cast(long) v);
                else static if (is(typeof(v) == bool))
                    obj.object[k] = JSONValue(v);
                else static if (is(typeof(v) == float) || is(typeof(v) == double))
                    obj.object[k] = JSONValue(cast(double) v);
                else static if (is(typeof(v) == JSONValue))
                    obj.object[k] = v;
                else
                    obj.object[k] = JSONValue(v.toString());
            }
            _json.object[key] = obj;
        }
        else
            _json.object[key] = JSONValue(value.toString());
    }

    void remove(string key)
    {
        _json.object.remove(key);
    }

    bool has(string key)
    {
        return (key in _json.object) !is null;
    }


    JSONValue toJSON()
    {
        return _json;
    }
}