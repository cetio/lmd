module lmd.response;

import std.string;
import std.json;
import lmd.exception;
import lmd.model;
import core.atomic;
import core.thread;

/// Represents `finish_reason` or cause for the end of output by a model.
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

struct Choice
{
    Model model;
    union
    {
        struct
        {
            string think;
            string content;
        }
        float[] embedding;
    }
    float logprobs = float.nan;
    Exit exit = Exit.Missing;
    ToolCall[] toolCalls;

    this(Model model, JSONValue json, bool streaming = false)
    {
        this.model = model;
        JSONValue raw = streaming && "delta" in json 
            ? json["delta"] 
            : json["message"];
            
        if ("content" in raw)
        {
            if (raw["content"].str.indexOf("<think>") != -1)
            {
                content = raw["content"].str;

                think = content[content.indexOf("<think>")..(content.indexOf("</think>") + 8)];
                content = content[content.indexOf("</think>") + 8..$];
            }
            else
                content = raw["content"].str;
        }
        
        // Parse tool calls from the appropriate location
        if (streaming && "delta" in json && "tool_calls" in json["delta"])
            toolCalls = parseToolCalls(json["delta"]["tool_calls"].array);
        else if ("message" in json && "tool_calls" in json["message"])
            toolCalls = parseToolCalls(json["message"]["tool_calls"].array);
        else if ("tool_calls" in json)
            // Legacy format fallback
            toolCalls = parseToolCalls(json["tool_calls"].array);
        
        // Parse other fields
        exit = "finish_reason" in json ? asExit(json["finish_reason"].str) : Exit.Missing;
        logprobs = "logprobs" in json 
            ? json["logprobs"].isNull
                ? float.nan
                : json["logprobs"].floating
            : float.nan;
        
        if ("embedding" in json)
        {
            embedding = new float[json["embedding"].array.length];
            foreach (i, val; json["embedding"].array)
                embedding[i] = val.floating;
        }
    }

    string pick()
    {
        scope (exit) model.choose(this);
        return content;
    }

    /// Picks a line from the content and chooses this choice for the model.
    string pick(int index)
    {
        scope (exit) model.choose(this);
        return content.strip.splitLines()[index];
    }
}

// TODO: Implement kind to determine the variety of response.
// TODO: Response should be semi-agnostic to the endpoint.
struct Response
{
    Model model;
    Choice[] choices;
    ModelException exception;
    long promptTokens;
    long completionTokens;
    long totalTokens;
    string fingerprint;
    string id;
    //Kind kind;

    this(Model model, JSONValue json)
    {
        this.model = model;
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
        id = "id" in json ? json["id"].str : null;
        
        if ("choices" in json)
        {
            foreach (choice; json["choices"].array)
            {
                Choice item = Choice(model, choice, false);
                if (item != Choice.init)
                    choices ~= item;
            }
        }
        else if ("data" in json)
        {
            // Handle embeddings API response format
            foreach (embeddingData; json["data"].array)
            {
                Choice item = Choice(model, embeddingData, false);
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

class ResponseStream
{
package:
    void delegate(ResponseStream) _commence;

public:
    Response response;
    shared bool responseReady;
    void delegate(Response) callback;
    Model model;

    this(Model model, void delegate(Response) callback)
    {
        this.callback = callback;
        this.response = Response.init;
        this.responseReady = false;
        this.model = model;
    }

    Response next()
    {
        if (_commence is null)
            throw new ModelException(
                "not_initialized", 
                "Stream not initialized", 
                "stream", 
                "invalid_request_error"
            );
        
        while (!atomicLoad!(MemoryOrder.acq)(responseReady))
            Thread.yield();
        
        atomicFence!(MemoryOrder.acq);
        return response;
    }
    
    Response[] collect(int n)
    {
        Response[] results;
        for (int i = 0; i < n; i++)
            results ~= next();
        return results;
    }

    void begin()
    {
        _commence(this);
    }

    void begin(void delegate(Response) callback)()
    {
        this.callback = callback;
        _commence(this);
    }

    Response last()
    {
        _commence(this);
        // Wait for response to be ready
        while (!atomicLoad!(MemoryOrder.acq)(responseReady))
        {
            // Spin wait
        }
        
        atomicFence!(MemoryOrder.acq);
        return response;
    }

    // Internal method for updating the response atomically
    package void updateResponse(Response newResponse)
    {
        // Update the response
        response = newResponse;
        
        // Memory fence to ensure the response is written before the flag
        atomicFence!(MemoryOrder.rel);
        
        // Atomically set the ready flag
        atomicStore!(MemoryOrder.rel)(responseReady, true);
    }
}