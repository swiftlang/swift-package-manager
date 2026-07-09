#include "cxx2.h"

// See Cxx1/cxx1.cpp for why this uses C++ exceptions.
extern "C" int cxx2() {
    try {
        throw 2;
    } catch (...) {
        return 2;
    }
    return 0;
}
