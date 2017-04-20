module test_allocator;

// tracks allocations and throws in the destructor if there is a memory leak
// it also throws when there is an attempt to deallocate memory that wasn't
// allocated
struct TestAllocator {
    import std.experimental.allocator.common: platformAlignment;
    import std.experimental.allocator.mallocator: Mallocator;

    alias allocator = Mallocator.instance;

    private static struct ByteRange {
        void* ptr;
        size_t length;
    }

    private ByteRange[] _allocations;
    private int _numAllocations;

    enum uint alignment = platformAlignment;

    void[] allocate(size_t numBytes) @safe @nogc {
        import std.experimental.allocator: makeArray, expandArray;

        static const exception = new Exception("Allocation failed");

        ++_numAllocations;

        auto ret = allocator.allocate(numBytes);
        if(numBytes > 0 && ret.length == 0)
            throw exception;

        auto newEntry = ByteRange(&ret[0], ret.length);

        if(_allocations is null)
            _allocations = allocator.makeArray(1, newEntry);
        else
            () @trusted { allocator.expandArray(_allocations, 1, newEntry); }();

        return ret;
    }

    bool deallocate(void[] bytes) @trusted @nogc nothrow {
        import std.algorithm: remove, canFind;
        import core.stdc.stdio: sprintf;

        bool pred(ByteRange other) { return other.ptr == bytes.ptr && other.length == bytes.length; }

        static char[1024] buffer;

        if(!_allocations.canFind!pred) {
            auto index = sprintf(&buffer[0],
                                 "Unknown deallocate byte range. Ptr: %p, length: %ld, allocations:\n",
                                 &bytes[0], bytes.length);
            index = printAllocations(buffer, index);
            assert(false, buffer[0 .. index]);
        }
        _allocations = _allocations.remove!pred;
        return () @trusted { return allocator.deallocate(bytes); }();
    }

    auto numAllocations() @safe @nogc pure nothrow const {
        return _numAllocations;
    }

    ~this() @trusted @nogc nothrow {

        static char[1024] buffer;

        if(_allocations.length) {
            import core.stdc.stdio: sprintf;
            auto index = sprintf(&buffer[0], "Memory leak in TestAllocator. Allocations:\n");
            index = printAllocations(buffer, index);
            assert(false, buffer[0 .. index]);
        }
    }

    int printAllocations(int N)(ref char[N] buffer, int index = 0) @trusted @nogc const nothrow {
        import core.stdc.stdio: sprintf;
        index += sprintf(&buffer[index], "[");
        foreach(ref allocation; _allocations) {
            index += sprintf(&buffer[index], "ByteRange(%p, %ld), ",
                             allocation.ptr, allocation.length);
        }

        index += sprintf(&buffer[index], "]");
        return index;
    }
}
