# Adding dependencies to a Swift package

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

To depend on a package, define the dependency and the version in the manifest of
your package, and add a product from that package as a dependency, e.g., if
you want to use https://github.com/apple/example-package-playingcard as
a dependency, add the GitHub URL in the dependencies of `Package.swift`:

<!-- ref: https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package -->

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(url: "https://github.com/apple/example-package-playingcard.git", from: "3.0.4"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: ["PlayingCard"]
        ),
        .testTarget(
            name: "MyPackageTests",
            dependencies: ["MyPackage"]
        ),
    ]
)
```

### Requiring System Libraries

You can link against system libraries using the package manager. To do so, you'll
need to add a special `target` of type `.systemLibrary`, and a `module.modulemap`
for each system library you're using.

Let's see an example of adding [libgit2](https://github.com/libgit2/libgit2) as a
dependency to an executable target.

Create a directory called `example`, and initialize it as a package that
builds an executable:

    $ mkdir example
    $ cd example
    example$ swift package init --type executable

Edit the `Sources/example/main.swift` so it consists of this code:

```swift
import Clibgit

let options = git_repository_init_options()
print(options)
```

To `import Clibgit`, the package manager requires that the libgit2 library has
been installed by a system packager (eg. `apt`, `brew`, `yum`, `nuget`, etc.). The
following files from the libgit2 system-package are of interest:

    /usr/local/lib/libgit2.dylib      # .so on Linux
    /usr/local/include/git2.h

**Note:** the system library may be located elsewhere on your system, such as:
- `/usr/`, or `/opt/homebrew/` if you're using Homebrew on an Apple Silicon Mac.
- `C:\vcpkg\installed\x64-windows\include` on Windows, if you're using `vcpkg`.
On most Unix-like systems, you can use `pkg-config` to lookup where a library is installed:

    example$ pkg-config --cflags libgit2
    -I/usr/local/libgit2/1.6.4/include


**First, let's define the `target` in the package description**:

```swift
// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

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

**Note:** For Windows-only packages `pkgConfig` should be omitted as
`pkg-config` is not expected to be available. If you don't want to use the
`pkgConfig` parameter you can pass the path of a directory containing the
library using the `-L` flag in the command line when building your package
instead.

    example$ swift build -Xlinker -L/usr/local/lib/

Next, create a directory `Sources/Clibgit` in your `example` project, and
add a `module.modulemap` and the header file to it:

    module Clibgit [system] {
      header "git2.h"
      link "git2"
      export *
    }

The header file should look like this:

```c
// git2.h
#pragma once
#include <git2.h>
```

**Note:** Avoid specifying an absolute path  in the `module.modulemap` to `git2.h`
header provided by the library. Doing so will break compatibility of 
your project between machines that may use a different file system layout or
install libraries to different paths.

> The convention we hope the community will adopt is to prefix such modules
> with `C` and to camelcase the modules as per Swift module name conventions.
> Then the community is free to name another module simply `libgit` which
> contains more “Swifty” function wrappers around the raw C interface.

The `example` directory structure should look like this now:

    .
    ├── Package.swift
    └── Sources
        ├── Clibgit
        │   ├── git2.h
        │   └── module.modulemap
        └── main.swift

At this point, your system library target is fully defined, and you can now use
that target as a dependency in other targets in your `Package.swift`, like this:

```swift

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

Now if we type `swift build` in our example app directory we will create an
executable:

    example$ swift build
    …
    example$ .build/debug/example
    git_repository_init_options(version: 0, flags: 0, mode: 0, workdir_path: nil, description: nil, template_path: nil, initial_head: nil, origin_url: nil)
    example$

### Requiring a System Library Without `pkg-config`

Let’s see another example of using [IJG’s JPEG library](http://www.ijg.org)
from an executable, which has some caveats.

Create a directory called `example`, and initialize it as a package that builds
an executable:

    $ mkdir example
    $ cd example
    example$ swift package init --type executable

Edit the `Sources/main.swift` so it consists of this code:

```swift
import CJPEG

let jpegData = jpeg_common_struct()
print(jpegData)
```

Install the JPEG library, on macOS you can use Homebrew package manager: `brew install jpeg`.
`jpeg` is a keg-only formula, meaning it won't be linked to `/usr/local/lib`,
and you'll have to link it manually at build time.

Just like in the previous example, run `mkdir Sources/CJPEG` and add the
following `module.modulemap`:

    module CJPEG [system] {
        header "shim.h"
        header "/usr/local/opt/jpeg/include/jpeglib.h"
        link "jpeg"
        export *
    }

Create a `shim.h` file in the same directory and add `#include <stdio.h>` in
it.

    $ echo '#include <stdio.h>' > shim.h

This is because `jpeglib.h` is not a correct module, that is, it does not contain
the required line `#include <stdio.h>`. Alternatively, you can add `#include <stdio.h>`
to the top of jpeglib.h to avoid creating the `shim.h` file.

Now to use the CJPEG package we must declare our dependency in our example
app’s `Package.swift`:

```swift

import PackageDescription

let package = Package(
    name: "example",
    targets: [
        .executableTarget(
            name: "example",
            dependencies: ["CJPEG"],
            path: "Sources"
            ),
        .systemLibrary(
            name: "CJPEG",
            providers: [
                .brew(["jpeg"])
            ])
    ]
)
```

Now if we type `swift build` in our example app directory we will create an
executable:

    example$ swift build -Xlinker -L/usr/local/jpeg/lib
    …
    example$ .build/debug/example
    jpeg_common_struct(err: nil, mem: nil, progress: nil, client_data: nil, is_decompressor: 0, global_state: 0)
    example$

We have to specify the path where the libjpeg is present using `-Xlinker` because
there is no pkg-config file for it. We plan to provide a solution to avoid passing
the flag in the command line.

### Packages That Provide Multiple Libraries

Some system packages provide multiple libraries (`.so` and `.dylib` files). In
such cases you should add all the libraries to that Swift modulemap package’s
`.modulemap` file:

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

`foobar` and `foobaz` link to `foo`; we don’t need to specify this information
in the module-map because the headers `foo/bar.h` and `foo/baz.h` both include
`foo/foo.h`. It is very important however that those headers do include their
dependent headers, otherwise when the modules are imported into Swift the
dependent modules will not get imported automatically and link errors will
happen. If these link errors occur for consumers of a package that consumes your
package, the link errors can be especially difficult to debug.

### Cross-platform Module Maps

Module maps must contain absolute paths, thus they are not cross-platform. We
intend to provide a solution for this in the package manager. In the long term,
we hope that system libraries and system packagers will provide module maps and
thus this component of the package manager will become redundant.

*Notably* the above steps will not work if you installed JPEG and JasPer with
[Homebrew](http://brew.sh) since the files will be installed to `/usr/local` on
Intel Macs, or /opt/homebrew on Apple silicon Macs. For now adapt the paths,
but as said, we plan to support basic relocations like these.

### Module Map Versioning

Version the module maps semantically. The meaning of semantic version is less
clear here, so use your best judgement. Do not follow the version of the system
library the module map represents; version the module map(s) independently.

Follow the conventions of system packagers; for example, the debian package for
python3 is called python3, as there is not a single package for python and
python is designed to be installed side-by-side. Were you to make a module map
for python3 you should name it `CPython3`.

### System Libraries With Optional Dependencies

At this time you will need to make another module map package to represent
system packages that are built with optional dependencies.

For example, `libarchive` optionally depends on `xz`, which means it can be
compiled with `xz` support, but it is not required. To provide a package that
uses libarchive with xz you must make a `CArchive+CXz` package that depends on
`CXz` and provides `CArchive`.
