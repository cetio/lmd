# LMD

LMD is a library for interfacing with LLM APIs. Connect to OpenAI, LMStudio, or any compatible endpoint. Send messages, get responses, manage conversations.

The system is modular, allowing for new Endpoints to be implemented through `IEndpoint` and supporting common API out of the box.

Streaming is designed to be intuitive and threadable using `ResponseStream` which can be blocked (forcing a wait for each iterative `Response`) or classic with a callback for incoming responses.

## Use

Import the library:

```d
import lmd;
// Or for specifically OpenAI-style endpoints:
import lmd.common.openai;
```

Create an endpoint and load a model:

```d
// Connect to LMStudio running locally
IEndpoint ep = openai!("http", "127.0.0.1", 1234);
Model model = ep.load();

// Or connect to OpenAI
IEndpoint openai = openai!("https", "api.openai.com", 443);
Model gpt4 = openai.load("gpt-4", "your-api-key");
```

Send messages and get responses:

```d
// Simple completion
Response resp = model.send("What is 2+2?");
string answer = resp.choices[0].content;

// With system prompt
model.setSystemPrompt("You are a helpful assistant.");
Response resp = model.send("Explain quantum computing briefly.");

// Streaming responses
model.stream((StreamChunk chunk) {
    foreach (choice; chunk.choices) {
        write(choice.content);
    }
})("Tell me a story");
```

Handle tool calls:

```d
// Define tools
Tool[] tools = [
    Tool("function", "get_weather", "Get current weather", /* parameters */)
];

Options opts;
opts.tools = tools;

Model model = ep.load("model-name", "owner", opts);
Response resp = model.send("What's the weather like?");

// Check for tool calls
if (resp.choices[0].toolCalls.length > 0) {
    // Handle tool execution
    model.addToolMessage(toolCallId, result);
}
```

## Endpoints

Currently supports OpenAI-compatible endpoints:

- `/v1/chat/completions` - Main chat interface
- `/v1/completions` - Legacy completion endpoint  
- `/v1/models` - List available models

Works with:
- OpenAI API
- LMStudio
- Ollama
- Any OpenAI-compatible server

## Roadmap

- [X] /v1/models
- [X] /v1/completions
- [X] /v1/chat/completions
- [ ] /v1/embeddings
- [ ] /v1/audio
- [ ] /v1/image
- [X] Streaming
- [ ] Standardize no-think and support OpenAI-specific Options keys
- [ ] Modularize Options to be by-endpoint
- [ ] Claude and Gemini support
- [ ] Document all code with DDocs formatting
- [ ] Support other schema than HTTP

## Contributing

Please do not contribute. I don't want to review your code.

## License

LMD is licensed under [AGPL-3.0](LICENSE.txt).