module lmd.options;

import std.json;

interface IOptions
{
    JSONValue toJSON();
}