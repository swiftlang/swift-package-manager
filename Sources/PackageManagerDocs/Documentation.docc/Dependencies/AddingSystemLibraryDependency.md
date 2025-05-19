# Adding a dependency to a system library.

Define the location for the library and provide module map to expose C headers to Swift. 

## Overview

You can link against system libraries using the package manager. 
To do so, add a `target` of type [systemLibrary](https://developer.apple.com/documentation/packagedescription/target/systemlibrary(name:path:pkgconfig:providers:)), and a `module.modulemap` for each system library you're using.

### Declaring the system library

The `systemLibrary` definition informs the Swift compiler of where to find the C library.
For building on Unix-like systems, the package manager uses `pkg-config` to look up where a library is installed. 
Specify the name of the C library you want to look up on those systems.
For building on Windows, omit `pkgConfig`, as the command `pkg-config` is not expected to be available.

If you omit the optional pkgConfig parameter, pass the path of a directory containing the library using the `-L` flag in the command line when building your package.
For example, if the library you depend on resides in `/usr/local/lib/`, the following command tells the linker to add that path when building the project:

```bash
% swift build -Xlinker -L/usr/local/lib/
```

#### System Libraries With Optional Dependencies

To reference a system library with optional dependencies, you to make another module map package to represent the optional library.

For example, `libarchive` optionally depends on `xz`, which means it can be compiled with `xz` support, but it is not required. 
To provide a package that uses libarchive with xz you must make a `CArchive+CXz` package that depends on `CXz` and provides `CArchive`.

### Defining the module map

The `module.modulemap` file declares the C library headers, and what parts of them, to expose in Swift. 
A `module.modulemap` file contains one or more maps. 
Each map defining a name for the Swift module to be exposed, one or more header files to reference, a reference to the name of the C library, and one or more export lines that identify what to expose to Swift.

For example, the following 

```
module Clibgit [system] {
  header "git2.h"
  link "git2"
  export *
}
```

Module maps must contain absolute paths. As such, they are not cross-platform.
Use a local header and let the linker handle the location of the binary with a pkgConfig parameter in the `systemLibrary` declaration if you can.

For more information on the structure of module maps, see the [LLVM](https://llvm.org/) documentation: [Module Map Language](https://clang.llvm.org/docs/Modules.html#module-map-language).

#### Module Map Versioning

Version the module maps semantically. 
The meaning of semantic version is less clear here, so use your best judgement. 
Do not follow the version of the system library the module map represents; version the module map(s) independently.

Follow the conventions of system packagers; for example, the Debian package for `python3` is called `python3`. 
In Debian, there is not a single package for python; the system packagers designed it to be installed side-by-side with other versions. 
The recommended name for a module map for `python3` on a Debian system is `CPython3`.

#### Packages That Provide Multiple Libraries

To use a system package that provides multiple libraries, such as `.so` and `.dylib` files, add all the libraries to the `module.modulemap` file. 

```
module CFoo [system] {
    header "/usr/local/include/foo/foo.h"
    link "foo"
    export *
}

module CFooBar [system] {
    header "/usr/include/foo/bar.h"
    link "foobar"
    export *
}

module CFooBaz [system] {
    header "/usr/include/foo/baz.h"
    link "foobaz"
    export *
}
```

In the above example `foobar` and `foobaz` link to `foo`. 
You don’t need to specify this information in the module map because the headers `foo/bar.h` and `foo/baz.h` both include `foo/foo.h`. 
It is very important however that those headers do include their dependent headers.
Otherwise when the modules are imported into Swift the dependent modules are not imported automatically and you will receive link errors. 
If link errors occur for consumers of your package, the link errors can be especially difficult to debug.

## See Also

- <doc:ExampleSystemLibraryPkgConfig>
- <doc:ExampleSystemLibraryWithoutPkgConfig>
