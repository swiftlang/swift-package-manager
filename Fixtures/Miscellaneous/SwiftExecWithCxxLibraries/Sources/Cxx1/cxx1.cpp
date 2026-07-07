#include "cxx1.h"

// Uses C++ exceptions so the object pulls in libc++abi symbols. When this
// library and Cxx2 are both statically linked into an executable for the
// static Linux SDK, each object formerly embedded its own copy of the C++
// runtime, producing duplicate libc++abi symbols at link time.
extern "C" int cxx1() {
    try {
        throw 1;
    } catch (...) {
        return 1;
    }
    return 0;
}
