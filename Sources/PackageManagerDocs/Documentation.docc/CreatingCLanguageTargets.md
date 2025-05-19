# Creating C language targets

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

C language targets are similar to Swift targets, except that the C language
libraries should contain a directory named `include` to hold the public headers.

To allow a Swift target to import a C language target, add a [target](PackageDescription.md#target) in the manifest file. Swift Package Manager will
automatically generate a modulemap for each C language library target for these
3 cases:

* If `include/Foo/Foo.h` exists and `Foo` is the only directory under the
  include directory, and the include directory contains no header files, then
  `include/Foo/Foo.h` becomes the umbrella header.

* If `include/Foo.h` exists and `include` contains no other subdirectory, then
  `include/Foo.h` becomes the umbrella header.

* Otherwise, the `include` directory becomes an umbrella directory, which means
  that all headers under it will be included in the module.

In case of complicated `include` layouts or headers that are not compatible with
modules, a custom `module.modulemap` can be provided in the `include` directory.

For executable targets, only one valid C language main file is allowed, e.g., it
is invalid to have `main.c` and `main.cpp` in the same target.
