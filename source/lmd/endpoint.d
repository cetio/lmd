module lmd.endpoint;

import std.variant;
import lmd.model;
import lmd.response;

// TODO: Possibly revisit this?
Response complete(string MODEL, E : IEndpoint, T)(E ep, T data)
{
    return ep.completions(MODEL, Variant(data));
}

Response embed(string MODEL, E : IEndpoint, T)(E ep, T data)
{
    return ep.embeddings(MODEL, Variant(data));
}

interface IEndpoint
{
    ref string key();

    IModel[] available();

    IModel fetch(string model);

    Response completions(string model, Variant data);

    // TODO: Legacy completions.

    Response embeddings(string model, Variant data);

    ResponseStream stream(string model, Variant data);
}