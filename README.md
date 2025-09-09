# LMD

A D library for interfacing with LLM APIs. Connect to OpenAI, LMStudio, or any compatible endpoint. Send messages, get responses, manage conversations.

## Install

Add to your `dub.json`:

```json
{
    "dependencies": {
        "lmd": "~>0.1.0"
    }
}
```

## Use

Import the library:

```d
import lmd;
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

Configure generation options:

```d
Options opts;
opts.temperature = 0.7;
opts.maxTokens = 100;
opts.topP = 0.9;

Model model = ep.load("model-name", "owner", opts);
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

## Examples

See `source/examples/vibesort.d` for a complete working example.

## API Reference

### IEndpoint
Interface for LLM endpoints. Create with `openai!(scheme, address, port)`.

### Model
Represents a loaded model instance. Use `ep.load()` to create.

**Methods:**
- `send(string prompt)` - Send message, get response
- `stream(void delegate(StreamChunk) callback)(string prompt)` - Stream response
- `setSystemPrompt(string prompt)` - Set system message
- `addToolMessage(string toolCallId, string content)` - Add tool result

### Response
Contains model response and metadata.

**Fields:**
- `choices[]` - Array of response choices
- `totalTokens` - Token usage count
- `exception` - Error if request failed

### Options
Generation parameters.

**Fields:**
- `temperature` - Randomness (0.0-2.0)
- `maxTokens` - Maximum tokens to generate
- `topP` - Nucleus sampling
- `tools[]` - Available tools for model
- `stream` - Enable streaming

## Roadmap

- [X] /v1/models
- [X] /v1/completions
- [X] /v1/chat/completions
- [ ] /v1/embeddings
- [ ] /v1/audio
- [ ] /v1/image
- [X] Streaming
- [ ] Standardize no-think
- [ ] Claude and Gemini support
- [ ] Authorization for `endpoint.available`
- [ ] Tool usage and statistics
- [ ] Document all code with DDocs formatting

## Contributing

Please do not contribute. I don't want to review your code.

## License

LMD is licensed under [AGPL-3.0](LICENSE.txt).