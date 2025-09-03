module examples.vibesort;

import std.conv;
import std.traits;
import llmd.model;

T vibesort(T)(T arr, Model model)
    if (isDynamicArray!T || isStaticArray!T)
{
    return model.send(
        "Sort this array and only output the array in the correct original syntax:"~arr.to!string
    ).choices[0].lines[$-1].to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    Model model = Model(address: "127.0.0.1", port: 1234);
    assert([2, 5, 3, 1].vibesort(model) == [1, 2, 3, 5]);
}