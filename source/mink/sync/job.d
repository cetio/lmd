module mink.sync.job;

import mink.traits;
import mink.sync.atomic;
import mink.sync.executor;
import core.thread;

enum JobState : ubyte
{
    pending,
    running,
    completed,
    failed
}

interface IJob
{
    enum type = "undefined";
    void stub();
    bool await();
    JobState getState();
}

/// Lock-free job implementation with minimal memory footprint
class Job(T) : IJob
{
    enum type = T.stringof;
private:
    T delegate() inner;
    Atom!JobState state;
    Exception exception;
    Atom!bool hasResult;

public:
    static if (!is(T == void))
    T value;

    this()
    {
        state.store(JobState.pending);
        hasResult.store(false);
    }

    void stub()
    {
        state.store(JobState.running);
        
        try
        {
            static if (!is(T == void))
                value = inner();
            else
                inner();
                
            state.store(JobState.completed);
        }
        catch (Exception e)
        {
            exception = e;
            state.store(JobState.failed);
        }
        
        hasResult.store(true);
    }

    T wait()
    {
        while (!hasResult.load())
            Thread.yield();
            
        if (state.load() == JobState.failed)
            throw exception;
            
        static if (!is(T == void))
            return value;
    }

    bool await() 
    {
        while (!hasResult.load())
            Thread.yield();
            
        return state.load() == JobState.completed;
    }
    
    JobState getState() => state.load();
    
    void setInner(T delegate() func)
    {
        inner = func;
    }
    
    void bubble()
    {
        if (state.load() == JobState.failed)
            throw exception;
    }
}

/// Submits a function for asynchronous execution and returns a Job
auto async(alias F, ARGS...)(ARGS args)
    if (isCallable!F)
{
    auto job = new Job!(ReturnType!(() => F(args)))();
    job.inner = () => F(args);
    getGlobalExecutor().submit(job);
    return job;
}