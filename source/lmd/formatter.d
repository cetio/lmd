module lmd.formatter;

import lmd.context;
import lmd.options;
import lmd.response;
import lmd.model;
import lmd.tool;
import lmd.exception;
import lmd.endpoint;
import std.json;
import std.string;

interface IFormatter
{
    JSONValue toJSON(Context context);

    JSONValue toJSON(Options options);

    JSONValue toJSON(Response response);

    JSONValue toJSON(Model model);

    JSONValue toJSON(Tool tool);
    
    Context parseContext(JSONValue json);

    Options parseOptions(JSONValue json);

    Response parseResponse(Model model, JSONValue json);

    Model parseModel(IEndpoint endpoint, JSONValue json);

    Tool parseTool(JSONValue json);
}

class BaseFormatter : IFormatter
{
    JSONValue toJSON(Context context)
    {
        JSONValue ret = JSONValue.emptyArray;

        foreach (msg; context.messages)
        {
            JSONValue json = JSONValue.emptyObject;
            json["role"] = JSONValue(cast(string)msg.role);
            
            if (msg.isText)
                json["content"] = JSONValue(msg.text());
            else if (msg.isTool)
            {
                json["tool_calls"] = JSONValue.emptyArray;
                json["tool_calls"].array ~= toJSON(msg.tool());
            }
            
            ret.array ~= json;
        }
        
        return ret;
    }
    
    JSONValue toJSON(Options options)
    {
        JSONValue ret = options.json;
        
        if (options.tools.length > 0)
        {
            JSONValue json = JSONValue.emptyArray;
            foreach (tool; options.tools)
                json.array ~= toJSON(tool);
            ret["tools"] = json;
        }
        
        if (options.toolChoice == ToolChoice.Auto)
            ret["tool_choice"] = JSONValue("auto");
        else if (options.toolChoice == ToolChoice.None)
            ret["tool_choice"] = JSONValue("none");
        else if (options.toolChoice == ToolChoice.Required)
        {
            JSONValue opt = JSONValue.emptyObject;
            opt["type"] = JSONValue("function");
            opt["function"] = JSONValue.emptyObject;
            opt["function"]["name"] = JSONValue(options.requiredTool);
            ret["tool_choice"] = opt;
        }
        
        return ret;
    }
    
    JSONValue toJSON(Response response)
    {
        throw new Exception("Not implemented");
        return JSONValue.emptyObject;
    }
    
    JSONValue toJSON(Model model)
    {
        JSONValue json = JSONValue.emptyObject;
        json["name"] = JSONValue(model.name);
        json["owner"] = JSONValue(model.owner);
        return json;
    }
    
    JSONValue toJSON(Tool tool)
    {
        JSONValue json = JSONValue.emptyObject;
        if (tool.isCall())
        {
            json["id"] = JSONValue(tool.id);
            json["type"] = JSONValue(tool.type);
            json["function"] = JSONValue.emptyObject;
            json["function"]["name"] = JSONValue(tool.name);
            json["function"]["arguments"] = tool.arguments;
        }
        else
        {
            json["type"] = JSONValue(tool.type);
            json["function"] = JSONValue.emptyObject;
            json["function"]["name"] = JSONValue(tool.name);
            json["function"]["description"] = JSONValue(tool.description);
            json["function"]["parameters"] = tool.parameters;
        }
        return json;
    }
    
    Context parseContext(JSONValue json)
    {
        Context ctx;
        if ("messages" in json)
        {
            foreach (msg; json["messages"].array)
            {
                string role = msg["role"].str;
                
                if ("content" in msg)
                    ctx.add(role, msg["content"].str);
                
                if ("tool_calls" in msg)
                {
                    foreach (call; msg["tool_calls"].array)
                        ctx.add(role, parseTool(call));
                }
            }
        }
        return ctx;
    }
    
    Options parseOptions(JSONValue json)
    {
        Options opts;
        opts.json = json;

        if ("tools" in json)
        {
            foreach (tool; json["tools"].array)
                opts.tools ~= parseTool(tool);
        }
        
        if ("tool_choice" in json)
        {
            JSONValue choice = json["tool_choice"];
            if (choice.type == JSONType.string)
            {
                if (choice.str == "auto")
                    opts.toolChoice = ToolChoice.Auto;
                else if (choice.str == "none")
                    opts.toolChoice = ToolChoice.None;
            }
            else if (choice.type == JSONType.object && "type" in choice)
            {
                opts.toolChoice = ToolChoice.Required;
                if ("function" in choice && "name" in choice["function"])
                    opts.requiredTool = choice["function"]["name"].str;
            }
        }
        return opts;
    }
    
    Response parseResponse(Model model, JSONValue json)
    {
        Response resp;
        resp.model = model;
        
        if ("error" in json)
        {
            resp.error = new ModelException(
                json["error"]["code"].str,
                json["error"]["message"].str,
                json["error"]["param"].str,
                json["error"]["type"].str
            );
        }
        
        resp.fingerprint = "system_fingerprint" in json ? json["system_fingerprint"].str : null;
        resp.id = "id" in json ? json["id"].str : null;
        resp.kind = "object" in json 
            ? cast(RequestKind)json["object"].str 
            : RequestKind.Unknown;
        
        if ("choices" in json)
        {
            foreach (data; json["choices"].array)
            {
                Choice choice;
                JSONValue msg = "delta" in data 
                    ? data["delta"] 
                    : data["message"];
                
                string content;
                if ("content" in msg)
                    content = msg["content"].str;
                else if ("text" in msg)
                    content = msg["text"].str;
                
                if (content.indexOf("<think>") != -1 && content.indexOf("</think>") != -1)
                {
                    choice.reasoning = content[content.indexOf("<think>")..(content.indexOf("</think>") + 8)];
                    content = content[content.indexOf("</think>") + 8..$];
                }

                if (content.length > 0)
                    choice.context.add(Role.Assistant, content);
                
                if ("reasoning" in msg)
                    choice.reasoning = msg["reasoning"].str;
                
                if ("tool_calls" in msg)
                {
                    foreach (call; msg["tool_calls"].array)
                        choice.context.add(Role.Assistant, parseTool(call));
                }
                else if ("tool_calls" in data)
                {
                    foreach (call; data["tool_calls"].array)
                        choice.context.add(Role.Assistant, parseTool(call));
                }
                
                choice.finishReason = "finish_reason" in data && !data["finish_reason"].isNull
                    ? cast(FinishReason)data["finish_reason"].str 
                    : FinishReason.Unknown;
                choice.logprobs = "logprobs" in data
                    ? data["logprobs"].isNull
                        ? float.nan
                        : data["logprobs"].floating
                    : float.nan;
                
                resp.choices ~= choice;
            }
        }
        else if ("data" in json)
        {
            foreach (data; json["data"].array)
            {
                Embedding embed;
                embed.index = "index" in data ? data["index"].integer : 0;
                if ("embedding" in data)
                {
                    // TODO: This seems inefficient.
                    foreach (val; data["embedding"].array)
                        embed.value ~= cast(float)val.floating;
                }
                resp.embeddings ~= embed;
            }
        }
        
        if ("usage" in json)
        {
            resp.promptTokens = json["usage"]["prompt_tokens"].integer;
            resp.completionTokens = json["usage"]["completion_tokens"].integer;
            resp.totalTokens = json["usage"]["total_tokens"].integer;
        }
        return resp;
    }
    
    Model parseModel(IEndpoint endpoint, JSONValue json)
    {
        string name = "id" in json ? json["id"].str : null;
        string owner = "owned_by" in json ? json["owned_by"].str : null;
        return new Model(endpoint, name, owner);
    }
    
    Tool parseTool(JSONValue json)
    {
        Tool tool;
        tool.id = "id" in json ? json["id"].str : null;
        tool.type = "type" in json ? json["type"].str : "function";
        if ("function" in json)
        {
            tool.name = "name" in json["function"] ? json["function"]["name"].str : null;
            if ("arguments" !in json["function"])
                tool.arguments = JSONValue.emptyObject;
            else
            {
                JSONValue args = json["function"]["arguments"];
                if (args.type == JSONType.string)
                    tool.arguments = args.str.parseJSON();
                else
                    tool.arguments = args;
            }
        }
        return tool;
    }
}