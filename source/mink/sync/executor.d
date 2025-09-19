module mink.sync.executor;

import mink.sync.job;
import mink.sync.container;
import mink.sync.atomic;
import core.sync.condition;
import core.sync.mutex;
import core.thread;

__gshared Executor globalExecutor;

Executor getGlobalExecutor()
{
    if (globalExecutor is null)
        globalExecutor = new Executor();
    return globalExecutor;
}

shared static ~this()
{
    if (globalExecutor !is null)
    {
        // Exceptions might throw but I don't really care.
        globalExecutor.shutdown();
        globalExecutor = null;
    }
}

class Executor
{
private:
    Queue!(IJob) queue;
    Thread[] workers;
    Atom!bool running;
    shared Mutex mutex;
    shared Condition condition;

package:
    void workerLoop()
    {
        while (running.load())
        {
            mutex.lock();
            scope (exit) mutex.unlock();
            
            IJob task;
            while (running.load() && !queue.tryDequeue(task))
                condition.wait();
            
            if (task !is null)
                task.stub();
        }
    }

public:
    size_t getQueueSize() => queue.size();
    bool isRunning() => running.load();

    this(size_t threadCount = 4)
    {
        queue = new Queue!(IJob)();
        workers = new Thread[threadCount];
        running = Atom!bool(true);
        mutex = new shared Mutex();
        condition = new shared Condition(mutex);
        
        foreach (ref worker; workers)
        {
            worker = new Thread(&workerLoop);
            worker.isDaemon = true;
            worker.start();
        }
    }

    void submit(IJob task)
    {
        if (running.load() && queue.tryEnqueue(task))
            condition.notify();
    }

    void shutdown() 
    {
        running.store(false);
        condition.notifyAll();
        
        foreach (ref worker; workers)
        {
            if (worker.isRunning)
                worker.join();
        }
    }
}
