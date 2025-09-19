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
    
    bool state = async!(() => stream.begin())().await();
    
    // This is fine.
    Response resp = stream.next();
    assert((state && resp.model.name != "") || resp.exception !is null, 
           "Response should be either valid or have an error");
}
