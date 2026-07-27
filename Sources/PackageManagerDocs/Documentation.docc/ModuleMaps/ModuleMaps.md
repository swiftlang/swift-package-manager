# Creating Module Maps

Define how C and C++ headers are exposed to Swift for system library targets, precompiled libraries, or C Language targets.

## Overview

Module maps bridge C and C++ libraries with Swift code.
They define how the Clang module system organizes headers so Swift can import them.
When you wrap a C library for use in Swift Package Manager, you create a module map that describes the library's public interface.

Create a module map when you:

- Wrap a C or C++ library for Swift Package Manager.
- Define a system library target that references pre-installed libraries.
- Package a binary library in an artifact bundle.
- Need to control which headers Swift can import.

Swift Package Manager automatically configures the build system when it finds your module map:

- Adds the module map to compiler search paths.
- Configures header include directories.
- Links binary libraries specified in the module map.
- Selects platform-specific variants from artifact bundles.

You don't need to manually configure compiler flags or search paths.

This article shows you how to create module maps for libraries you're wrapping.
For complete syntax details, see <doc:ModuleMapReference>.
To diagnose import failures and compilation errors, see <doc:DebuggingModuleMaps>.

### Create a basic module map

To show how to create a module map, this example starts with a simple module map that exposes a single header.

Create a file named `module.modulemap` in your library's include directory:

```
module MyLibrary {
    header "MyLibrary.h"
    export *
}
```

This module map defines a module named `MyLibrary` that includes one header file.
The `export *` directive makes all symbols from the header available to code that imports the module.

#### Use relative paths for headers

Specify header paths relative to the module map file's location.
If your module map is in `include/module.modulemap`, the header directive `header "MyLibrary.h"` looks for `include/MyLibrary.h`.

Don't use absolute paths or parent directory references (`../`) when referencing headers.
Relative paths ensure your module map works across different systems and build configurations.

#### Match the module name to your artifact

The module name in your module map must match the artifact name in Swift Package Manager.
If your Package.swift defines a binary target named `MyLibrary`, your module map must declare `module MyLibrary`.

When you use the functions exposed in a module map in Swift, you get access to them using `import`.
For the example above, use the following to access the C functions you exposed in the module map:

```swift
import MyLibrary
```

### Create a module map for C++

C++ libraries require an additional directive to enable C++ language support.
Add the `requires cplusplus` directive to your module map:

```
module MyCppLibrary {
    header "MyCppLibrary.h"
    requires cplusplus
    export *
}
```

Without this directive, the compiler treats the header as C code and produces errors when it encounters C++ syntax.

You can require a specific C++ standard version:

```
module ModernCppLibrary {
    header "ModernCppLibrary.h"
    requires cplusplus11
    export *
}
```

Use `cplusplus11` for C++11 or later.
The compiler rejects the module if the build doesn't enable the required C++ standard.

### Organize multiple headers with umbrella headers

When your library has multiple headers, use an umbrella header to include them all.

Create a main header file that includes your other headers:

```c
// MyLibrary.h
#ifndef MYLIBRARY_H
#define MYLIBRARY_H

#include "Core.h"
#include "Utils.h"
#include "Types.h"

#endif
```

Then reference it in your module map with the `umbrella header` directive:

```
module MyLibrary {
    umbrella header "MyLibrary.h"
    export *
}
```

The umbrella header pattern is common for libraries with multiple public headers.
It provides a single include point for all functionality and clearly defines the public API.

### Mark system libraries

<!-- REVIEWER QUESTION - Is this commonly used, or should we leave this to reference content? -->

When wrapping system libraries (libraries that are built in or pre-installed on the system), add the `[system]` attribute:

```
module SystemLib [system] {
    header "systemlib.h"
    link "systemlib"
    export *
}
```

The `[system]` attribute ensures consistent behavior between local builds and client builds.
It affects how Swift imports certain Objective-C types, particularly `NSUInteger`, which maps to `Int` for system modules and `UInt` for non-system modules.

<!-- REVIEWER QUESTION - Is this section relevant outside of Apple exposing internal libraries? -->

### Link binary libraries

<!-- REVIEWER QUESTION - Is this commonly used, or should we leave this to reference content? -->

Use the `link` directive to specify libraries the linker should include:

```
module ZLib [system] {
    header "zlib.h"
    link "z"
    export *
}
```

Swift Package Manager passes this information to the linker automatically.
You specify the library name without the `lib` prefix or file extension.
For example write `"z"` for `libz.a` or `libz.dylib`.

<!-- REVIEWER QUESTION - keep the example that shows dylib or drop it? -->

### Add a module map to a system library target

Create a system library target when you wrap a library that users install separately on their systems.
The common convention for exposing system libraries is to prefix the name of the library with `C`.
This allows you to create a Swift module with the name of the C library that provides a more idiomatic Swift interface. 

#### Create the target directory

Make a directory for your system library target in your package's root:

```bash
mkdir -p SystemLibraries/CSystemLib
```

#### Create the module map file

Add a `module.modulemap` file in the target directory:

```
module CSystemLib [system] {
    header "shim.h"
    link "systemlib"
    export *
}
```

#### Create a shim header

Add a shim header that includes the actual system header:

```c
// shim.h
#include <systemlib.h>
```

The shim header allows the compiler to find the actual header through search paths, avoiding hardcoded absolute paths that break portability.

#### Declare the target

Add a system library target to your Package.swift:

```swift
.systemLibrary(
    name: "CSystemLib",
    pkgConfig: "systemlib",
    providers: [
        .apt(["libsystemlib-dev"]),
        .brew(["systemlib"])
    ]
)
```

Users who build your package need to install the library first.
The package manager uses `pkg-config` to locate the library and configure search paths.

## Topics

- <doc:ModuleMapReference>
- <doc:DebuggingModuleMaps>

