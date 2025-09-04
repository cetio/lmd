module examples.vibesort;

import std.conv;
import std.traits;
import llmd;
import std.stdio;

T vibesort(T)(T arr, Model model)
    if (isDynamicArray!T || isStaticArray!T)
{
    Response resp = model.send(
        "Sort this array and only output the array in D syntax without any code blocks or additional formatting:"~arr.to!string
    );
    writeln(resp);
    return resp.choices[0].lines[$-1].to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = endpoint!("http", "127.0.0.1", 1234);
    Model m = ep.load("text-embedding-nomic-embed-text-v1.5");
    writeln(m);
    assert([2, 5, 3, 1].vibesort(m) == [1, 2, 3, 5]);
}