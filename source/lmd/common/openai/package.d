module lmd.common.openai;

public import lmd.common.openai.context;
public import lmd.options;
public import lmd.endpoint;
public import lmd.model;
public import lmd.response;
import lmd.exception;

// So many imports :(
import core.atomic;
import std.conv;
import std.algorithm;
import std.net.curl;
import std.array;
import std.json;
import std.string;

/// Represents a strongly-typed OpenAI-style model endpoint for a given scheme, address, and port.
class OpenAI(string SCHEME, string ADDRESS, uint PORT) : IEndpoint
{
    /// Cache of loaded models keyed by their name.
    static Model[string] models;
    /// API key for this endpoint.
    static string key;

package:
    /// Converts the `/v1/models` JSON response into a list of `Model` objects.
    Model[] fromJSON(JSONValue json)
    {
        Model[] ret;
        if ("data" in json)
        {
            foreach (model; json["data"].array)
            {
                ret ~= Model(
                    this,
                    "id" in model ? model["id"].str : null,
                    "owned_by" in model ? model["owned_by"].str : null
                );
            }
        }
        return ret;
    }

    string selectKey(Model model) =>
        model.key == null && model.name != null ? key : model.key;

public:
    /// Creates a string URL for the provided API query using the current endpoint scheme, address, and port.
    string url(string api)
    {
        return SCHEME ~ "://" ~ ADDRESS
            ~ ((PORT != 0 && PORT != 80 && PORT != 443) ? ':' ~ PORT.to!string : "")
            ~ api;
    }

    Model load(string name = null,
        string owner = "organization_owner",
        Options options = Options.init,
        IContext context = null)
    {
        if (name != null && available.filter!(m => m.name == name).empty)
            throw new ModelException(
                "model_not_found",
                "Model is not available.",
                "model",
                "invalid_request_error"
            );

        if (options == Options.init)
            options = Options();
        if (context is null)
            context = new Context();

        Model m = name in models
            ? models[name] : (models[name] = Model(this, name, owner, options, context));
        return m;
    }

    /// Requests a completion from '/v1/chat/completions' for `model`.
    Response completions(Model model)
    {
        // TODO: Sanity checks.
        JSONValue json = model.context.completions(model.options);

        // This is the worst networking I have seen in my entire life.
        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer " ~ selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string) data;
            return data.length;
        });

        if (http.perform() == 0)
            return Response(model, resp.strip.parseJSON);
        else
            return Response(model, new ModelException(
                "connection_failed",
                "Failed to connect to the server",
                "completions",
                "connection_error"
            ));
    }

    /// Requests a streaming completion from '/v1/chat/completions' for `model'.
    ResponseStream stream(Model model, void delegate(Response) callback)
    {
        // throw new ModelException(
        //     "not_supported",
        //     "Streaming is not supported by this model.",
        //     "streaming",
        //     "invalid_request_error"
        // );

        ResponseStream stream = new ResponseStream(model, callback);
        stream._commence = &_commence;
        return stream;
    }

    void _commence(ResponseStream stream)
    {
        // TODO: Really ugly.....
        bool tmp = stream.model.options.get!bool("stream");
        scope (exit) stream.model.options.set("stream", tmp);
        stream.model.options.set("stream", true);

        JSONValue json = stream.model.context.completions(stream.model.options);

        HTTP http = HTTP(url("/v1/chat/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(stream.model) != null)
            http.addRequestHeader("Authorization", "Bearer " ~ selectKey(stream.model));

        string buffer;
        http.onReceive((ubyte[] data) {
            buffer ~= cast(string) data;

            // Process complete JSON objects from the buffer
            while (true)
            {
                size_t newlinePos = buffer.indexOf('\n');
                if (newlinePos == -1)
                    break;

                string line = buffer[0 .. newlinePos];
                buffer = buffer[newlinePos + 1 .. $];

                // Skip empty lines and data: prefix
                if (line.length == 0)
                    continue;

                if (line.startsWith("data: "))
                    line = line[6 .. $];

                if (line == "[DONE]")
                    continue;

                try
                {
                    Response resp = Response(stream.model, line.parseJSON);
                    stream.update(resp);
                    if (stream.callback !is null)
                        stream.callback(resp);
                }
                catch (Exception e)
                    continue;
            }

            return data.length;
        });

        int result = http.perform();
        if (result != 0 || buffer.length == 0)
        {
            Response err = Response(stream.model, new ModelException(
                    "connection_failed",
                    "Failed to connect to the server",
                    "stream",
                    "connection_error"
            ));
            stream.update(err);
            if (stream.callback !is null)
                stream.callback(err);
        }
    }

    /// Requests a legacy completion from `/v1/completions` for `model`.
    Response legacyCompletions(Model model)
    {
        JSONValue json = model.context.completions(model.options);

        HTTP http = HTTP(url("/v1/completions"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (selectKey(model) != null)
            http.addRequestHeader("Authorization", "Bearer " ~ selectKey(model));

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string) data;
            return data.length;
        });

        if (http.perform() == 0)
            return Response(model, resp.parseJSON);
        else
            return Response(model, new ModelException(
                "connection_failed",
                "Failed to connect to the server",
                "legacy_completions",
                "connection_error"
            ));
    }

    /// Requests embeddings for the given text using the specified model.
    Response embeddings(Model model)
    {
        JSONValue json = model.context.embeddings(model.options);

        HTTP http = HTTP(url("/v1/embeddings"));
        http.method = HTTP.Method.post;
        http.setPostData(json.toString(JSONOptions.specialFloatLiterals), "application/json");
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer " ~ key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string) data;
            return data.length;
        });

        if (http.perform() == 0)
            return Response(model, resp.strip.parseJSON);
        else
            return Response(model, new ModelException(
                "connection_failed",
                "Failed to connect to the server",
                "embeddings",
                "connection_error"
            ));
    }

    /// Queries for the list of available models from `/v1/models`.
    Model[] available()
    {
        HTTP http = HTTP(url("/v1/models"));
        http.method = HTTP.Method.get;
        if (key != null)
            http.addRequestHeader("Authorization", "Bearer " ~ key);

        string resp;
        http.onReceive((ubyte[] data) {
            if (data.length > 0)
                resp = cast(string) data;
            return data.length;
        });

        if (http.perform() == 0)
            return fromJSON(resp.parseJSON);
        else
            return null;
    }
}

/// Helper function for creating an OpenAI-style endpoint as an IEndpoint.
IEndpoint openai(string SCHEME, string ADDRESS, uint PORT)()
{
    return cast(IEndpoint)(new OpenAI!(SCHEME, ADDRESS, PORT));
}
