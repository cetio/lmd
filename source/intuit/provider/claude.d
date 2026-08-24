/// Anthropic Claude provider implementation with Messages API.
module intuit.provider.claude;

public import intuit.provider;
import intuit.core.exception : EndpointException;
import intuit.core.model;
import intuit.core.response;
import intuit.core.tool;

import std.algorithm.searching : canFind;
import std.json : JSONType, JSONValue;
import std.net.curl : HTTP;
import std.string : toLower;

/// Anthropic Claude LLM provider.
class Claude : IProvider
{
private:
    string _name;
    string _url;
    string _key;
    ToolRegistry _tools;
    HTTP _http;
    ModelProfile[string] _profiles;

    string[string] buildHeaders()
    {
        string[string] ret;
        ret["Content-Type"] = "application/json";
        ret["anthropic-version"] = "2023-06-01";
        if (_key.length > 0)
            ret["x-api-key"] = _key;
        return ret;
    }

    /// Reads an integral value from a JSON object under the primary or fallback key.
    static size_t readUint(
        JSONValue obj,
        string primary,
        string fallback = null,
    )
    {
        foreach (key; [primary, fallback])
        {
            if (key is null || key !in obj)
                continue;

            JSONValue value = obj[key];
            if (value.type == JSONType.integer)
                return cast(size_t)value.integer;
            else if (value.type == JSONType.uinteger)
                return cast(size_t)value.uinteger;
        }
        return 0;
    }

    /// Maps a JSON finish reason string to the FinishReason enum.
    static FinishReason parseFinishReason(JSONValue value)
    {
        if (value.type != JSONType.string)
            return FinishReason.Unknown;

        switch (value.str)
        {
        case "end_turn":
            return FinishReason.EndTurn;
        case "max_tokens":
            return FinishReason.MaxTokens;
        case "stop_sequence":
            return FinishReason.StopSequence;
        case "tool_use":
            return FinishReason.ToolUse;
        case "content_filter":
            return FinishReason.ContentFilter;
        default:
            return FinishReason.Unknown;
        }
    }

    /// Throws if the JSON response contains an exception field.
    static void checkException(JSONValue json)
    {
        if ("error" !in json)
            return;

        if (json["error"].type == JSONType.string)
            throw new Exception(json["error"].str);
        else if (json["error"].type == JSONType.object && "message" in json["error"])
            throw new EndpointException("POST", "messages", 0, "error", json["error"]["message"].str);
        else
            throw new EndpointException("POST", "messages", 0, "error", json.toPrettyString());
    }

public:
    /**
     * Constructs a Claude provider.
     *
     * The provided URL is used as-is and the caller is responsible for
     * supplying the correct base URL for the endpoint.
     *
     * Params:
     *  url = The base URL of the endpoint.
     *  key = Optional API key.
     *  name = Display name for the provider.
     */
    this(string url, string key = null, string name = "Claude")
    {
        _name = name;
        _url = url;
        _key = key;
        _http = HTTP();
    }

    override ref string name()
        => _name;

    override ref string url()
        => _url;

    override ref string key()
        => _key;

    override ref ToolRegistry tools()
        => _tools;

    override ModelProfile[] available()
    {
        JSONValue json = _http.request(HTTP.Method.get, _url~"/v1/models", buildHeaders());
        ModelProfile[] ret;
        if ("data" in json && json["data"].type == JSONType.array)
        {
            foreach (item; json["data"].array)
            {
                string id = "id" in item ? item["id"].str : null;
                if (id is null)
                    continue;

                if (id !in _profiles)
                    _profiles[id] = new ModelProfile(id, _name);
                ret ~= _profiles[id];
            }
        }
        return ret;
    }

    override ModelProfile profile(string modelId)
    {
        if (auto found = modelId in _profiles)
            return *found;
        ModelProfile ret = new ModelProfile(modelId, _name);
        _profiles[modelId] = ret;
        return ret;
    }

    override JSONValue buildPayload(string modelId, JSONValue input, ToolRegistry tools, JSONValue options)
    {
        JSONValue ret = JSONValue.emptyObject;
        ret["model"] = JSONValue(modelId);

        if (options.type == JSONType.object)
        {
            foreach (key, value; options.object)
                ret[key] = value;
        }

        Tool[] toolList = tools.list();
        if (toolList.length > 0)
        {
            JSONValue toolsArray = JSONValue.emptyArray;
            foreach (tool; toolList)
            {
                JSONValue toolObj = JSONValue.emptyObject;
                toolObj["name"] = JSONValue(tool.name);
                if (tool.description.length > 0)
                    toolObj["description"] = JSONValue(tool.description);
                toolObj["input_schema"] = tool.schema;
                toolsArray.array ~= toolObj;
            }
            ret["tools"] = toolsArray;
        }

        string systemPrompt;

        if ("system" in ret && ret["system"].type == JSONType.string)
            systemPrompt = ret["system"].str;

        if (input.type == JSONType.array)
        {
            JSONValue[] remainingMessages;
            foreach (msg; input.array)
            {
                if ("role" in msg && msg["role"].type == JSONType.string && msg["role"].str == "system")
                {
                    if ("content" in msg && msg["content"].type == JSONType.string)
                    {
                        if (systemPrompt.length > 0)
                            systemPrompt ~= "\n"~msg["content"].str;
                        else
                            systemPrompt = msg["content"].str;
                    }
                }
                else
                {
                    remainingMessages ~= msg;
                }
            }
            ret["messages"] = JSONValue(remainingMessages);
        }
        else
        {
            ret["messages"] = JSONValue.emptyArray;
            JSONValue message = JSONValue.emptyObject;
            message["role"] = JSONValue("user");
            message["content"] = input;
            ret["messages"].array ~= message;
        }

        if (systemPrompt.length > 0)
            ret["system"] = JSONValue(systemPrompt);

        return ret;
    }

    override Completion parseResponse(string modelId, JSONValue json)
    {
        Completion ret;
        ret.raw = json;
        checkException(json);

        if ("model" in json && json["model"].type == JSONType.string)
            ret.usage.modelName = json["model"].str;
        else
            ret.usage.modelName = modelId;

        if ("latency" in json && json["latency"].type == JSONType.float_)
            ret.usage.latency = cast(float)json["latency"].floating;
        else if ("latency" in json && json["latency"].type == JSONType.integer)
            ret.usage.latency = cast(float)json["latency"].integer;

        if ("usage" in json && json["usage"].type == JSONType.object)
        {
            JSONValue usage = json["usage"];
            size_t inputTokens = readUint(usage, "input_tokens", null);
            size_t cacheReadTokens = readUint(usage, "cache_read_input_tokens", null);
            size_t cacheCreationTokens = readUint(usage, "cache_creation_input_tokens", null);
            ret.usage.promptTokens = inputTokens + cacheReadTokens + cacheCreationTokens;
            ret.usage.completionTokens = readUint(usage, "output_tokens", null);
            ret.usage.totalTokens = ret.usage.promptTokens + ret.usage.completionTokens;
            ret.usage.cacheHits = cacheReadTokens;
            ret.usage.cacheMisses = inputTokens + cacheCreationTokens;
        }

        Choice choice;
        choice.raw = json;

        if ("content" in json && json["content"].type == JSONType.array)
        {
            foreach (block; json["content"].array)
            {
                if (block.type != JSONType.object)
                    continue;

                if ("type" in block && block["type"].type == JSONType.string)
                {
                    string blockType = block["type"].str;
                    if (blockType == "text" && "text" in block)
                        choice.text ~= block["text"].str;
                    else if (blockType == "thinking" && "thinking" in block)
                        choice.reasoning ~= block["thinking"].str;
                    else if (blockType == "redacted_thinking")
                        choice.reasoning ~= "[redacted thinking]";
                    else if (blockType == "tool_use")
                    {
                        ToolCall call;
                        call.id = ("id" in block) ? block["id"].str : "";
                        call.name = ("name" in block) ? block["name"].str : "";
                        if ("input" in block)
                            call.arguments = block["input"];
                        choice.toolCalls ~= call;
                    }
                }
            }
        }

        choice.finishReason = parseFinishReason(
            "stop_reason" in json ? json["stop_reason"] : JSONValue.init
        );

        ret.choices ~= choice;
        return ret;
    }

    override JSONValue buildEmbeddingsPayload(string modelId, JSONValue input, JSONValue options)
    {
        throw new EndpointException("POST", "embeddings", 0, "not supported", "Claude does not support embeddings.");
    }

    override JSONValue parseEmbeddingsResponse(JSONValue json)
    {
        throw new EndpointException("POST", "embeddings", 0, "not supported", "Claude does not support embeddings.");
    }

    override JSONValue _completions(JSONValue payload)
    {
        return _http.request(
            HTTP.Method.post,
            _url~"/v1/messages",
            buildHeaders(),
            payload,
        );
    }

    override JSONValue _embeddings(JSONValue payload)
    {
        throw new EndpointException(
            "POST",
            "embeddings",
            0,
            "not supported",
            "Claude does not support embeddings.",
        );
    }
}
