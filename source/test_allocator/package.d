module test_allocator;

// tracks allocations and throws in the destructor if there is a memory leak
// it also throws when there is an attempt to deallocate memory that wasn't
// allocated
struct TestAllocator {
    import std.experimental.allocator.common: platformAlignment;
    import std.experimental.allocator.mallocator: Mallocator;

    alias allocator = Mallocator.instance;

    @safe @nogc nothrow:

    private static struct ByteRange {
        void* ptr;
        size_t length;
        inout(void)[] opSlice() @trusted @nogc nothrow pure inout {
            return ptr[0 .. length];
        }
    }

    private ByteRange[] _allocations;
    private int _numAllocations;
    private char[1024] _textBuffer;

    enum uint alignment = platformAlignment;

    void[] allocate(size_t numBytes) scope {
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

    bool deallocate(void[] bytes) scope pure {
        import std.algorithm: remove, canFind;
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }

        bool pred(ByteRange other) { return other.ptr == bytes.ptr && other.length == bytes.length; }

        static char[1024] buffer;

        // @trusted because this is `scope` and we're taking the address of it
        assert(() @trusted { return &this !is null; }(), "Attempting to deallocate when `this` is null");

        if(!_allocations.canFind!pred) {
            auto index = pureSprintf(
                () @trusted { return _textBuffer.ptr; }(),
                "Cannot deallocate unknown byte range.\nPtr: %p, length: %ld, allocations:\n",
                () @trusted { return bytes.ptr; }(), bytes.length);
            index = printAllocations(_textBuffer, index);
            _textBuffer[index] = 0;
            debug
                assert(false, _textBuffer[0 .. index].dup);
            else
                assert(false, "Cannot deallocate unknown byte range. Use debug mode to see more information");
        }

        _allocations = _allocations.remove!pred;

        return () @trusted { return allocator.deallocate(bytes); }();
    }

    bool deallocateAll() scope pure {
        foreach(ref allocation; _allocations) {
            deallocate(allocation[]);
        }
        return true;
    }

    auto numAllocations() pure const scope {
        return _numAllocations;
    }

    ~this() pure {
        verify;
        finalise;
    }

    private void finalise() scope pure {
        import std.experimental.allocator: dispose;
        deallocateAll;
        () @trusted { allocator.dispose(_allocations); }();
    }

    void verify() scope pure {
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }

        if(_allocations.length) {
            auto index = pureSprintf(
                () @trusted { return _textBuffer.ptr; }(),
                "Memory leak in TestAllocator. Allocations:\n");
            index = printAllocations(_textBuffer, index);
            _textBuffer[index] = 0;

            finalise;  // avoid asan leaks

            debug
                assert(false, _textBuffer[0 .. index].dup);
            else
                assert(false, "Memory leak in TestAllocator. Use debug mode to see more information");
        }
    }

    int printAllocations(int N)(ref char[N] buffer, int index = 0) pure const scope {
        static if (__VERSION__ < 2077)
        {
            import core.stdc.stdio: sprintf;
            alias pureSprintf = sprintf;
        }

        index += pureSprintf(&buffer[index], "[");

        if(_allocations !is null) {
            foreach(ref allocation; _allocations) {
                index += pureSprintf(&buffer[index], "ByteRange(%p, %ld), ",
                                     allocation.ptr, allocation.length);
            }
        }

        index += pureSprintf(&buffer[index], "]");
        return index;
    }
}

static if (__VERSION__ >= 2077)
{
    /* Private bits that allow sprintf to become pure */
    private int pureSprintf(A...)(scope char* s, scope const(char*) format, A va)
        @trusted pure nothrow
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

@safe @nogc nothrow unittest {
    import std.experimental.allocator : allocatorObject;
    import std.experimental.allocator.building_blocks.stats_collector;
    import std.experimental.allocator.mallocator: Mallocator;
    import std.conv : to;

    alias SCAlloc = StatsCollector!(TestAllocator, Options.bytesUsed);

    SCAlloc allocator;
    auto buf = allocator.allocate(10);
    allocator.deallocate(buf);
    assert(allocator.bytesUsed == 0);
}


@safe @nogc nothrow unittest {
    auto obj = TestAllocator();
    scope ptr = &obj;
}


@safe @nogc unittest {
    import std.experimental.allocator: makeArray, expandArray, dispose;
    auto allocator = TestAllocator();
    auto array = allocator.makeArray!int(3);
    // expandArray is @system because Mallocator.reallocate is @system,
    // and that in turn is because reallocate may make pointers dangle.
    const expanded = () @trusted { return allocator.expandArray(array, 2); }();
    allocator.dispose(array);
}
