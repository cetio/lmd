module examples.vibesort;

import std.conv;
import std.traits;
import std.string;
import lmd.common.openai;

T vibesort(T)(T arr, Model model)
    if (isDynamicArray!T || isStaticArray!T)
{
    // LLMs are a little special needs, so we do a little bit of extra formatting.
    Response resp = model.send(
        "Sort this array and only output the array in D syntax without any code blocks or additional formatting:"~arr.to!string
    );
    return resp.choices[0].pick(0)
        .replace("{", "[")
        .replace("}", "]")
    .to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    // Load the default/first model.
    Model m = ep.load();
    assert([2, 5, 3, 1].vibesort(m) == [1, 2, 3, 5]);
}