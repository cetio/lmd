# Quick Start

Intuit can be used through endpoints or routers. Endpoints are stateless provider clients whose requests name a model explicitly. Routers select an active model and maintain conversation context across requests.

## Installation

```sh
dub add intuit
```

Import the complete public API:

```d
import intuit;
```

## Using an Endpoint

Construct an endpoint with the provider's base URL and optional API key:

```d
import intuit;

import std.stdio : writeln;

OpenAI ep = new OpenAI("http://localhost:1234");

Context ctx;
ctx.system("You are a helpful assistant.");
ctx.user("What is D?");

Completion result = completions(ep, "llama3", ctx);
writeln(result.text);
```

The endpoint does not own conversation state. Passing `ctx` by reference sends its messages and appends the assistant response, allowing the caller to preserve state. A string request sends one user message without retaining the response:

```d
Completion result = completions(ep, "llama3", "Why is the sky blue?");
```

Configure a model through the endpoint's cached `ModelConfig`:

```d
ModelConfig cfg = ep.config("llama3");
cfg.temperature = 0.7;
cfg.maxTokens = 1024;
```

Built-in endpoint classes are `OpenAI`, `Claude`, and `Qwen`. See the [Endpoints guide](endpoints/README.md).

## Using a Router

A router owns its context and uses one active model:

```d
import intuit;

import std.stdio : writeln;

OpenRouter router = new OpenRouter("sk-or-key");
router.active("openai/gpt-4o");
router.context.system("Answer concisely.");

Completion first = completions(router, "What is D?");
Completion second = completions(router, "How does it compare to C++?");

writeln(first.text);
writeln(second.text);
```

`OpenRouter` fetches model metadata on demand. When metadata exists, selecting a model changes the context compactor's token limit to match that model's context window.

`LiteLLM` currently supports model-catalog access only and does not implement completion or embedding requests. See the [Routers guide](routers/README.md).

## Embeddings

OpenAI-compatible endpoints and OpenRouter expose single and batch embedding requests:

```d
Embedding!float embedding = embeddings(
    ep,
    "nomic-embed-text",
    "Hello, world!"
);

Embedding!float[] batch = embeddings(
    ep,
    "nomic-embed-text",
    ["first", "second"]
);
```

Claude does not support embeddings through Intuit's Messages API implementation.

## Tools

Register a D function on an endpoint or router. Intuit generates its JSON schema and parses returned arguments:

```d
@Description("Greet someone by name.")
string greet(string name)
{
    return "Hello, "~name~"!";
}

ep.tools.add!greet();
ep.config("llama3").setToolLiability("auto");

Context ctx;
ctx.user("Say hello to Bob.");

Completion result = completions(ep, "llama3", ctx);
foreach (call; result.choice.toolCalls)
{
    Tool tool = ep.tools.get(call.name);
    ctx.tool(call.id, tool.impl(call.arguments));
}

Completion finalResult = completions(ep, "llama3", ctx);
```

Tool execution is explicit; Intuit never invokes returned calls automatically. See [Tools](TOOLS.md) for supported signatures and provider behavior.

## Next Steps

- [Endpoints](endpoints/README.md) — provider clients, model configuration, completions, and embeddings.
- [Routers](routers/README.md) — active models, catalogs, maintained context, and OpenRouter options.
- [Context](CONTEXT.md) — messages and compaction.
- [Responses](RESPONSES.md) — choices, usage, finish reasons, and embeddings.
- [Tools](TOOLS.md) — schema generation and tool-call round-trips.
