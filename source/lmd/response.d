module lmd.response;

import std.string;
import std.json;
import lmd.exception;

/// Represents finish_reason or cause for the end of output by a model.
enum Exit
{
    Missing = 0,
    Length = 1,
    Max_Tokens = 1,
    Content_Filter = 2,
    Refusal = 2,
    Tool = 3,
    Pause = 3,
    Pause_Turn = 3,
    Stop = 4,
    End_Turn = 4,
    Stop_Sequence = 5,
    Unknown = 6
}

/// Represents a tool function definition.
struct Tool
{
    string type = "function";
    string name;
    string description;
    JSONValue parameters;
}

/// Represents a tool call made by the model.
struct ToolCall
{
    string id;
    string type = "function";
    string name;
    JSONValue arguments;
}

/// Represents tool choice configuration.
struct ToolChoice
{
    string type = "auto";
    string name;
}

/// Parses a string to retrieve the representation as enum Exit.
Exit asExit(string str)
{
    switch (str)
    {
    case null:
        return Exit.Missing;
    case "length":
        return Exit.Length;
    case "max_tokens":
        return Exit.Max_Tokens;
    case "content_filter":
        return Exit.Content_Filter;
    case "refusal":
        return Exit.Refusal;
    case "tool_call":
    case "tool_use":
    case "function_call":
        return Exit.Tool;
    case "pause":
        return Exit.Pause;
    case "pause_turn":
        return Exit.Pause_Turn;
    case "stop":
        return Exit.Stop;
    case "end_turn":
        return Exit.End_Turn;
    case "stop_sequence":
        return Exit.Stop_Sequence;
    default:
        return Exit.Unknown;
    }
}

/// Parses tool calls from a JSON array.
ToolCall[] parseToolCalls(JSONValue[] toolCallsArray)
{
    ToolCall[] result;
    foreach (toolCall; toolCallsArray)
    {
        ToolCall tc;
        tc.id = "id" in toolCall ? toolCall["id"].str : "";
        tc.type = "type" in toolCall ? toolCall["type"].str : "function";
        if ("function" in toolCall)
        {
            tc.name = "name" in toolCall["function"] ? toolCall["function"]["name"].str : "";
            tc.arguments = "arguments" in toolCall["function"] 
                ? toolCall["function"]["arguments"] 
                : JSONValue.emptyObject;
        }
        result ~= tc;
    }
    return result;
}

/// Parses content string and extracts think tags.
string[] parseContent(string content)
{
    if (content.indexOf("<think>") != -1)
    {
        string think = content[content.indexOf("<think>")..(content.indexOf("</think>") + 8)];
        string main = content[content.indexOf("</think>") + 8..$].strip;
        return [think] ~ main.splitLines();
    }
    return content.splitLines();
}

/// Parses a choice from JSON, handling both regular and streaming formats.
Choice parseChoice(JSONValue json, bool isStreaming = false)
{
    Choice item;
    
    // Handle content - either from "message" or "delta"
    JSONValue contentSource = isStreaming && "delta" in json 
        ? json["delta"] 
        : json["message"];
        
    if ("content" in contentSource)
        item.lines = parseContent(contentSource["content"].str);
    
    // Parse tool calls from the appropriate location
    if (isStreaming && "delta" in json && "tool_calls" in json["delta"])
        item.toolCalls = parseToolCalls(json["delta"]["tool_calls"].array);
    else if ("message" in json && "tool_calls" in json["message"])
        item.toolCalls = parseToolCalls(json["message"]["tool_calls"].array);
    else if ("tool_calls" in json)
        // Legacy format fallback
        item.toolCalls = parseToolCalls(json["tool_calls"].array);
    
    // Parse other fields
    item.exit = "finish_reason" in json ? asExit(json["finish_reason"].str) : Exit.Missing;
    item.logprobs = "logprobs" in json 
        ? json["logprobs"].isNull
            ? float.nan
            : json["logprobs"].floating
        : float.nan;
    
    return item;
}

/// Parses common response fields from JSON.
void parseCommonFields(JSONValue json, ref ModelException exception, 
    ref string fingerprint, ref string model, ref string id)
{
    if ("error" in json)
    {
        JSONValue error = json["error"].object;
        exception = new ModelException(
            error["code"].str, 
            error["message"].str, 
            error["param"].str,
            error["type"].str
        );
    }
    
    fingerprint = "system_fingerprint" in json ? json["system_fingerprint"].str : null;
    model = "model" in json ? json["model"].str : null;
    id = "id" in json ? json["id"].str : null;
}

struct Choice
{
    // Not adding "role" was a choice.
    string think;
    string[] lines;
    float logprobs = float.nan;
    Exit exit = Exit.Missing;
    ToolCall[] toolCalls;
    // TODO: choice selection and add that to messages
}

struct Response
{
    Choice[] choices;
    ModelException exception;
    long promptTokens;
    long completionTokens;
    long totalTokens;
    string fingerprint;
    string model;
    string id;
    //Kind kind;

    this(JSONValue json)
    {
        parseCommonFields(json, exception, fingerprint, model, id);
        
        if ("choices" in json)
        {
            foreach (choice; json["choices"].array)
            {
                Choice item = parseChoice(choice, false);
                if (item != Choice.init)
                    choices ~= item;
            }
        }

        if ("usage" in json)
        {
            promptTokens = json["usage"]["prompt_tokens"].integer;
            completionTokens = json["usage"]["completion_tokens"].integer;
            totalTokens = json["usage"]["total_tokens"].integer;
        }
    }

    bool bubble()
    {
        if (exception !is null)
            throw exception;
        return true;
    }
}

/// Represents a streaming chunk from the API.
struct StreamChunk
{
    Choice[] choices;
    ModelException exception;
    string fingerprint;
    string model;
    string id;
    bool done = false;

    this(JSONValue json)
    {
        parseCommonFields(json, exception, fingerprint, model, id);
        
        if ("choices" in json)
        {
            foreach (choice; json["choices"].array)
            {
                Choice item = parseChoice(choice, true);
                if (item != Choice.init)
                    choices ~= item;
            }
        }
        
        done = "done" in json ? json["done"].type == JSONType.true_ : false;
    }

    bool bubble()
    {
        if (exception !is null)
            throw exception;
        return true;
    }
}