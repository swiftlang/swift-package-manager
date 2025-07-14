# Creating C language targets

Include C language code as a target in your Swift package.

## Overview

C language targets are structured similarly to Swift targets, with the additional of a directory, commonly named `include`, to hold public header files.
If you use a directory other than `include` for public headers, declare it using the [publicHeadersPath parameter](https://developer.apple.com/documentation/packagedescription/target/publicheaderspath) on [target](https://developer.apple.com/documentation/packagedescription/target).

Swift Package manager allows only one valid C language main file for executable targets. 
For example, it is invalid to have `main.c` and `main.cpp` in the same target.

### Exposing C functions to Swift

Swift Package Manager automatically generates a module map for each C language library target for these use cases:

* If `include/Foo/Foo.h` exists, `Foo` is the only directory under the include directory, and the include directory contains no header files, then Swift package manager uses `include/Foo/Foo.h` as the umbrella header.

* If `include/Foo.h` exists and `include` contains no other subdirectory, then Swift package manager uses `include/Foo.h` as the umbrella header for the module map.

* Otherwise, Swift package manager uses the `include` directory as an umbrella directory; all headers under it are included in the module.

In case of complicated `include` layouts or headers that are not compatible with modules, provide a `module.modulemap` in the `include` directory.
