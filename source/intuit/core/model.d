/// Model profile, capabilities, and modalities.
module intuit.core.model;

import std.json : JSONValue;

/// Input or output modality supported by a model.
enum Modality : string
{
    /// Plain text input or output.
    text = "text",
    /// Image input or output.
    image = "image",
    /// Audio input or output.
    audio = "audio",
    /// PDF document input.
    pdf = "pdf",
    /// Embedding vector output.
    embedding = "embedding",
}

/// Capability flags describing what a model can do.
enum Capability : string
{
    /// Chat / completions.
    Chat = "chat",
    /// Tool / function calling.
    Tools = "tools",
    /// Vision / image input.
    Vision = "vision",
    /// Structured output via JSON schema.
    StructuredOutput = "structured_output",
    /// Embeddings generation.
    Embeddings = "embeddings",
    /// Audio input.
    AudioInput = "audio_input",
    /// Audio output.
    AudioOutput = "audio_output",
    /// Reasoning / thinking output.
    Reasoning = "reasoning",
    /// Prompt caching support.
    PromptCaching = "prompt_caching",
    /// Web search integration.
    WebSearch = "web_search",
}

/// Static metadata describing a model's capabilities and constraints.
class ModelProfile
{
    /// The model slug, e.g. "openai/gpt-4o".
    string id;
    /// The provider name, e.g. "openai".
    string provider;
    /// Human-readable display name.
    string name;
    /// Model description text.
    string description;
    /// Capability flags.
    Capability[] capabilities;
    /// Total context window in tokens; drives the compactor token limit.
    size_t contextLength;
    /// Maximum tokens the model can generate in a single response.
    size_t maxOutputTokens;
    /// Supported input modalities.
    Modality[] inputModalities;
    /// Supported output modalities.
    Modality[] outputModalities;
    /// OpenAI-compatible parameters the model accepts, e.g. ["tools", "temperature"].
    string[] supportedParameters;
    /// Cost in USD per input token.
    double promptCost;
    /// Cost in USD per output token.
    double completionCost;
    /// Raw provider-specific metadata.
    JSONValue raw;

    /**
     * Constructs a ModelProfile with a minimal identity.
     *
     * Params:
     *  id = The model identifier.
     *  provider = The provider name.
     */
    this(string id, string provider = null)
    {
        this.id = id;
        this.provider = provider;
        this.name = id;
    }
}
