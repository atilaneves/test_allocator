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
        inout(void)[] opSlice() @trusted @nogc inout nothrow {
            return ptr[0 .. length];
        }
    }

    private ByteRange[] _allocations;
    private int _numAllocations;

    enum uint alignment = platformAlignment;

    void[] allocate(size_t numBytes) @safe @nogc nothrow {
        import std.experimental.allocator: makeArray, expandArray;

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

    bool deallocate(void[] bytes) @trusted @nogc nothrow pure {
        import std.algorithm: remove, canFind;
        import core.stdc.stdio: sprintf;

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

    ~this() @safe @nogc nothrow pure {
        verify;
    }

    void verify() @trusted @nogc nothrow pure {

        char[1024] buffer;

        if(_allocations.length) {
            import core.stdc.stdio: sprintf;
            auto index = pureSprintf(&buffer[0], "Memory leak in TestAllocator. Allocations:\n");
            index = printAllocations(buffer, index);
            assert(false, buffer[0 .. index]);
        }
    }

    pure
    int printAllocations(int N)(ref char[N] buffer, int index = 0) @trusted @nogc const nothrow {
        import core.stdc.stdio: sprintf;
        index += pureSprintf(&buffer[index], "[");
        foreach(ref allocation; _allocations) {
            index += pureSprintf(&buffer[index], "ByteRange(%p, %ld), ",
                             allocation.ptr, allocation.length);
        }

        index += pureSprintf(&buffer[index], "]");
        return index;
    }
}

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

unittest
{
    import std.experimental.allocator : allocatorObject;
    import std.experimental.allocator.building_blocks.stats_collector;
    import std.experimental.allocator.mallocator: Mallocator;
    import std.conv : to;

    alias SCAlloc = StatsCollector!(TestAllocator, Options.bytesUsed);

    SCAlloc statsCollectorAlloc;
    {
        auto _allocator = allocatorObject(&statsCollectorAlloc);
        auto buf = _allocator.allocate(10);
        _allocator.deallocate(buf);
    }
    auto bytesUsed = statsCollectorAlloc.bytesUsed;
    assert(bytesUsed == 0, "Ref count leaks memory; leaked " ~ to!string(bytesUsed) ~ " bytes");
}
