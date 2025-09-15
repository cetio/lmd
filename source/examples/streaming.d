module examples.streaming;

import std.conv;
import std.string;
import std.array;
import lmd.common.openai;
import mink.sync.job;

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    Model m = ep.load();
    ResponseStream stream = m.stream("What is the meaning of life?");
    async!(() => stream.begin())();
    assert(stream.next() != Response.init);
}
