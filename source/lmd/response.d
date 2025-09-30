module lmd.response;

import std.string;
import std.json;
import lmd.exception;
import lmd.model;
import lmd.tool;
import lmd.context;
import core.atomic;
import core.thread;
import std.traits;

/// Represents `finish_reason` or cause for the end of output by a model.
enum FinishReason
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


/// Parses a string to retrieve the representation as enum FinishReason.
FinishReason asExit(string str)
{
    switch (str)
    {
    case null:
        return FinishReason.Missing;
    case "length":
        return FinishReason.Length;
    case "max_tokens":
        return FinishReason.Max_Tokens;
    case "content_filter":
        return FinishReason.Content_Filter;
    case "refusal":
        return FinishReason.Refusal;
    case "tool_call":
    case "tool_use":
    case "function_call":
        return FinishReason.Tool;
    case "pause":
        return FinishReason.Pause;
    case "pause_turn":
        return FinishReason.Pause_Turn;
    case "stop":
        return FinishReason.Stop;
    case "end_turn":
        return FinishReason.End_Turn;
    case "stop_sequence":
        return FinishReason.Stop_Sequence;
    default:
        return FinishReason.Unknown;
    }
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
    FinishReason exit = FinishReason.Missing;
    // TODO: Reconsider naming?
    Tool[] toolCalls;

    Tool[] parseToolCalls(JSONValue[] json)
    {
        Tool[] ret;
        foreach (call; json)
            ret ~= Tool(call);
        return ret;
    }

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

        if (streaming && "delta" in json && "tool_calls" in json["delta"])
            toolCalls = parseToolCalls(json["delta"]["tool_calls"].array);
        else if ("message" in json && "tool_calls" in json["message"])
            toolCalls = parseToolCalls(json["message"]["tool_calls"].array);
        else if ("tool_calls" in json)
            // Legacy format fallback
            toolCalls = parseToolCalls(json["tool_calls"].array);

        exit = "finish_reason" in json ? asExit(json["finish_reason"].str) : FinishReason.Missing;
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
        scope (exit) model.context.choose(this);
        return content;
    }

    /// Picks a line from the content and chooses this choice for the model.
    string pick(int index)
    {
        scope (exit) model.choose(this);
        return content.strip.splitLines()[index];
    }
}

// TODO: Add response type classification (completion, embedding, etc.)
struct Response
{
    Model model;
    Choice[] choices;
    ModelException error = null;
    long promptTokens;
    long completionTokens;
    long totalTokens;
    string fingerprint;
    string id;
    //Kind kind;

    this(Model model, ModelException error)
    {
        this.model = model;
        this.error = error;
    }

    this(F = void)(Model model, JSONValue json)
        if (isCallable!F || is(F == void))
    {
        this.model = model;
        static if (isCallable!F)
        {
            this = F(model, json);
            return;
        }

        if ("error" in json)
        {
            this.error = new ModelException(
                json["error"]["code"].str,
                json["error"]["message"].str,
                json["error"]["param"].str,
                json["error"]["type"].str
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
        if (error !is null)
            throw error;
        return choices.length > 0;
    }
}

class ResponseStream
{
package:
    void delegate(ResponseStream) _commence;
    shared bool flag;

public:
    Response response;
    void delegate(Response) callback;
    Model model;

    this(Model model, void delegate(Response) callback)
    {
        this.callback = callback;
        this.response = Response.init;
        this.flag = false;
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

        // NOTE: It is unlikely that this will be a problem burning CPU, since the model will probably not take too long to respond, but it could be a problem.
        while (!atomicLoad!(MemoryOrder.acq)(flag))
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
        while (!atomicLoad!(MemoryOrder.acq)(flag))
            Thread.yield();

        atomicFence!(MemoryOrder.acq);
        return response;
    }

    void update(Response val)
    {
        if (response.choices.length > 0 && val.choices.length > 0)
        {
            foreach (i, choice; val.choices)
            {
                if (i < response.choices.length)
                {
                    if (choice.content.length > 0)
                        response.choices[i].content ~= choice.content;
                    if (choice.toolCalls.length > 0)
                        response.choices[i].toolCalls ~= choice.toolCalls;
                    if (choice.exit != FinishReason.Missing)
                        response.choices[i].exit = choice.exit;
                }
                else
                {
                    response.choices ~= choice;
                }
            }
        }
        else
        {
            response = val;
        }
        atomicFence!(MemoryOrder.rel);
        atomicStore!(MemoryOrder.rel)(flag, true);
    }
}
