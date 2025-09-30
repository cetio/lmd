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
    
    Thread th = new Thread(() => stream.begin());
    th.start();
    
    Response resp = stream.next();
    assert((resp.model.name != "") || resp.error !is null, 
           "Response should be either valid or have an error");
    
    th.join();
}
