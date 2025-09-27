module examples.streaming;

import std.conv;
import std.string;
import std.array;
import core.thread;
import lmd.common.openai;

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    Model m = ep.load();
    ResponseStream stream = m.stream("What is the meaning of life?");
    
    // Horrible test.
    Thread streamThread = new Thread(() => stream.begin());
    streamThread.start();
    streamThread.join();
    
    Response resp = stream.next();
    assert((resp.model.name != "") || resp.exception !is null, 
           "Response should be either valid or have an error");
}
