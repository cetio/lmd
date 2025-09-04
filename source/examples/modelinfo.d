module examples.modelinfo;

import std.stdio;
import llmd;

unittest
{
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    writeln(ep.available);
    writeln(ep.models);
}