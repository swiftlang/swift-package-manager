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

### Add a system library target

Add a `systemLibrary` target to `Package.swift` that uses the `pkgConfig` parameter to look up the location of the library. 

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "example",
    targets: [
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
> If you can't or don't want to use the `pkgConfig` parameter, pass the path of a directory containing the
> library using the `-L` flag in the command line when building your package instead.
> 
> ```bash
> % swift build -Xlinker -L/usr/local/lib/
> ```

This example follows the convention of prefixing modules with `C` and using camelcase for the rest of the library, following Swift module name conventions.
This allows you to create and use another module more directly named after the library that provides idiomatic Swift wrappers around the underlying C functions.

### Create a module map and local header

Create a directory `Sources/Clibgit` in your `example` project, and add a `module.modulemap` in the directory:

```
module Clibgit [system] {
  header "git2.h"
  link "git2"
  export *
}
```

In the same directory, create the header file, `git2.h`, that the above module map references: 

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
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "example",
    targets: [
        .executableTarget(
            name: "example",
            dependencies: ["Clibgit"],
            path: "Sources"
        ),
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
