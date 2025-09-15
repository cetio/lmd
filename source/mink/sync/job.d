module mink.sync.job;

import mink.traits;
import mink.sync.atomic;
import core.sync.mutex;
import core.thread;

__gshared ThreadPool globalJobPool;

shared static this()
{
    globalJobPool = new ThreadPool();
}

shared static ~this()
{
    globalJobPool.shutdown();
}

interface IJob
{
    enum type = "undefined";
    void stub();
}

class Job(T) : IJob
{
    enum type = T.stringof;
private:
    T delegate() inner;
    shared Mutex mutex;
    Atom!bool completed;

public:
    void stub()
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        static if (!is(T == void))
            value = inner();
        else
            inner();
        completed.store(true);
    }

    static if (!is(T == void))
    T value;

    this()
    {
        mutex = new shared Mutex();
        completed = Atom!bool(false);
    }
    
    T wait()
    {
        // Use mutex for waiting instead of spin-wait to avoid CPU waste
        mutex.lock();
        scope (exit) mutex.unlock();
        static if (!is(T == void))
            return value;
    }
}

class Queue(T)
{
private:
    T[] items;
    Atom!size_t head;
    Atom!size_t tail;
    Atom!size_t count;

public:
    this(size_t capacity = 1024)
    {
        items = new T[capacity];
        head = Atom!size_t(0);
        tail = Atom!size_t(0);
        count = Atom!size_t(0);
    }

    bool tryEnqueue(T item)
    {
        size_t currentCount = count.load();
        if (currentCount >= items.length)
            return false;
            
        size_t currentTail = tail.load();
        items[currentTail] = item;
        tail.store((currentTail + 1) % items.length);
        count.store(currentCount + 1);
        return true;
    }

    bool tryDequeue(ref T item)
    {
        size_t currentCount = count.load();
        if (currentCount == 0)
            return false;
            
        size_t currentHead = head.load();
        item = items[currentHead];
        head.store((currentHead + 1) % items.length);
        count.store(currentCount - 1);
        return true;
    }
}

class ThreadPool
{
private:
    Queue!(IJob) queue;
    Thread[] workers;
    Atom!bool running;

package:
    void workerDispatch()
    {
        IJob job;
        if (queue.tryDequeue(job))
            job.stub();
        else
            // TODO: Eventually this should also support constant threading.
            return;
    }

public:
    this(size_t threads = 4)
    {
        queue = new Queue!(IJob)();
        workers = new Thread[threads];
        running = Atom!bool(true);
        
        for (size_t i = 0; i < threads; i++)
            workers[i] = new Thread(&workerDispatch);
    }

    void submit(IJob job)
    {
        // TODO: Maybe not good?
        foreach (worker; workers)
        {
            if (!worker.isRunning)
                worker.start();
        }

        // This should never fail.
        queue.tryEnqueue(job);
    }

    void shutdown() => running.store(false);
}

auto async(alias F, ARGS...)(ARGS args)
    if (isCallable!F)
{
    auto job = new Job!(ReturnType!(() => F(args)))();
    job.inner = () => F(args);
    globalJobPool.submit(job);
    return job;
}