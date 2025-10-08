# LMD

Library for interacting/managing language models, particularly locally, with native structures for D. Connect to OpenAI, LMStudio, or any OpenAI-compatible endpoint through:
- `/v1/chat/completions`
- `/v1/embeddings`
- `/v1/models`

Built-in support for other providers like Claude and Gemini are planned, but have not yet been implemented. LMD allows for defining new models and endpoints easily and building off of existing endpoints.

## Quick Start

```d
import lmd.common.openai;
import lmd.endpoint;

IEndpoint ep = cast(IEndpoint)(new OpenAI("http", "127.0.0.1", 1234));
Response resp = ep.complete!"gpt-oss"("What is 2+2?");
string answer = resp.select!string();
```

## Usage

### Endpoints

```d
import lmd.common.openai;

// Local LMStudio
IEndpoint ep = cast(IEndpoint)(new OpenAI("http", "127.0.0.1", 1234));

// OpenAI API
IEndpoint openai = cast(IEndpoint)(new OpenAI("https", "api.openai.com", 443, "your-api-key"));
```

### Completions

```d
import lmd.endpoint;
import lmd.context;

// Simple text
Response resp = ep.complete!"gpt-4"("Explain quantum computing");
string text = resp.select!string();

// With conversation context
Context ctx;
ctx.add(Role.System, "You are a helpful assistant");
ctx.add(Role.User, "What is the capital of France?");
Response resp = ep.complete!"gpt-4"(ctx);
```

### Model Configuration

```d
import lmd.model;

IModel model = ep.fetch("gpt-4");
model.temperature = 0.7;
model.maxTokens = 500;

// Options applied automatically to requests
Response resp = ep.complete!"gpt-4"("Hello!");
```

### Tools

```d
import std.json;
import lmd.tool;

IModel model = ep.fetch("gpt-4");

JSONValue params = parseJSON(`{
    "type": "object",
    "properties": {
        "city": {"type": "string", "description": "City name"}
    },
    "required": ["city"]
}`);

model.tools().add("get_weather", "Get current weather", params);

Response resp = ep.complete!"gpt-4"("What's the weather in Paris?");
Completion comp = resp.select!Completion();

if (comp.context.messages[0].isTool())
{
    Tool toolCall = comp.context.messages[0].tool();
    string city = toolCall.argument!string("city");
}
```

### Streaming

```d
ResponseStream stream = ep.stream("gpt-4", "Tell me a story");
stream.callback = (Response resp) {
    string text = resp.select!string();
    write(text);
};
// Calling `begin` starts the streaming.
// Callback will be used if it was provided, otherwise you may use `next()`, `last()`, and `collect(size_t)`
stream.begin();
```

### Embeddings

```d
Response resp = ep.embed!"text-embedding-ada-002"("Hello, world!");
float[] vector = resp.select!Embedding().value;
```

## Architecture

The library is endpoint-centric. Endpoints handle API communication, models are lightweight configuration handles, and context is passed as data.

- `IEndpoint` - Manages HTTP requests and model availability
- `IModel` - Holds configuration (temperature, tools, etc.)
- `Response` - Contains `Variant data` extracted via `select!T()`
- `Context` - Conversation messages with roles

## Examples

See `source/examples/` for working code:
- `vibesort.d` - Array sorting via LLM
- `tool.d` - Function calling

## Roadmap

- [x] Chat completions
- [x] Embeddings
- [x] Tool/function calling
- [x] Response streaming (lock-free*) *mostly
- [ ] Tool choice control
- [ ] Image generation
- [ ] Audio endpoints
- [ ] Claude and Gemini providers

## License

LMD is licensed under [AGPL-3.0](LICENSE.txt).
