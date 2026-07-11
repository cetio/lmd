/// Qwen-compatible provider implementation with XML tool-call fallback.
module intuit.provider.qwen;

public import intuit.provider;
import intuit.provider.openai;
import intuit.core.model;
import intuit.core.response;
import intuit.core.tool;

import std.algorithm.searching : canFind;
import std.conv : to;
import std.format : format;
import std.json : JSONType, JSONValue, parseJSON;
import std.regex;
import std.string : indexOf, strip;

/// Qwen-compatible LLM provider, extending OpenAI with XML tool-call extraction.
class Qwen : OpenAI
{
    /**
     * Constructs a Qwen provider.
     *
     * The provided URL is used as-is and the caller is responsible for
     * supplying the correct base URL for the endpoint.
     *
     * Params:
     *  url = The base URL of the endpoint.
     *  key = Optional API key.
     *  name = Display name for the provider.
     */
    this(string url, string key = null, string name = "Qwen")
    {
        super(url, key, name);
    }

    override JSONValue buildPayload(string modelId, JSONValue input, ToolRegistry tools, JSONValue options)
    {
        JSONValue ret = super.buildPayload(modelId, input, tools, options);

        if (options.type == JSONType.object)
        {
            if ("top_k" in options)
                ret["top_k"] = options["top_k"];
            if ("thinking_budget" in options)
                ret["thinking_budget"] = options["thinking_budget"];
            if ("chat_template_kwargs" in options)
                ret["chat_template_kwargs"] = options["chat_template_kwargs"];
            if ("enable_thinking" in options)
                ret["enable_thinking"] = options["enable_thinking"];
            if ("mm_processor_kwargs" in options)
                ret["mm_processor_kwargs"] = options["mm_processor_kwargs"];
        }

        return ret;
    }

    override JSONValue buildEmbeddingsPayload(string modelId, JSONValue input, JSONValue options)
    {
        JSONValue ret = super.buildEmbeddingsPayload(modelId, input, options);

        if (options.type == JSONType.object)
        {
            if ("encoding_format" in options)
                ret["encoding_format"] = options["encoding_format"];
            if ("dimensions" in options)
                ret["dimensions"] = options["dimensions"];
        }

        return ret;
    }

    override Completion parseResponse(string modelId, JSONValue json)
    {
        Completion ret = super.parseResponse(modelId, json);
        foreach (ref choice; ret.choices)
        {
            if (choice.toolCalls.length == 0 && choice.text.length > 0)
                extractXmlToolCalls(choice);
        }
        return ret;
    }

private:
    /// Attempts to extract tool calls from XML tags embedded in choice text.
    /// Supports both Qwen3-Coder custom XML and Qwen2.5+/Qwen3 JSON-in-XML formats.
    static void extractXmlToolCalls(ref Choice choice)
    {
        if (!choice.text.canFind("<tool_call>"))
            return;

        ToolCall[] customCalls = parseCustomXmlToolCalls(choice.text);
        if (customCalls.length > 0)
        {
            choice.toolCalls = customCalls;
            choice.text = stripXmlToolCalls(choice.text);
            return;
        }

        ToolCall[] jsonCalls = parseJsonInXmlToolCalls(choice.text);
        if (jsonCalls.length > 0)
        {
            choice.toolCalls = jsonCalls;
            choice.text = stripXmlToolCalls(choice.text);
        }
    }

    /// Parses Qwen3-Coder custom XML tool calls from text.
    static ToolCall[] parseCustomXmlToolCalls(string text)
    {
        ToolCall[] ret;
        if (!text.canFind("<function="))
            return ret;

        auto toolCallRe = ctRegex!(r"<tool_call>(.*?)</tool_call>|<tool_call>(.*)$", "s");
        auto funcRe = ctRegex!(r"<function=(.*?)</function>|<function=(.*)$", "s");
        auto paramRe = ctRegex!(
            r"<parameter=(.*?)(?:</parameter>|(?=<parameter=)|(?=</function>)|$)", "s"
        );

        foreach (tcMatch; text.matchAll(toolCallRe))
        {
            string block = tcMatch.captures[1];
            if (block.length == 0)
                block = tcMatch.captures[2];
            if (block.length == 0)
                continue;

            foreach (funcMatch; block.matchAll(funcRe))
            {
                string funcBlock = funcMatch.captures[1];
                if (funcBlock.length == 0)
                    funcBlock = funcMatch.captures[2];
                if (funcBlock.length == 0)
                    continue;

                ptrdiff_t gt = funcBlock.indexOf(">");
                if (gt < 0)
                    continue;

                string funcName = funcBlock[0..gt].strip;
                string paramsStr = funcBlock[gt + 1..$];

                JSONValue args = JSONValue.emptyObject;
                foreach (paramMatch; paramsStr.matchAll(paramRe))
                {
                    string paramBlock = paramMatch.captures[1];
                    if (paramBlock.length == 0)
                        continue;

                    ptrdiff_t pgt = paramBlock.indexOf(">");
                    if (pgt < 0)
                        continue;

                    string paramName = paramBlock[0..pgt].strip;
                    string paramValue = paramBlock[pgt + 1..$].strip;
                    args[paramName] = tryConvertValue(paramValue);
                }

                ToolCall call;
                call.id = generateToolCallId(ret.length);
                call.name = funcName;
                call.arguments = args;
                ret ~= call;
            }
        }
        return ret;
    }

    /// Parses JSON-in-XML tool calls (Hermes-style used by Qwen2.5/Qwen3).
    static ToolCall[] parseJsonInXmlToolCalls(string text)
    {
        ToolCall[] ret;
        Regex!char re = ctRegex!(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", "s");
        foreach (m; text.matchAll(re))
        {
            try
            {
                JSONValue json = parseJSON(m.captures[1]);
                ToolCall call;
                call.id = generateToolCallId(ret.length);
                if ("name" in json)
                    call.name = json["name"].str;
                else if ("function" in json)
                    call.name = json["function"].str;

                if ("arguments" in json && json["arguments"].type == JSONType.object)
                    call.arguments = json["arguments"];
                else if ("parameters" in json && json["parameters"].type == JSONType.object)
                    call.arguments = json["parameters"];

                if (call.name.length > 0)
                    ret ~= call;
            }
            catch (Exception) { }
        }
        return ret;
    }

    /// Removes XML tool-call blocks from text, preserving any leading/trailing prose.
    static string stripXmlToolCalls(string text)
    {
        return text.replaceAll(ctRegex!(r"<tool_call>.*?</tool_call>", "s"), "")
            .replaceAll(ctRegex!(r"<tool_call>.*$", "s"), "")
            .strip();
    }

    /// Generates a synthetic tool call ID for XML-extracted calls.
    static string generateToolCallId(size_t index)
    {
        return format("call_%016x", index);
    }

    /// Converts a string value to the most appropriate JSON type.
    static JSONValue tryConvertValue(string value)
    {
        string trimmed = value.strip;
        if (trimmed.length == 0)
            return JSONValue("");

        try
        {
            long num = trimmed.to!long;
            if (num.to!string == trimmed)
                return JSONValue(num);
        }
        catch (Exception) { }

        try
        {
            double num = trimmed.to!double;
            if (num.to!string == trimmed || (num.to!string~"f") == trimmed)
                return JSONValue(num);
        }
        catch (Exception) { }

        if (trimmed == "true" || trimmed == "True")
            return JSONValue(true);
        if (trimmed == "false" || trimmed == "False")
            return JSONValue(false);
        if (trimmed == "null" || trimmed == "None")
            return JSONValue(null);

        try
        {
            return parseJSON(trimmed);
        }
        catch (Exception) { }

        return JSONValue(trimmed);
    }
}
