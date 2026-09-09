# Endpoints

An endpoint wraps one provider API. Every endpoint implements `IEndpoint` and exposes model configuration, completion, and embedding request functions.

- [Getting Started](GETTING_STARTED.md) — construct endpoints, fetch and configure models, and send completion and embedding requests.
- [Models](MODELS.md) — `ModelConfig` fields, provider-specific subclasses, structured output, and tool choice.

Built-in endpoint classes:

| Class | Module | API |
| --- | --- | --- |
| `OpenAI` | `intuit.provider.openai` | OpenAI Chat Completions and Embeddings. |
| `Claude` | `intuit.provider.claude` | Anthropic Messages API. No embeddings. |
| `Qwen` | `intuit.provider.qwen` | Extends `OpenAI` with Qwen-specific parameters and XML tool-call extraction. |

Endpoints are constructed with a base URL and an optional API key. Intuit does not normalize it; provider request paths such as `/v1/chat/completions` are appended to it. Intuit does not host endpoints — use a local server such as [Ollama](https://ollama.com/) or [LM Studio](https://lmstudio.ai/), a router, or the vendor's API directly.
