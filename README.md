# LMD

LMD provides endpoint and model support for local and remote LLM/AI models. Natively, it is designed to provide extensive and dynamic support for OpenAI with agnostic model and endpoint interfaces.

## Features

LMD is designed to be highly extensible, supporting API keys per model and using interfaced endpoints to allow for defining new endpoints. 

Supported endpoints:
- OpenAI
    - `/v1/chat/completions`
    - `/v1/completions` (legacy)
    - `/v1/models`

---

- Handles multi-message conversations with roles.
- Sends and receives messages and normalizes assistant responses.
- Full support for common generation options (`temperature`, `top_p`, `frequency_penalty`, etc.).
- Designed around LMStudio and OpenAI endpoints.


Works over HTTP and HTTPS and accepts any address/port combination.

## Usage

Examples are provided at [source/examples/](source/examples/)
All structures are designed to mirror LLM JSON structures and be as easy as possible to quickly pick up on.

You can see a small snippet for sorting an array incredibly slowly here:

```d
T vibesort(T)(T arr, Model model)
    if (isDynamicArray!T || isStaticArray!T)
{
    Response resp = model.send(
        "Sort this array and only output the array in D syntax without any code blocks or additional formatting:"~arr.to!string
    );
    return resp.choices[0].lines[$-1].to!T;
}

unittest
{
    // LMStudio 127.0.0.1
    IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    // Load the default/first model.
    Model m = ep.load();
    assert([2, 5, 3, 1].vibesort(m) == [1, 2, 3, 5]);
}
```

When LMD becomes more stable, further usage will be documented.

## Roadmap

- [X] `/v1/models`
- [X] `/v1/chat/completions`
- [X] `/v1/completions`
- [ ] `/v1/embeddings`
- [ ] Tool usage and stats.
- [X] Response parsing as native structures.
- [ ] No-think mode.
- [ ] Optimization for different modes/interactions.
- [ ] Documentation.

## Contribution

LMD is currently a very early release, and lacks documentation or fleshed out support for other endpoints than completion.

If you would like to contribute, please just make sure to follow D conventions and conventions used in my code, ideally with a formatter but any contributions are welcome!

## License

LMD is licensed under [AGPL-3.0](LICENSE.txt).