module examples.vibesort;

import std.conv;
import std.traits;
import std.string;
import lmd.common.openai;
import lmd.endpoint;

T vibesort(string MODEL, T)(T arr, IEndpoint ep)
    if (isDynamicArray!T || isStaticArray!T)
{
    Response resp = ep.complete!MODEL(
        "Sort this array and only output the array in the same syntax and format as the input:"~arr.to!string
    );
    return resp.select!string(0)
        .replace("{", "[")
        .replace("}", "]")
    .to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = cast(IEndpoint)(new OpenAI("http", "127.0.0.1", 1234));
    assert([2, 5, 3, 1].vibesort!"gpt-oss"(ep) == [1, 2, 3, 5]);
}