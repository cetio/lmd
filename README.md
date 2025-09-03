# LLMD

D client for OpenAI-style chat completions. Small, explicit, and practical, with support for many common structures and designed to seamlessly work with LMStudio for using language models locally.

LLMD can handle:
- High context prompts/series of messages with roles.
- Sending and receiving messages with variant support between `Response` and `JSONValue` queries.
- Normalizing assistant responses into choice and option sets.
- Full option sets (`frequency_penalty`, `top_p`, etc.)

Supported endpoints:
- `/v1/chat/completions`

Supports HTTPS/HTTP schemes from any address/port.

## Usage

Examples are provided at [source/examples/](source/examples/)
All structures are designed to mirror LLM JSON structures and be as easy as possible to quickly pick up on.

You can see a small snippet for sorting an array incredibly slowly here:

```d
T vibesort(T)(T arr, Model model)
    if (isDynamicArray!T || isStaticArray!T)
{
    return model.send(
        "Sort this array and only output the array in the correct original syntax:"~arr.to!string
    ).choices[0].lines[$-1].to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    Model model = Model(address: "127.0.0.1", port: 1234);
    assert([2, 5, 3, 1].vibesort(model) == [1, 2, 3, 5]);
}
```

```d
public struct Options
{
    float temperature;
    float topP;
    int n = 0;
    string stop;
    int maxTokens = -1;
    float presencePenalty;
    float frequencyPenalty;
    int[string] logitBias;
}

public struct Model
{
    string scheme = "http";
    string address;
    uint port;
    /// API key, may be empty if not required.
    string key;
    /// The name of the model which this represents.
    string name;
    JSONValue[] messages;
    Options options;
}
```

## Roadmap

- [ ] `/v1/models`
- [X] `/v1/chat/completions`
- [ ] `/v1/completions`
- [ ] `/v1/embeddings`
- [ ] Tool usage and stats.
- [X] Response parsing as native structures.
- [ ] No-think mode.
- [ ] Optimization for different modes/interactions.
- [ ] Documentation.

## Contribution

LLMD is currently a very early release, and lacks documentation or fleshed out support for other endpoints than completion.

If you would like to contribute, please just make sure to follow D conventions and conventions used in my code, ideally with a formatter but any contributions are welcome!

## License

LLMD is licensed under [AGPL-3.0](LICENSE.txt).