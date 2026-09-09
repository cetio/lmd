# Documentation

Intuit is split into endpoint and router layers, with shared context, response, and tool types:

- [Endpoints](endpoints/README.md) — construct provider endpoints, fetch and configure models, and send completion and embedding requests.
- [Routers](routers/README.md) — work with routers that maintain their own context and select among endpoints behind a single active model.
- [Context](CONTEXT.md) — typed conversation messages, context accumulation, and compaction policies.
- [Responses](RESPONSES.md) — completion choices, token usage, and embedding vectors.
- [Tools](TOOLS.md) — register native D functions as tools with automatic JSON schema generation.

Project-level guides:

- [Testing](../TESTING.md)
- [Contributing](../CONTRIBUTING.md)
