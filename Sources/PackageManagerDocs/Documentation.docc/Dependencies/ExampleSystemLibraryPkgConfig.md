# Swift package example that uses system library dependency with pkg-config

Create an Command-line executable package that uses libgit2 as a system library dependency.

## Overview

The following example walks through creating a binary executable that depends on [libgit2](https://github.com/libgit2/libgit2).

### Set up the package

Create a directory called `example`, and initialize it as a package that builds an executable:

```bash
$ mkdir example
$ cd example
example$ swift package init --type executable
```

Edit the `Sources/example/main.swift` so it consists of this code:

```swift
import Clibgit

let options = git_repository_init_options()
print(options)
```

### Referencing libgit2

To `import Clibgit`, the package manager requires that the libgit2 library has been installed by a system packager (for example `apt`, `brew`, `yum`, `nuget`, and so on).

To depend on libgit2, The Swift compiler is interested in the following files:

    /usr/local/lib/libgit2.dylib      # .so on Linux
    /usr/local/include/git2.h

> Note: the system library may be located elsewhere on your system, such as:
> 
> - `/usr/`, or `/opt/homebrew/` if you're using Homebrew on an Apple Silicon Mac.
> - `C:\vcpkg\installed\x64-windows\include` on Windows, if you're using `vcpkg`.

On most Unix-like systems, you can use `pkg-config` to lookup where a library is installed:

```bash
example$ pkg-config --cflags libgit2
-I/opt/homebrew/Cellar/libgit2/1.9.0/include
```

### Add a system library target

Add a `systemLibrary` target to `Package.swift` that uses the `pkgConfig` parameter to look up the location of the library. 

```swift
// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "example",
    targets: [
        // systemLibrary is a special type of build target that wraps a system library
        // in a target that other targets can require as their dependency.
        .systemLibrary(
            name: "Clibgit",
            pkgConfig: "libgit2",
            providers: [
                .brew(["libgit2"]),
                .apt(["libgit2-dev"])
            ]
        )
    ]
)

```

The above example specifies two `providers` that Swift Package Manager can use to install the dependency, if needed.

> Note: For Windows-only packages `pkgConfig` should be omitted as `pkg-config` is not expected to be available. 
> If you don't want to use the `pkgConfig` parameter you can pass the path of a directory containing the
> library using the `-L` flag in the command line when building your package instead.
> 
> ```bash
> % swift build -Xlinker -L/usr/local/lib/
> ```

This example follows the convention of prefixing modules with `C` and using camelcase for the rest of the library, following Swift module name conventions.
This allows another Swift module `libgit` which contains contains more idiotic Swift functions that wrap the underlying C interface.

### Create a module map and local header

Create a directory `Sources/Clibgit` in your `example` project, and add a `module.modulemap` in the directory:
and the header file to it:

```
module Clibgit [system] {
  header "git2.h"
  link "git2"
  export *
}
```

Create the local header file, `git2.h`, that the above module map references: 

```c
// git2.h
#pragma once
#include <git2.h>
```

> Tip: Try to avoid specifying an absolute system path in the module map to the `git2.h` header provided by the library. 
> Doing so will break compatibility of your project between machines that use a different file system layout or install libraries to different paths.

The `example` directory structure should look like this now:

```
.
├── Package.swift
└── Sources
    ├── Clibgit
    │   ├── git2.h
    │   └── module.modulemap
    └── main.swift
```

### Add the system library dependency to the executable target

With the system library target fully defined, you can now use it as a dependency in other targets.

For example, in `Package.swift`:

```swift
// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "example",
    targets: [
        .executableTarget(
            name: "example",
            // example executable requires "Clibgit" target as its dependency.
            // It's a systemLibrary target defined below.
            dependencies: ["Clibgit"],
            path: "Sources"
        ),

        // systemLibrary is a special type of build target that wraps a system library
        // in a target that other targets can require as their dependency.
        .systemLibrary(
            name: "Clibgit",
            pkgConfig: "libgit2",
            providers: [
                .brew(["libgit2"]),
                .apt(["libgit2-dev"])
            ]
        )
    ]
)

```

### Run the example

Now run the command `swift run` in the example directory to create and run the executable:

```bash
% example swift run
Building for debugging...
[1/1] Write swift-version-3E695E30EE234B31.txt
Build of product 'example' complete! (0.10s)
git_repository_init_options(version: 0, flags: 0, mode: 0, workdir_path: nil, description: nil, template_path: nil, initial_head: nil, origin_url: nil)
```
