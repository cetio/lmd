module examples.tool;

import std.json;
import std.conv;
import lmd.common.openai;
import lmd.endpoint;
import lmd.model;
import lmd.tool;
import lmd.context;

unittest
{
    IEndpoint ep = cast(IEndpoint)(new OpenAI("http", "127.0.0.1", 1234));
    IModel model = ep.fetch("gpt-oss");
    
    JSONValue params = parseJSON(`{
        "type": "object",
        "properties": {
            "a": {"type": "number", "description": "First number"},
            "b": {"type": "number", "description": "Second number"}
        },
        "required": ["a", "b"]
    }`);
    
    model.tools().add("add_numbers", "Add two numbers together", params);
    
    Response resp = ep.complete!"gpt-oss"("What is 25 plus 17?");
    Completion comp = resp.select!Completion(0);
    Message msg = comp.context.messages[0];
    
    if (msg.isTool())
    {
        Tool toolCall = msg.tool();
        assert(toolCall.name == "add_numbers");
        assert(toolCall.argument!long("a") == 25);
        assert(toolCall.argument!long("b") == 17);
    }
}

