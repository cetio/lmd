module mink.sync.atomic;

import mink.traits;
import core.atomic;
import core.thread;
import core.sync.mutex;
import std.bitmanip;

// The idea:
// Atoms wrap any type and are guaranteed to be atomic for any one line, no matter what.
// For instance `(Atom!int) foo = 1;` will always be atomic.
// For scopes that need to be atomic they can use Mutex for locking:
// Atom!T.lock(() {
// if (foo == 1)
//    foo ^= 3;
// else
//     foo += 2
// });
shared struct Atom(T)
    if (isPOD!T && T.sizeof <= size_t.sizeof * 2)
{
    // TODO: Lock table should be constructed and __MODULE__ + __LINE__ will act as an identifier to query into the table for this lock.
    shared T value;
    shared Mutex mutex;
    alias value this;

    this(T val)
    {
        value = val;
        mutex = new shared Mutex();
    }

    T load()
    {
        return cast(T)atomicLoad!(MemoryOrder.seq)(value);
    }

    void store(T val)
    {
        atomicStore!(MemoryOrder.seq)(value, val);
    }

    bool cmpxchg(T cmp, T val)
    {
        return cas!(MemoryOrder.seq, MemoryOrder.seq)(&value, cmp, val);
    }

    auto lock(T)(T dg)
        if (isCallable!dg)
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        static if (is(ReturnType!dg == void))
            dg();
        else
            return dg();
    }
}

shared struct Atom(T)
    if (!isPOD!T || T.sizeof > size_t.sizeof * 2)
{
    shared T value;
    shared Mutex mutex;
    alias value this;

    this(T val)
    {
        value = cast(shared(T))val;
        mutex = new shared Mutex();
    }

    T load()
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        return cast(T)value;
    }

    void store(T val)
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        value = cast(shared(T))val;
    }

    bool cmpxchg(T cmp, T val)
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        bool ret = cast(T)value == cmp;
        value = cast(shared(T))(cast(T)value == cmp ? val : cast(T)value);
        return ret;
    }

    auto lock(F)(F dg)
        if (isCallable!F)
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        static if (is(ReturnType!F == void))
            dg();
        else
            return dg();
    }
}