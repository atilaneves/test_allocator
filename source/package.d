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

    void[] allocate(size_t numBytes) {
        ++_numAllocations;
        auto ret = allocator.allocate(numBytes);
        _allocations ~= ByteRange(ret.ptr, ret.length);
        return ret;
    }

    bool deallocate(void[] bytes) {
        import std.algorithm: remove, canFind;
        import std.conv: text;

        bool pred(ByteRange other) { return other.ptr == bytes.ptr && other.length == bytes.length; }

        assert(_allocations.canFind!pred,
                text("Unknown deallocate byte range. Ptr: ", bytes.ptr, " length: ", bytes.length,
                     " allocations: ", _allocations));
        _allocations = _allocations.remove!pred;
        return allocator.deallocate(bytes);
    }

    auto numAllocations() @safe pure nothrow const {
        return _numAllocations;
    }

    ~this() {
        import std.conv: text;
        assert(!_allocations.length, text("Memory leak in TestAllocator. Allocations: ", _allocations));
    }
}
