# Adding a dependency on a system library.

Define the location for the library and provide module map to expose C headers to Swift. 

## Overview

You can link against system libraries, using them as a dependency in your code, using the package manager. 
To do so, add a `target` of type [systemLibrary](https://developer.apple.com/documentation/packagedescription/target/systemlibrary(name:path:pkgconfig:providers:)), and a `module.modulemap` for each system library you're using.

### Using pkg-config to provide header and linker search paths

For Unix-like systems, Swift Package Manager can use [pkgConfig](https://en.wikipedia.org/wiki/Pkg-config) to provide the compiler with the paths for including library headers and linking to binaries.
If your system doesn't provide pkgConfig, or the library doesn't include package config files, you can provide the options to the Swift compiler directly.

`pkgConfig` looks up libraries by name, which is the paramter that you pass to the systemLibrary target.
The following two examples illustrate using `libgit2` to manually look up paths for that library: 

```bash
$ pkg-config --cflags libgit2
-I/opt/homebrew/Cellar/libgit2/1.9.0/include
```

To manually provide search paths for headers, use the `-Xcc -I/path/to/include/` as additional parameters to `swift build`.
To match the above example from `pkgConfig`, the additional command line options would be:
`-Xcc -I/opt/homebrew/Cellar/libgit2/1.9.0/include`

```bash
$ pkg-config --libs-only-L libgit2
-L/opt/homebrew/Cellar/libgit2/1.9.0/lib
```

To manually provide search paths for linking to binaries, use the `-Xlinker -L/path/to/include/` as additional parameters to `swift build`.
To match the above example from `pkgConfig`, the additional command line options would be:
`-Xlinker -L/opt/homebrew/Cellar/libgit2/1.9.0/lib`.

### Declaring the system library

The `systemLibrary` definition informs the Swift compiler of where to find the C library.
When building on Unix-like systems, the package manager can use `pkg-config` to look up where a library is installed.
Specify the name of the C library you want to look up for the `pkgConfig` parameter.
To use the Swift Package Manager to install the package locally, if it isn't already installed, you can specify one or more providers.

The following example provides a declaration for the `libgit2` library, installing the library with homebrew on macOS or apt on a Debian based Linux system:

```swift
.systemLibrary(
    name: "Clibgit",
    pkgConfig: "libgit2",
    providers: [
        .brew(["libgit2"]),
        .apt(["libgit2-dev"])
    ]
)
```

### Authoring a module map

The `module.modulemap` file declares the C library headers, and what parts of them, to expose as one or more clang modules that can be imported in Swift code.
Each defines:

- A name for the module to be exposed
- One or more header files to reference
- A reference to the name of the C library
- One or more export lines that identify what to expose to Swift

For example, the following module map uses the header `git2.h`, links to `libgit2`, and exports all functions defined in the header `git2.h` to Swift:

```
module Clibgit [system] {
  header "git2.h"
  link "git2"
  export *
}
```

Try to reference headers that reside in the same directory or as a local path to provide the greatest flexibility.
You can use an absolute path, although that makes the declaration more brittle, as different systems install system libraries in a variety of paths.

> Note: Not all libraries are easily made into modules. You may have to create additional shim headers to provide the Swift compiler with the references needed to fully compile and link the library.

For more information on the structure of module maps, see the [LLVM](https://llvm.org/) documentation: [Module Map Language](https://clang.llvm.org/docs/Modules.html#module-map-language).

#### Versioning Modules from system libraries

When creating a module map, follow the conventions of system packagers as you name the module with version information.
For example, the Debian package for `python3` is called `python3`.
In Debian, there is not a single package for python; the system packagers designed it to be installed side-by-side with other versions.
Based on that, a recommended name for a module map for `python3` on a Debian system is `CPython3`.

#### System Libraries With Optional Dependencies

<!-- (heckj) I need to verify this is still the case for C libraries with optional dependencies - are distinct packages still needed? -->

To reference a system library with optional dependencies, you need to make another package to represent the optional library.

For example, the library `libarchive` optionally depends on `xz`, which means it can be compiled with `xz` support, but it isn't required. 
To provide a package that uses libarchive with xz, make a `CArchive+CXz` package that depends on `CXz` and provides `CArchive`.


<!--#### Packages That Provide Multiple Libraries-->
<!---->
<!--To use a system package that provides multiple libraries, such as `.so` and `.dylib` files, add all the libraries to the `module.modulemap` file. -->
<!---->
<!--```-->
<!--module CFoo [system] {-->
<!--    header "/usr/local/include/foo/foo.h"-->
<!--    link "foo"-->
<!--    export *-->
<!--}-->
<!---->
<!--module CFooBar [system] {-->
<!--    header "/usr/include/foo/bar.h"-->
<!--    link "foobar"-->
<!--    export *-->
<!--}-->
<!---->
<!--module CFooBaz [system] {-->
<!--    header "/usr/include/foo/baz.h"-->
<!--    link "foobaz"-->
<!--    export *-->
<!--}-->
<!--```-->
<!---->
<!--^^ refine this out into a full example, with code included form the headers to make it possible to follow it - and drop the FOO stuff!-->
<!---->
<!--In the above example `foobar` and `foobaz` link to `foo`. -->
<!--You don’t need to specify this information in the module map because the headers `foo/bar.h` and `foo/baz.h` both include `foo/foo.h`. -->
<!--It is very important however that those headers do include their dependent headers.-->
<!--Otherwise when the modules are imported into Swift the dependent modules are not imported automatically and you will receive link errors. -->
<!--If link errors occur for consumers of your package, the link errors can be especially difficult to debug.-->

## See Also

- <doc:ExampleSystemLibraryPkgConfig>
