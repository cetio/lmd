module examples.turns;

import std.conv;
import std.string;
import std.array;
import std.json;
import lmd.common.openai;

unittest
{
    // Create endpoint and model
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    Model m = ep.load();
    
    // Simple conversation setup
    m.context.clear();
    m.context.add("system", "You are a helpful assistant.");
    
    // Add user message
    m.context.add("user", "Hello, my name is Alice.");
    
    // Add assistant response
    m.context.add("assistant", "Hello Alice! Nice to meet you.");
    
    // Continue conversation
    m.context.add("user", "What's my name?");
    m.context.add("assistant", "Your name is Alice, as you just told me!");
    
    // Test tool usage
    m.context.add("tool", "Weather is sunny and 72°F", "weather_call_123");
    m.context.add("assistant", "Thank you for the weather information.");
    
    // Verify conversation state
    JSONValue[] messages = m.context.getMessages();
    assert(messages.length >= 1, "Should have at least 1 message in conversation");
    assert(messages[0]["role"].str == "system", "First message should be system");
    
    // Test choice handling
    Choice testChoice = Choice(m, JSONValue([
        "message": JSONValue([
            "role": JSONValue("assistant"),
            "content": JSONValue("I can help you with that.")
        ])
    ]));
    
    // Test choice picking
    string response = testChoice.pick();
    assert(response == "I can help you with that.", "Choice should return correct content");
    
    // Test line picking
    Choice multiLineChoice = Choice(m, JSONValue([
        "message": JSONValue([
            "role": JSONValue("assistant"),
            "content": JSONValue("Option 1\nOption 2\nOption 3")
        ])
    ]));
    
    string secondOption = multiLineChoice.pick(1);
    assert(secondOption == "Option 2", "Should pick the correct line");
}
