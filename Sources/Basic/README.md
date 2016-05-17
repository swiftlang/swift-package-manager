# Basic Library

This library contains the basic support facilities for `swiftpm`. It is layered
on `libc`, `POSIX`, and `Foundation`, and defines the shared data structures,
utilities, and algorithms for the rest of the package manager.

This library is also intended to contain the bulk of the cross-platform
compatibility logic not present in lower layers, so that higher level libraries
can be written in as platform agnostic a manner as possible.
