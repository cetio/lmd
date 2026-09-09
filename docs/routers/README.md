# Routers

An `IRouter` presents models from one or more backing providers through a single stateful interface. A router owns a `Context`, a tool registry, a model catalog, and one active model.

- [Getting Started](GETTING_STARTED.md) — discover models, select an active model, configure requests, and use the maintained context.

Built-in routers:

| Class | Model catalog | Requests |
| --- | --- | --- |
| `OpenRouter` | Dynamic catalog from `/api/v1/models`. | Completions and embeddings. |
| `LiteLLM` | Dynamic catalog from `/v1/model/info`. | Not yet implemented. |

`OpenRouter` can make requests through the public OpenRouter API or a compatible deployment. `LiteLLM` currently exposes catalog metadata only; active-model selection, model configuration, completions, and embeddings throw.

Routers differ from endpoints in two important ways:

- Router request functions use the active model instead of accepting a model name.
- Completion requests always use and update the router's maintained context.

See [Getting Started](GETTING_STARTED.md) for the implemented surface and current limitations.
