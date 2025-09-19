module mink.sync.container;

// TODO: Documentation
import mink.sync.atomic;
import core.sync.mutex;

/// Thread-safe circular queue implementation
class Queue(T)
{
private:
    T[] items;
    Atom!size_t head;
    Atom!size_t tail;
    Atom!size_t count;
    shared Mutex mutex;

public:
    this(size_t capacity = 1024)
    {
        items = new T[capacity];
        head = Atom!size_t(0);
        tail = Atom!size_t(0);
        count = Atom!size_t(0);
        mutex = new shared Mutex();
    }

    /// Get current queue size (may be stale)
    size_t size() => count.load();
    
    /// Check if queue is empty (may be stale)
    bool empty() => count.load() == 0;
    
    /// Get queue capacity
    size_t capacity() const => items.length;

    bool tryEnqueue(T item)
    {
        mutex.lock();
        scope (exit) mutex.unlock();
        
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
        mutex.lock();
        scope (exit) mutex.unlock();
        
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
