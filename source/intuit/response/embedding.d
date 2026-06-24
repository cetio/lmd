/// Embedding vector type.
module intuit.response.embedding;

/// Wrapper around an embedding vector that implicitly converts to its value.
struct Embedding(T)
{
    alias value this;

    /// The embedding vector values.
    T[] value;
}
