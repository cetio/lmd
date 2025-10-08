module lmd.response;

import std.variant;
import std.json;
import lmd.context;
import core.atomic;
import core.thread;
import core.exception;

enum FinishReason : string
{
    Missing = "missing",
    Length = "length",
    Max_Tokens = "max_tokens",
    ContentFilter = "content_filter",
    Refusal = "refusal",
    ToolCall = "tool_call",
    ToolUse = "tool_use",
    FunctionCall = "function_call",
    Pause = "pause",
    PauseTurn = "pause_turn",
    Stop = "stop",
    EndTurn = "end_turn",
    StopSequence = "stop_sequence",
    Unknown = "unknown"
}

enum ResponseKind : string
{
    Unknown = "unknown",
    
    ChatCompletions = "chat.completions",
    ChatCompletion = "chat.completion",
    ChatCompletionChunk = "chat.completion.chunk",
    Completion = "completion",

    Embedding = "value",
    DataList = "list",

    File = "file",
    FileContent = "file.content",
    FileSearch = "file.search",

    Image = "image",
    ImageEdit = "image.edit",

    Transcription = "transcription",
    RealtimeTranscription = "realtime.transcription_session",
    AudioBuffer = "audio.buffer",

    Conversation = "conversation",
    Message = "message",
    MessageDelta = "message.delta",
    OutputAudioBuffer = "output_audio_buffer",

    Batch = "batch",
    BatchCompleted = "batch.completed",
    WebhookEvent = "webhook_event",
    Webhook = "webhook",

    Model = "model",
    Engine = "engine",
    Deployment = "deployment",
}

struct Embedding
{
    size_t index;
    float[] value;
}

struct Completion
{
    Context context;
    FinishReason finishReason;
    float logProbs;
}

struct Response
{
    string model;
    Exception error = null;
    ResponseKind kind;
    Variant data;

    bool bubble()
    {
        if (error !is null)
            throw error;
        return completions.length > 0 || embedding.value.length > 0;
    }

    Completion[] completions()
    {
        if (kind == ResponseKind.ChatCompletions && data.type == typeid(Completion[]))
            return data.get!(Completion[]);
        throw new Exception("Response is not completions!");
    }

    Embedding embedding()
    {
        if (kind == ResponseKind.Embedding && data.type == typeid(Embedding))
            return data.get!Embedding;
        throw new Exception("Response is not an embedding!");
    }

    T select(T)(size_t index = 0)
        if (is(T == Completion) || is(T == Embedding) || is(T == string) || is(T == float[]))
    {
        static if (is(T == Completion))
        {
            Completion[] comps = completions();
            if (index >= comps.length)
                throw new RangeError();
            return comps[index];
        }
        else static if (is(T == Embedding))
        {
            Embedding emb = embedding();
            if (emb.value.length == 0)
                throw new RangeError();
            return emb;
        }
        else static if (is(T == string))
        {
            Completion comp = select!Completion(index);
            if (comp.context.messages.length == 0)
                throw new RangeError();
            return comp.context.messages[0].text();
        }
        else static if (is(T == float[]))
        {
            Embedding emb = embedding();
            if (emb.value.length == 0)
                throw new RangeError();
            return emb.value;
        }
    }

    T select(T)()
        if (is(T == Completion) || is(T == Embedding) || is(T == string) || is(T == float[]))
        => select!T(0);
}

class ResponseStream
{
private:
    Response[] responses;
    shared size_t length;
    shared size_t index;
    shared bool writer;

package:
    void delegate(ResponseStream) _commence;

public:
    JSONValue json;
    string model;
    bool complete;
    void delegate(Response) callback;

    this(string model, void delegate(Response) callback)
    {
        this.model = model;
        this.callback = callback;
        this.responses = null;
        this.length = 0;
        this.index = 0;
        this.writer = false;
        this.complete = false;
        this.json = JSONValue.emptyObject;
    }

    Response next()
    {
        if (_commence is null)
            throw new Exception("Stream not initialized");

        while (atomicLoad!(MemoryOrder.acq)(writer))
            Thread.yield();

        size_t cur = atomicFetchAdd!(MemoryOrder.seq)(index, 1);
        
        while (cur >= atomicLoad!(MemoryOrder.acq)(length))
        {
            if (complete)
                return responses[atomicLoad!(MemoryOrder.acq)(length) - 1];
            Thread.yield();
        }
        
        atomicFence!(MemoryOrder.acq);
        return responses[cur];
    }

    Response[] collect(size_t count)
    {
        Response[] ret;
        foreach (i; 0 .. count)
            ret ~= next();
        return ret;
    }

    void begin()
    {
        _commence(this);
    }

    void update(Response val)
    {
        atomicStore!(MemoryOrder.rel)(writer, true);
        atomicFence!(MemoryOrder.rel);
        
        responses ~= val;
        atomicFetchAdd!(MemoryOrder.rel)(length, 1);
        
        atomicFence!(MemoryOrder.rel);
        atomicStore!(MemoryOrder.rel)(writer, false);
    }
}