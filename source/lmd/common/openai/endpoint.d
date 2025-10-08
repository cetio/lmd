module lmd.common.openai.endpoint;

import std.json;
import std.net.curl;
import std.string;
import std.conv;
import std.variant;

import lmd.endpoint;
import lmd.response;
import lmd.model;
import lmd.context;
import lmd.common.openai.model;
public import lmd.response;

class OpenAI : IEndpoint
{
    alias Model = OpenAIModel;

private:
    string _scheme;
    string _address;
    uint _port;
    string _key;

    Model[string] _models;

    string toUrl(string api)
    {
        return _scheme~"://"~_address
            ~((_port != 0 && _port != 80 && _port != 443) ? ':'~_port.to!string : "")
            ~api;
    }

public:
    this(string scheme, string address, uint port, string key = null)
    {
        _scheme = scheme;
        _address = address;
        _port = port;
        _key = key;
    }

    ref string key()
        => _key;

    IModel fetch(string model)
    {
        if (model in _models)
            return _models[model];
        return new Model(model);
    }

    IModel[] available()
    {
        HTTP http = HTTP(toUrl("/v1/models"));
        http.method = HTTP.Method.get;
        if (_key.length)
            http.addRequestHeader("Authorization", "Bearer "~_key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp ~= cast(string)data;
            return data.length;
        });

        IModel[] ret;
        if (http.perform() == 0)
        {
            JSONValue json = resp.parseJSON();
            if ("data" in json)
            {
                foreach (m; json["data"].array)
                {
                    string name = "id" in m ? m["id"].str : null;
                    string owner = "owned_by" in m ? m["owned_by"].str : null;
                    ret ~= new Model(name, owner);
                }
            }
        }
        return ret;
    }

    // TODO: Consolidate logic.
    Response completions(string model, Variant data)
    {
        Model m = cast(Model)fetch(model);
        JSONValue json = m.toChatJSON(data);

        HTTP http = HTTP(toUrl("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        string key = m.key().length ? m.key() : _key;
        if (key.length)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp ~= cast(string)data;
            return data.length;
        });

        if (http.perform() != 0 || resp.length == 0)
            throw new Exception("Connection to endpoint failed!");

        try
            json = resp.parseJSON();
        catch (Exception e)
            return Response(model, e);

        return m.parseChatResponse(json);
    }

    Response embeddings(string model, Variant data)
    {
        Model m = cast(Model)fetch(model);
        JSONValue json = m.toEmbeddingsJSON(data);

        HTTP http = HTTP(toUrl("/v1/embeddings"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        string key = m.key().length ? m.key() : _key;
        if (key.length)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp ~= cast(string)data;
            return data.length;
        });

        if (http.perform() != 0 || resp.length == 0)
            throw new Exception("Connection to endpoint failed!");

        try
            json = resp.parseJSON();
        catch (Exception e)
            return Response(model, e);

        return m.parseEmbeddingsResponse(json);
    }

    ResponseStream stream(string model, Variant data)
    {
        Model m = cast(Model)fetch(model);
        JSONValue json = m.toChatJSON(data);
        json["stream"] = JSONValue(true);

        ResponseStream stream = new ResponseStream(m.name(), null);
        stream.json = json;
        stream._commence = &_commence;
        return stream;
    }

private:
    void _commence(ResponseStream stream)
    {
        Model m = cast(Model)fetch(stream.model);

        HTTP http = HTTP(toUrl("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(stream.json.toString(JSONOptions.specialFloatLiterals), "application/json");
        string key = m.key().length ? m.key() : _key;
        if (key.length)
            http.addRequestHeader("Authorization", "Bearer "~key);

        string buffer;
        http.onReceive((ubyte[] data) {
            buffer ~= cast(string)data;

            while (true)
            {
                size_t newlinePos = buffer.indexOf('\n');
                if (newlinePos == -1)
                    break;

                string line = buffer[0..newlinePos];
                buffer = buffer[(newlinePos + 1)..$];

                if (line.length == 0)
                    continue;

                if (line.startsWith("data: "))
                    line = line[6 .. $];

                if (line == "[DONE]")
                    continue;

                Response resp;
                try
                {
                    JSONValue json = line.parseJSON();
                    resp = m.parseChatResponse(json);
                }
                catch (Exception e)
                    resp = Response(stream.model, e);

                stream.update(resp);
                if (stream.callback !is null)
                    stream.callback(resp);
            }

            stream.complete = true;
            return data.length;
        });

        if (http.perform() != 0 || buffer.length == 0)
        {
            Response resp = Response(stream.model, new Exception("Connection to endpoint failed!"));
            stream.update(resp);
            if (stream.callback !is null)
                stream.callback(resp);
        }
    }
}