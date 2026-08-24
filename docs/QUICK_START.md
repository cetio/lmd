# Quick Start

Intuit can be used at 2 different layers, routers and endpoints, with strings being used to reference models through one of them. 

## Routers

Routers are endpoint-agnostic interfaces for interacting with models with a shared context, automatic limits, and fine-grain details on models (such as cost, token limits, etc.) They are used to implement load balancing, failover, and other routing logic. 

This is effectively the same basis as most chat clients which display context information, costs, and allow for selecting different models in the same chat.

### How does this tie in with models?

// TODO: Finish this

Routers maintain an active model (`IRouter.active`). Changing model will change context limit but not activate compaction, meaning messages will only be affected on the next message. A router will have a default context and compactor for message management and, unlike endpoints, is stateful and maintains a "conversation" with an active model.

| Router | Description | Reference |
|--------|---------|---------|
| `IRouter` | Base interface for all routers. | |
| `LocalRouter` | Local router implementation, with a configurable default catalog. | |
| `OpenRouter` | OpenRouter implementation. | https://openrouter.ai/ |


## Endpoints

Endpoints are used to make requests to different providers. They are used to implement different providers like OpenAI, Anthropic, etc. but do not keep track of context. Settings can be configured for multiple models via `BaseModel` (or specific model implementations like `QwenModel`).

It is generally recommended not to use endpoints directly, but rather use routers for a more consistent and feature-rich experience.

| Endpoint | Description | Reference |
|----------|-------------|-----------|
| `IEndpoint` | Base interface for all endpoints. | |
| `OpenAI` | OpenAI implementation. | https://openai.com/ |
| `Qwen` | Alibaba's Qwen implementation. | https://qwen.ai/research/ |
| `Claude` | Anthropic implementation. | https://anthropic.com/ |

## Models

Model implementations are used to configure settings for specific models.
| Model | Description | Reference |
|-------|-------------|-----------|
| `BaseModel` | Base model implementation. | |
| `QwenModel` | Qwen model implementation. | https://qwen.ai/research/ |
| `ClaudeModel` | Claude model implementation. | https://anthropic.com/ |
| `OpenAIModel` | OpenAI model implementation. | https://openai.com/ |