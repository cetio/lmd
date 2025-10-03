module examples.streaming;

import std.conv;
import std.string;
import std.array;
import core.thread;
import lmd.common.openai;
import std.functional;
import std.stdio;

unittest
{
    assert(false);
    // LMStudio 127.0.0.1
    // IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    // Model m = ep.load();
    // ResponseStream stream = m.stream("What is the meaning of life?", (resp) => writeln(resp.choices[0]));
    // stream.begin();
    
    // Thread th = new Thread(() => stream.begin());
    // th.start();
    
    // th.join();
}
