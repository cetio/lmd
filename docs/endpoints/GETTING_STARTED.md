# Getting Started with Endpoints

This guide constructs a provider endpoint, fetches and configures a model, and sends completion and embedding requests.

## Creating an Endpoint

Endpoints are instantiated with a base URL and an optional API key. Intuit does not normalize it; each implementation appends its provider request path:

```d
import intuit;

auto ep = new OpenAI("http://localhost:1234", "sk-my-key");
```

`Claude` and `Qwen` follow the same constructor signature. `Qwen` extends `OpenAI` and inherits its request paths.

| Class | Completions path | Embeddings path |
| --- | --- | --- |
| `OpenAI` | `/v1/chat/completions` | `/v1/embeddings` |
| `Claude` | `/v1/messages` | Not supported |
| `Qwen` | `/v1/chat/completions` | `/v1/embeddings` |

## Models

Fetch the models advertised by the endpoint, or request one by name. Both return `ModelConfig` instances:

```d
ModelConfig[] models = ep.available();
ModelConfig cfg = ep.config("llama3");
```

`available()` fetches `/v1/models` and caches every returned model as a `ModelConfig`. `config(modelName)` returns a cached config by name, creating and caching a new one when the name is unknown. See [Models](MODELS.md) for configuration fields and provider-specific subclasses.

## Completions

Send a completion request with a string, a `Context`, or raw `JSONValue`. The model is referenced by name:

```d
import intuit;

import std.stdio : writeln;

auto ep = new OpenAI("http://localhost:1234");

Completion result = completions(ep, "llama3", "Why is the sky blue?");
writeln(result.text);
```

Use a `Context` to preserve conversation state. When `completions` receives a `Context`, the assistant response is appended automatically:

```d
Context ctx;
ctx.system("You are a helpful assistant.");
ctx.user("What is D?");

Completion result = completions(ep, "llama3", ctx);
writeln(result.text);
// ctx now contains the assistant's reply
```

See [Context](../CONTEXT.md) for message types and compaction, and [Responses](../RESPONSES.md) for the `Completion` structure.

## Structured Output

Request a JSON schema response format through `setResponseSchema`:

```d
import std.json : JSONValue;

JSONValue schema = JSONValue.emptyObject;
schema["type"] = JSONValue("object");
schema["properties"] = JSONValue.emptyObject;
schema["properties"]["answer"] = JSONValue("string");

ModelConfig cfg = ep.config("llama3");
cfg.setResponseSchema("answer_schema", schema);

Context ctx;
ctx.user("What is the capital of France?");

Completion result = completions(ep, cfg.name, ctx);
JSONValue parsed = result.json;
```

See [Models](MODELS.md) for `setResponseSchema`, `setRequiredTool`, and `setToolLiability`.

## Embeddings

Request embedding vectors for a single input or an array of inputs. The model is referenced by name:

```d
Embedding!float emb = embeddings(ep, "nomic-embed-text", "Hello, world!");
float[] vector = emb.value;

string[] inputs = ["Hello, world!", "Goodbye, world!"];
Embedding!float[] embs = embeddings(ep, "nomic-embed-text", inputs);
```

`Embedding!T` implicitly converts to its `T[]` value. The float type defaults to `float` but can be any numeric type. `Claude` does not support embeddings and throws `EndpointException` when called.

## Tools

Register native D functions as tools with automatic JSON schema generation:

```d
import intuit;

@Description("Get the current weather for a location.")
string getWeather(string location)
{
    return "Sunny and 72 degrees in "~location;
}

auto ep = new OpenAI("http://localhost:1234");
ep.tools.add!getWeather();

Context ctx;
ctx.user("What is the weather in Paris?");

Completion result = completions(ep, "llama3", ctx);
```

See [Tools](../TOOLS.md) for schema generation, tool execution, and tool-call round-trips.

## Error Handling

HTTP error responses are mapped to `EndpointException`, which exposes the method, route, status code, reason phrase, and response body. Provider error envelopes in the JSON body are also detected and thrown before response parsing.

```d
import intuit.exception : EndpointException;

try
    completions(ep, "llama3", ctx);
catch (EndpointException ex)
{
    writeln(ex.status, " ", ex.reason);
    writeln(ex.content);
}
```

## Next Steps

- [Models](MODELS.md) — `ModelConfig` fields, provider-specific subclasses, and structured output.
- [Routers](../routers/README.md) — stateful routing with a maintained context and active model.
- [Context](../CONTEXT.md) — typed messages and compaction policies.
- [Responses](../RESPONSES.md) — completion choices, token usage, and embeddings.
- [Tools](../TOOLS.md) — tool registration, schema generation, and execution.
