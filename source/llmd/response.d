module llmd.response;

import std.string;
import std.json;
import llmd.exception;

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

struct Choice
{
    // Not adding "role" was a choice.
    string think;
    string[] lines;
    float logprobs = float.nan;
    Exit exit = Exit.Missing;
    // TODO: tool_calls and tools
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
        else if ("choices" in json)
        {
            foreach (choice; json["choices"].array)
            {
                Choice item;
                if ("message" in choice)
                {
                    string str = choice["message"]["content"].str;
                    if (str.indexOf("<think>") != -1)
                    {
                        item.think = str[str.indexOf("<think>")..(str.indexOf("</think>") + 8)];
                        str = str[str.indexOf("</think>") + 8..$].strip;
                    }
                    item.lines = str.splitLines();
                }

                item.exit = "finish_reason" in choice ? asExit(choice["finish_reason"].str) : Exit.Missing;
                item.logprobs = "logprobs" in choice 
                    ? choice["logprobs"].isNull
                        ? float.nan
                        : choice["logprobs"].floating
                    : float.nan;

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

        fingerprint = "system_fingerprint" in json ? json["system_fingerprint"].str : null;
        model = "model" in json ? json["model"].str : null;
        id = "id" in json ? json["id"].str : null;
    }

    bool bubble()
    {
        if (exception !is null)
            throw exception;
        return true;
    }
}