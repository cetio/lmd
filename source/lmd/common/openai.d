module lmd.common.openai;

public import lmd.endpoint;
public import lmd.response;
public import lmd.model;
public import lmd.context;
public import lmd.options;
import lmd.formatter;
import lmd.exception;
import std.json;
import std.net.curl;
import std.string;
import std.conv;
import std.algorithm;

class OpenAI(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
private:
    Model[string] _models;
    string _key;
    IFormatter _formatter;

package:
    string selectKey(Model model) =>
        model.key == null && model.name != null ? this._key : model.key;
    
    string toUrl(string api)
    {
        return SCHEME ~ "://" ~ ADDRESS
            ~ ((PORT != 0 && PORT != 80 && PORT != 443) ? ':' ~ PORT.to!string : "")
            ~ api;
    }

public:
    this()
    {
        _formatter = new BaseFormatter();
    }

    ref Model[string] models() 
        => _models;

    ref string key()
        => _key;

    ref IFormatter formatter()
        => _formatter;

    Model[] available()
    {
        HTTP http = HTTP(toUrl("/v1/models"));
        http.method = HTTP.Method.get;
        if (this._key != null)
            http.addRequestHeader("Authorization", "Bearer " ~ this._key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string) data;
            return data.length;
        });

        if (http.perform() == 0)
        {
            JSONValue json = resp.parseJSON();
            Model[] ret;
            if ("data" in json)
            {
                foreach (model; json["data"].array)
                    ret ~= _formatter.parseModel(this, model);
            }
            return ret;
        }
        else
        // TODO: Error handling.
            return null;
    }

    Model load(string name = null,
        string owner = "organization_owner",
        Options options = Options.init,
        Context context = Context.init)
    {
        if (name != null && available.filter!(m => m.name == name).empty)
            throw new ModelException(
                "model_not_found",
                "Model is not available.",
                "model",
                "invalid_request_error"
            );

        Model m = name in _models
            ? _models[name] 
            : (_models[name] = new Model(this, name, owner, options, context));
        return m;
    }

    Response request(string api, Model model)
    {
        JSONValue json = _formatter.toJSON(model.options);
        if (api == "/v1/chat/completions")
            json["messages"] = _formatter.toJSON(model.context);
        else if (api == "/v1/completions")
            json["prompt"] = JSONValue(model.context.last().text());
        else if (api == "/v1/embeddings")
        // TODO: Eventually, add support for different types of input.
            json["input"] = JSONValue(model.context.last().text());
        else
            throw new Exception("Unsupported API request.");
        
        HTTP http = HTTP(toUrl(api));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer " ~ selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string)data;
            return data.length;
        });

        if (http.perform() == 0)
            return _formatter.parseResponse(model, resp.parseJSON());
        else
        {
            return Response(model, new ModelException(
                "connection_failed",
                "Failed to connect to the server",
                api,
                "connection_error"
            ));
        }
    }

    Response completions(Model model)
    {
        return request("/v1/chat/completions", model);
    }

    Response embeddings(Model model)
    {
        return request("/v1/embeddings", model);
    }

    ResponseStream stream(Model model, void delegate(Response) callback)
    {
        ResponseStream stream = new ResponseStream(model, callback);
        stream._commence = &_commence;
        return stream;
    }

    void _commence(ResponseStream stream)
    {
        JSONValue json = _formatter.toJSON(stream.model.options);
        json["messages"] = _formatter.toJSON(stream.model.context);
        json["stream"] = JSONValue(true);

        HTTP http = HTTP(toUrl("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(stream.model) != null)
            http.addRequestHeader("Authorization", "Bearer "~selectKey(stream.model));

        string buffer;
        Response resp;
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

                try
                    resp = _formatter.parseResponse(stream.model, line.parseJSON());
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
            resp = Response(stream.model, new ModelException(
                    "connection_failed",
                    "Failed to connect to the server",
                    "stream",
                    "connection_error"
            ));

            stream.update(resp);
            if (stream.callback !is null)
                stream.callback(resp);
        }
    }
}

IEndpoint openai(string SCHEME, string ADDRESS, uint PORT)()
    => cast(IEndpoint)(new OpenAI!(SCHEME, ADDRESS, PORT));
