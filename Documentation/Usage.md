# Usage

## Table of Contents

* [Overview](README.md)
* [**Usage**](Usage.md)
  * [Create a Module](#create-a-module)
  * [Create a Library](#create-a-library)
  * [Define Dependencies](#define-dependencies)
  * [Require System Libraries](#require-system-libraries)
  * [Build an Executable](#build-an-executable)
  * [Create a Package](#create-a-package)
  * [Distribute a Package](#distribute-a-package)
  * [Handling version-specific logic](#version-specific-logic)
* [Reference](Reference.md)
* [Resources](Resources.md)

---

## Create a Module

*Content to come.*

---

## Create a Library

*Content to come.*

---

## Define Dependencies

*Content to come.*

---

## Require System Libraries

You can link against system libraries using the package manager. To do so, there needs to be a special package for each system library that contains a module map for that library. Such a wrapper package does not contain any code of its own.

Let's see an example of using [libgit2](https://libgit2.github.com) from an executable.

First, create a directory called `example`, and initialize it as a package that builds an executable:

    $ mkdir example
    $ cd example
    example$ swift package init --type executable

Edit the `Sources/main.swift` so it consists of this code:

```swift
import Clibgit

let options = git_repository_init_options()
print(options)
```

To `import Clibgit`, the package manager requires
that the libgit2 library has been installed by a system packager (eg. `apt`, `brew`, `yum`, etc.).
The following files from the libgit2 system-package are of interest:

    /usr/local/lib/libgit2.dylib      # .so on Linux
    /usr/local/include/git2.h

Swift packages that provide module maps for system libraries are handled differently from regular Swift packages.

Note that the system library may be located elsewhere on your system, such as `/usr/` rather than `/usr/local/`.

Create a directory called `Clibgit` next to the `example` directory and initialize it as a package
that builds a system module:

    example$ cd ..
    $ mkdir Clibgit
    $ cd Clibgit
    Clibgit$ swift package init --type system-module

This creates `Package.swift` and `module.modulemap` files in the directory.  Edit `Package.swift` and add `pkgConfig` parameter:

```swift
import PackageDescription

let package = Package(
    name: "Clibgit",
    pkgConfig: "libgit2"
)
```

The `pkgConfig` parameter helps SwiftPM in figuring out the include and library search paths for the system library.  
Note: If you don't want to use pkgConfig paramater you can pass the path to directory containing libary using commandline when building your app:

    example$ swift build -Xlinker -L/usr/local/lib/

Edit `module.modulemap` so it consists of the following:

    module Clibgit [system] {
      header "/usr/local/include/git2.h"
      link "git2"
      export *
    }

> The convention we hope the community will adopt is to prefix such modules with `C` and to camelcase the modules
> as per Swift module name conventions. Then the community is free to name another module simply `libgit` which
> contains more “Swifty” function wrappers around the raw C interface.

Packages are Git repositories, tagged with semantic versions, containing a `Package.swift` file at their root.
Initializing the package created a `Package.swift` file, but to make it a usable package we need to initialize
a Git repository with at least one version tag:

    Clibgit$ git init
    Clibgit$ git add .
    Clibgit$ git commit -m "Initial Commit"
    Clibgit$ git tag 1.0.0

Now to use the Clibgit package we must declare our dependency in our example app’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "example",
    dependencies: [
        .Package(url: "../Clibgit", majorVersion: 1)
    ]
)
```

Here we used a relative URL to speed up initial development. If you push your module map package to a public repository you must change the above URL reference so that it is a full, qualified git URL.

Now if we type `swift build` in our example app directory we will create an executable:

    example$ swift build
    …
    example$ .build/debug/example
    git_repository_init_options(version: 0, flags: 0, mode: 0, workdir_path: nil, description: nil, template_path: nil, initial_head: nil, origin_url: nil)
    example$


Let’s see another example of using [IJG’s JPEG library](http://www.ijg.org) from an executable which has some caveats.

Create a directory called `example`, and initialize it as a package that builds an executable:

    $ mkdir example
    $ cd example
    example$ swift package init --type executable

Edit the `Sources/main.swift` so it consists of this code:

```swift
import CJPEG

let jpegData = jpeg_common_struct()
print(jpegData)
```

Install JPEG library using a system packager e.g `$ brew install jpeg`

Create a directory called `CJPEG` next to the `example` directory and initialize it as a package
that builds a system module:

    example$ cd ..
    $ mkdir CJPEG
    $ cd CJPEG
    CJPEG$ swift package init --type system-module

This creates `Package.swift` and `module.modulemap` files in the directory.  Edit `module.modulemap` so it
consists of the following:

    module CJPEG [system] {
        header "shim.h"
        header "/usr/local/include/jpeglib.h"
        link "jpeg"
        export *
    }

Create a `shim.h` file in the same directory and add `#include <stdio.h>` in it.

    $ echo '#include <stdio.h>' > shim.h 

This is because `jpeglib.h` is not a correct module. You can also add `#include <stdio.h>` to the top of jpeglib.h and avoid creating `shim.h` file.

Create a Git repository and tag it:

    CJPEG$ git init
    CJPEG$ git add .
    CJPEG$ git commit -m "Initial Commit"
    CJPEG$ git tag 1.0.0

Now to use the CJPEG package we must declare our dependency in our example app’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "example",
    dependencies: [
        .Package(url: "../CJPEG", majorVersion: 1)
    ]
)
```

Now if we type `swift build` in our example app directory we will create an executable:

    example$ swift build -Xlinker -L/usr/local/lib/
    …
    example$ .build/debug/example
    jpeg_common_struct(err: nil, mem: nil, progress: nil, client_data: nil, is_decompressor: 0, global_state: 0)
    example$

We have to specify path where the libjpeg is present using `-Xlinker` because there is no pkg-config file for it. We plan to provide solution to avoid passing the flag in commandline.

### Packages That Provide Multiple Libraries

Some system packages provide multiple libraries (`.so` and `.dylib` files). In such cases you should add all the libraries to that Swift modulemap package’s `.modulemap` file:

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

`foobar` and `foobaz` link to `foo`; we don’t need to specify this information in the module-map because the headers `foo/bar.h` and `foo/baz.h` both include `foo/foo.h`. It is very important however that those headers do include their dependent headers, otherwise when the modules are imported into Swift the dependent modules will not get imported automatically and link errors will happen. If these link errors occur to consumers of a package that consumes your package the link errors can be especially difficult to debug.


### Cross-platform Module Maps

Module maps must contain absolute paths, thus they are not cross-platform. We intend to provide a solution for this in the package manager. Long term we hope that system libraries and system packagers will provide module maps and thus this component of the package manager will become redundant.

*Notably* the above steps will not work if you installed JPEG and JasPer with [Homebrew](http://brew.sh) since the files will be installed to `/usr/local` for now adapt the paths, but as said, we plan to support basic relocations like these.


### Module Map Versioning

Version the module maps semantically. The meaning of semantic version is less clear here, so use your best judgement. Do not follow the version of the system library the module map represents, version the module map(s) independently.

Follow the conventions of system packagers; for example, the debian package for python3 is called python3, as there is not a single package for python and python is designed to be installed side-by-side. Were you to make a module map for python3 you should name it `CPython3`.


### System Libraries With Optional Dependencies

At this time you will need to make another module map package to represent system packages that are built with optional dependencies.

For example, `libarchive` optionally depends on `xz`, which means it can be compiled with `xz` support, but it is not required. To provide a package that uses libarchive with xz you must make a `CArchive+CXz` package that depends on `CXz` and provides `CArchive`.

---

## Build an Executable

*Content to come.*

---

## Create a Package

Simply put: a package is a git repository with semantically versioned tags, that contains Swift sources and a `Package.swift` manifest file at its root.

### Turning a Library Module into an External Package

If you are building an app with several modules, at some point you may decide to make that module into an external package. Doing this makes that code available as a dependable library that others may use.

Doing so with the package manager is relatively simple:

 1. Create a new repository on GitHub
 2. In a terminal, step into the module directory
 3. `git init`
 4. `git remote add origin [github-URL]`
 5. `git add .`
 6. `git commit --message="…"`
 7. `git tag 1.0.0`
 8. `git push origin master --tags`

Now delete the subdirectory, and amend your `Package.swift` so that its `package` declaration includes:

```swift
let package = Package(
    dependencies: [
        .Package(url: "…", versions: Version(1,0,0)..<Version(2,0,0)),
    ]
)
```

Now type `swift build`.


### Working on Apps and Packages Side-by-Side

If you are developing an app that consumes a package and you need to work on that package simultaneously then you have several options:

 1. Edit the sources that the package manager clones.

	The sources are cloned visibly into `./Packages` to facilitate this.

 2. Alter your `Package.swift` so it refers to a local clone of the package.

	This can be tedious however as you will need to force an update every time you make a change, including updating the version tag. Both options are currently non-ideal since it is easy to commit code that will break for other members of your team, for example, if you change the sources for `Foo` and then commit a change to your app that uses those new changes but you have not committed those changes to `Foo` then you have caused dependency hell for your co-workers.

	It is our intention to provide tooling to prevent such situations, but for now please be aware of the caveats.

### Packaging legacy code

You may be working with code that builds both as a package and not. For example, you may be packaging a project that also builds with Xcode.

In these cases, you can use the build configuration `SWIFT_PACKAGE` to conditionally compile code for Swift packages.

```swift
#if SWIFT_PACKAGE
import Foundation
#endif
```

---

## Distribute a Package

*Content to come.*

## Handling version-specific logic

The package manager is designed to support packages which work with a variety of
Swift project versions, including both the language and the package manager version.

In most cases, if you want to support multiple Swift versions in a package you
should do so by using the language-specific version checks available in the
source code itself. However, in some circumstances this may become
unmanageable; in particular, when the package manifest itself cannot be written
to be Swift version agnostic (for example, because it optionally adopts new
package manager features not present in older versions).

The package manager has support for a mechanism to allow Swift version-specific
customizations for the both package manifest and the package versions which will
be considered.

### Version-specific tag selection

The tags which define the versions of the package available for clients to use
can _optionally_ be suffixed with a marker in the form of `@swift-3`. When the
package manager is determining the available tags for a repository, _if_ a
version-specific marker is available which matches the current tool version,
then it will *only* consider the versions which have the version-specific
marker. Conversely, version-specific tags will be ignored by any non-matching
tool version.

For example, suppose the package `Foo` has the tags
`[1.0.0, 1.2.0@swift-3, 1.3.0]`. If version 3.0 of the package manager is
evaluating the available versions for this repository, it will only ever
consider version `1.2.0`. However, version 4.0 would consider only `1.0.0` and
`1.3.0`.

This feature is intended for use in the following scenarios:

1. A package wishes to maintain support for Swift 3.0 in older versions, but
   newer versions of the package require Swift 4.0 for the manifest to be
   readable. Since Swift 3.0 will not know to ignore those versions, it would
   fail when performing dependency resolution on the package if no action is
   taken. In this case, the author can re-tag the last versions which supported
   Swift 3.0 appropriately.

2. A package wishes to maintain dual support for Swift 3.0 and Swift 4.0 at the
   same version numbers, but this requires substantial differences in the
   code. In this case, the author can maintain parallel tag sets for both
   versions.

It is *not* expected the packages would ever use this feature unless absolutely
necessary to support existing clients. In particular, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift version.

The package manager supports looking for any of the following marked tags, in
order of preference:

1. `MAJOR.MINOR.PATCH` (e.g., `1.2.0@swift-3.1.2`)
2. `MAJOR.MINOR` (e.g., `1.2.0@swift-3.1`)
3. `MAJOR` (e.g., `1.2.0@swift-3`)

### Version-specific manifest selection

The package manager will additionally look for a version-specific marked
manifest version when loading the particular version of a package, by searching
for a manifest in the form of `Package@swift-3.swift`. The set of markers looked
for is the same as for version-specific tag selection.

This feature is intended for use in cases where a package wishes to maintain
compatibility with multiple Swift project versions, but requires a substantively
different manifest file for this to be viable (e.g., due to changes in the
manifest API).

It is *not* expected the packages would ever use this feature unless absolutely
necessary to support existing clients. In particular, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift version.
