module examples.tooling;

import std.conv;
import std.json;
import std.string;
import lmd.common.openai;
import lmd.tool;

unittest
{
    // TODO:
    assert(true, "Tooling tests not yet implemented");
    // // Create endpoint and model
    // IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    // Model m = ep.load();

    // m.options["registry"].add("calculate", "Perform basic mathematical calculations",
    //     JSONValue([
    //     "type": JSONValue("object"),
    //     "properties": JSONValue([
    //         "expression": JSONValue([
    //             "type": JSONValue("string"),
    //             "description": JSONValue("Mathematical expression to evaluate")
    //         ])
    //     ]),
    //     "required": JSONValue(["expression"])
    // ])
    // );

    // Response resp = m.send("Calculate 15 * 3 + 7 and only return the result");

    // assert(resp.error is null, "Should not have error");
    // assert(resp.choices.length > 0, "Should have choices");

    // assert(resp.choices[0].toolCalls.length > 0, "Should make tool call");
    // assert(resp.choices[0].toolCalls[0].name == "calculate", "Should call calculate tool");

    // assert(resp.choices[0].pick(0) == (15 * 3 + 7).to!string, "Should mention calculated result 52");
}
