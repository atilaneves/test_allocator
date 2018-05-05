module test_allocator;

// tracks allocations and throws in the destructor if there is a memory leak
// it also throws when there is an attempt to deallocate memory that wasn't
// allocated
struct TestAllocator {
    import stdx.allocator.common: platformAlignment;
    import stdx.allocator.mallocator: Mallocator;

    alias allocator = Mallocator.instance;

    private static struct ByteRange {
        void* ptr;
        size_t length;
        inout(void)[] opSlice() @trusted @nogc inout nothrow {
            return ptr[0 .. length];
        }
    }

    private ByteRange[] _allocations;
    private int _numAllocations;

    enum uint alignment = platformAlignment;

    void[] allocate(size_t numBytes) @safe @nogc nothrow {
        import stdx.allocator: makeArray, expandArray;

        ++_numAllocations;

        auto ret = allocator.allocate(numBytes);
        if(ret.length == 0) return ret;

        auto newEntry = ByteRange(&ret[0], ret.length);

        if(_allocations is null)
            _allocations = allocator.makeArray(1, newEntry);
        else
            () @trusted { allocator.expandArray(_allocations, 1, newEntry); }();

        return ret;
    }

    bool deallocate(void[] bytes) @trusted @nogc nothrow {
        import std.algorithm: remove, canFind;
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }

        bool pred(ByteRange other) { return other.ptr == bytes.ptr && other.length == bytes.length; }

        char[1024] buffer;

        if(!_allocations.canFind!pred) {
            auto index = pureSprintf(&buffer[0],
                                 "Unknown deallocate byte range. Ptr: %p, length: %ld, allocations:\n",
                                 &bytes[0], bytes.length);
            index = printAllocations(buffer, index);
            assert(false, buffer[0 .. index]);
        }

        _allocations = _allocations.remove!pred;

        return () @trusted { return allocator.deallocate(bytes); }();
    }

    bool deallocateAll() @safe @nogc nothrow {
        foreach(ref allocation; _allocations) {
            deallocate(allocation[]);
        }
        return true;
    }

    auto numAllocations() @safe @nogc pure nothrow const {
        return _numAllocations;
    }

    ~this() @safe @nogc nothrow {
        verify;
        finalise;
    }

    private void finalise() @trusted @nogc nothrow {
        import std.experimental.allocator: dispose;
        deallocateAll;
        allocator.dispose(_allocations);
    }

    void verify() @trusted @nogc nothrow {
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }

        char[1024] buffer;

        if(_allocations.length) {
            auto index = pureSprintf(&buffer[0], "Memory leak in TestAllocator. Allocations:\n");
            index = printAllocations(buffer, index);
            finalise;  // avoid asan leaks
            assert(false, buffer[0 .. index]);
        }
    }

    int printAllocations(int N)(ref char[N] buffer, int index = 0) @trusted @nogc const nothrow {
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }
        index += pureSprintf(&buffer[index], "[");
        foreach(ref allocation; _allocations) {
            index += pureSprintf(&buffer[index], "ByteRange(%p, %ld), ",
                             allocation.ptr, allocation.length);
        }

        index += pureSprintf(&buffer[index], "]");
        return index;
    }
}

static if (__VERSION__ >= 2077)
{
    /* Private bits that allow sprintf to become pure */
    private int pureSprintf(A...)(scope char* s, scope const(char*) format, A va) @trusted pure @nogc nothrow
    {
        const errnosave = fakePureErrno();
        int ret = fakePureSprintf(s, format, va);
        fakePureErrno() = errnosave;
        return ret;
    }

    extern (C) private @system @nogc nothrow
    {
        ref int fakePureErrnoImpl()
        {
            import core.stdc.errno;
            return errno();
        }
    }

    extern (C) private pure @system @nogc nothrow
    {
        pragma(mangle, "fakePureErrnoImpl") ref int fakePureErrno();
        pragma(mangle, "sprintf") int fakePureSprintf(scope char* s, scope const(char*) format, ...);
    }
}

unittest
{
    import stdx.allocator : allocatorObject;
    import stdx.allocator.building_blocks.stats_collector;
    import stdx.allocator.mallocator: Mallocator;
    import std.conv : to;

    alias SCAlloc = StatsCollector!(TestAllocator, Options.bytesUsed);

    SCAlloc allocator;
    auto buf = allocator.allocate(10);
    allocator.deallocate(buf);
    assert(allocator.bytesUsed == 0);
}
