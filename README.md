Test Allocator
=============

[![Build Status](https://travis-ci.org/atilaneves/test_allocator.png?branch=master)](https://travis-ci.org/atilaneves/test_allocator)
[![Coverage](https://codecov.io/gh/atilaneves/test_allocator/branch/master/graph/badge.svg)](https://codecov.io/gh/atilaneves/test_allocator)


`std.experimental.allocator` / `std.allocator` gives D the tools to allocate
memory as needed by the application without having to depend on the D's
mark-and-sweep garbage collector. But... how do you know if your code
is actually doing what you expect it to? Enter the test allocator
in this dub package. Essentially it tracks all allocations made through
it and throws in the destructor if there are any leaks.

It also verifies that the client code is trying to free memory that
was actually allocated via the allocator.

It's backed by mallocator for even better tracking: that way valgrind
and address sanitizer will possibly catch bugs the code in here doesn't.
