module lmd.response;

import lmd.context;
import lmd.model;
import lmd.exception;
import lmd.tool;
import core.atomic;
import core.thread;
import std.string;
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

enum RequestKind : string
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

struct Choice
{
    Context context;
    string reasoning;
    float logprobs;
    FinishReason finishReason;
    
    string text(size_t index = 0)
    {
        if (index >= context.messages.length)
            throw new RangeError();
        Message msg = context.messages[index];
        return msg.isText() ? msg.text() : null;
    }
    
    Tool tool(size_t index = 0)
    {
        if (index >= context.messages.length)
            throw new RangeError();
        Message msg = context.messages[index];
        return msg.isTool() ? msg.tool() : Tool.init;
    }
}

struct Response
{
    Model model;
    Exception error = null;
    RequestKind kind;
    union
    {
        Choice[] choices;
        Embedding[] embeddings;
    }
    long promptTokens;
    long completionTokens;
    long totalTokens;
    string fingerprint;
    string id;

    this(Model model, Exception error)
    {
        this.model = model;
        this.error = error;
    }

    bool bubble()
    {
        if (error !is null)
            throw error;
        return choices.length > 0 || embeddings.length > 0;
    }

    T pick(T)(size_t index = 0)
        if (is(T == Choice) || is(T == Embedding) || is(T == string) || is(T == float[]))
    {
        static if (is(T == Choice))
        {
            if (index >= choices.length)
                throw new RangeError();

            if (kind != RequestKind.ChatCompletionChunk)
                model.context.merge(choices[index].context);

            return choices[index];
        }
        else static if (is(T == Embedding))
        {
            if (index >= embeddings.length)
                throw new RangeError();
            return embeddings[index];
        }
        else static if (is(T == string))
            return pick!Choice(index).text();
        else static if (is(T == float[]))
            return pick!Embedding(index).value;
    }

    T pick(T)()
        if (is(T == Choice) || is(T == Embedding) || is(T == string) || is(T == float[]))
        => pick!T(0);
}

class ResponseStream
{
package:
    void delegate(ResponseStream) _commence;
    Response[] responses;
    shared size_t length;
    shared size_t index;
    shared bool writer;

public:
    // TODO: This feels bloated especially having Model everywhere.
    Model model;
    bool complete;
    void delegate(Response) callback;

    this(Model model, void delegate(Response) callback)
    {
        this.model = model;
        this.callback = callback;
        this.responses = null;
        this.length = 0;
        this.index = 0;
        this.writer = false;
        this.complete = false;
    }

    Response next()
    {
        if (_commence is null)
            throw new ModelException(
                "not_initialized",
                "Stream not initialized",
                "stream",
                "invalid_request_error"
            );

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
        
        // TODO: Adding responses to a queue is incredibly memory inefficient.
        //       Also doesn't have continuity which seems like a problem.
        responses ~= val;
        atomicFetchAdd!(MemoryOrder.rel)(length, 1);
        
        atomicFence!(MemoryOrder.rel);
        atomicStore!(MemoryOrder.rel)(writer, false);
    }
}
