module llmd.response;

import std.string;
import std.json;

enum Finish
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

Finish asFinish(string str)
{
    switch (str)
    {
    case null:
        return Finish.Missing;
    case "length":
        return Finish.Length;
    case "max_tokens":
        return Finish.Max_Tokens;
    case "content_filter":
        return Finish.Content_Filter;
    case "refusal":
        return Finish.Refusal;
    case "tool_call":
    case "tool_use":
    case "function_call":
        return Finish.Tool;
    case "pause":
        return Finish.Pause;
    case "pause_turn":
        return Finish.Pause_Turn;
    case "stop":
        return Finish.Stop;
    case "end_turn":
        return Finish.End_Turn;
    case "stop_sequence":
        return Finish.Stop_Sequence;
    default:
        return Finish.Unknown;
    }
}

struct Choice
{
    // Not adding "role" was a choice.
    string think;
    string[] lines;
    float logprobs = float.nan;
    Finish fin = Finish.Missing;
    // TODO: tool_calls and tools
}

struct Response
{
    Choice[] choices;
    long promptTokens;
    long completionTokens;
    long totalTokens;
    string fingerprint;

    this(JSONValue json)
    {
        if ("choices" in json)
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
                        str = str[str.indexOf("</think>") + 8..$];
                    }
                    item.lines = str.splitLines();
                }

                item.fin = "finish_reason" in choice ? asFinish(choice["finish_reason"].str) : Finish.Missing;
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
    }
}