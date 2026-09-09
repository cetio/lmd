# Context

A `Context` is a mutable sequence of typed conversation messages. It can preserve a conversation across endpoint requests or serve as the state owned by a router.

## Building a Context

Use the role helpers to append messages:

```d
import intuit;

Context ctx;
ctx.system("You are a helpful assistant.");
ctx.user("What is D?");
ctx.assistant("D is a systems programming language.");
ctx.user("Show me a small example.");
```

Each helper returns the context by reference, so calls can be chained:

```d
ctx.system("Answer concisely.")
    .user("What is an associative array?");
```

| Member | Message type | Purpose |
| --- | --- | --- |
| `append(message)` | Any `IMessage` | Append a pre-built message. |
| `system(data)` | `SystemMessage` | Add system instructions. |
| `user(data)` | `UserMessage` | Add user content. |
| `assistant(text)` | `AssistantMessage` | Add a synthetic assistant response. |
| `assistant(completion, index)` | `AssistantMessage` | Preserve a completion choice and its usage. |
| `tool(data)` | `ToolMessage` | Add an unassociated tool result. |
| `tool(callId, data)` | `ToolMessage` | Add a result for a specific tool call. |
| `clear()` | — | Remove every message. |
| `length` | — | Return the message count. |

The data helpers use Intuit's JSON conversion support. Strings, numbers, booleans, arrays, string-keyed associative arrays, `JSONValue`, and supported aggregate types can be passed directly.

## Endpoint Conversations

Endpoint requests are stateless unless the caller preserves a context. Passing a `Context` by reference sends all of its messages and automatically appends the returned assistant choice:

```d
OpenAI ep = new OpenAI("http://localhost:1234");

Context ctx;
ctx.system("You are a helpful assistant.");
ctx.user("What is D?");

Completion first = completions(ep, "llama3", ctx);

ctx.user("How does it compare to C++?");
Completion second = completions(ep, "llama3", ctx);
```

Passing a string or another value sends only that value and does not retain the response.

## Router Conversations

Every router owns a context. Supplying data to `completions(router, data)` appends it as a user message before sending the request. The response is then appended as an assistant message:

```d
OpenRouter router = new OpenRouter("sk-or-key");
router.active("openai/gpt-4o");
router.context.system("Answer concisely.");

Completion first = completions(router, "Explain context windows.");
Completion second = completions(router, "Now give one practical implication.");
```

Use `completions(router)` to send the context without adding a user message. Clear the conversation with `router.context.clear()`.

## Message Types

Every message implements `IMessage`, which exposes `role` and `toJSON()`.

| Type | Content |
| --- | --- |
| `SystemMessage` | JSON system instructions. |
| `UserMessage` | JSON user content. |
| `AssistantMessage` | A `Completion` choice or synthetic text and tool calls. |
| `ToolMessage` | JSON tool output with an optional originating call ID. |

`AssistantMessage` retains the complete `Completion`, selected choice index, token usage, text, and tool calls. This allows context compaction to account for usage reported by earlier requests.

All messages serialize to OpenAI-style message objects. `ClaudeModelConfig` translates system messages to the Anthropic Messages API's top-level `system` field.

## Tool Messages

A tool-call round-trip preserves the assistant call and associates each result with its call ID:

```d
Completion result = completions(ep, "llama3", ctx);
ToolCall call = result.choice.toolCalls[0];
Tool tool = ep.tools.get(call.name);
JSONValue output = tool.impl(call.arguments);

ctx.tool(call.id, output);
Completion finalResult = completions(ep, "llama3", ctx);
```

The first completion is already appended to `ctx`, including its tool calls. See [Tools](TOOLS.md) for registration and execution.

## Compaction

Assign a `Compactor` to enforce message or token limits after each append:

```d
Context ctx;
ctx.compactor = new Compactor();
ctx.compactor.maxMessages = 20;
ctx.compactor.maxTokens = 32_000;
ctx.compactor.strategy = CompactorStrategy.Trim;
```

A zero limit disables that limit. A new `Compactor` defaults to a 250,000-token limit and no message-count limit.

The token total is estimated from stored assistant completions:

- Sum the completion tokens from every assistant message.
- Add the prompt tokens from the most recent assistant message.

Synthetic assistant messages do not contribute tokens unless their wrapped completion contains usage data.

### Trim Strategy

`CompactorStrategy.Trim` removes the oldest non-system messages until every configured limit is satisfied. System messages are preserved. If only system messages remain and still exceed a configured message limit, no more messages can be removed.

Because messages are removed individually, trimming does not guarantee that assistant tool calls and their matching tool results remain together.

### Callback Strategy

`CompactorStrategy.Callback` delegates compaction to caller code:

```d
ctx.compactor.strategy = CompactorStrategy.Callback;
ctx.compactor.callback = (IMessage[] messages) {
    if (messages.length <= 10)
        return messages;
    return messages[$ - 10..$];
};
```

The callback runs only after a configured limit is exceeded. If it is null, the messages are left unchanged.

Routers construct a compactor automatically. When `OpenRouter.active(modelName)` finds model metadata, it changes `maxTokens` to that model's context length without immediately compacting existing messages. Compaction occurs on the next append.

## Serialization

`ctx.toJSON()` returns an array of serialized message objects:

```d
import std.json : JSONValue;

JSONValue messages = ctx.toJSON();
```

Use the public `messages` array when individual message types or stored completion metadata are needed.
