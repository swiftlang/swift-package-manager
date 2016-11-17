# Usage

## Table of Contents

* [Overview](README.md)
* [**Usage**](Usage.md)
  * [Create a Package](#create-a-package)
    * [Create a library package](#create-a-library-package)
    * [Create an executable package](#create-an-executable-package)
  * [Define Dependencies](#define-dependencies)
  * [Publishing a package](#publishing-a-package)
  * [Require System Libraries](#require-system-libraries)
  * [Handling version-specific logic](#version-specific-logic)
  * [Working on Apps and Packages Side-by-Side](#working-on-apps-and-packages-side-by-side-top-of-the-tree-development)
  * [Editable Packages](#editable-packages)
* [Reference](Reference.md)
* [Resources](Resources.md)

---

## Create a Package

Simply put: a package is a git repository with semantically versioned tags, that contains Swift sources and a `Package.swift` manifest file at its root.

### Create a library package

A libary package contains code which other packages can use and depend on. To get started, create a directory and run `swift package init` command:

    $ mkdir MyPackage
    $ cd MyPackage
    $ swift package init # or swift package init --type library
    $ swift build
    $ swift test

This will create the directory structure needed for a library package with a module and the corresponding test module to write unit tests. A library package can contain multiple modules as explained in [Module Format Reference](Reference.md#module-format-reference).

### Create an executable package

SwiftPM can create native binary which can be executed from command line. To get started: 

    $ mkdir MyExecutable
    $ cd MyExecutable
    $ swift package init --type executable
    $ swift build
    $ .build/debug/MyExecutable
    Hello, World!

This creates the directory structure needed for executable modules. Any module can be turned into a executable module if there is a `main.swift` present in its sources. Complete reference for layout is [here](Reference.md#module-format-reference).

## Define Dependencies

All you need to do to depend on a package is define the dependency and the version, in manifest of your package.
For e.g. if you want to use https://github.com/apple/example-package-playingcard as a dependency, add the github URL in dependencies of your `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .Package(url: "https://github.com/apple/example-package-playingcard.git", majorVersion: 3),
    ]
)
```

Now you should be able to `import PlayingCard` anywhere in your package and use the public APIs.

## Publish a package

To publish a package, you just have to initialize a git repository and create a semantic version tag:

    $ git init
    $ git add .
    $ git remote add origin [github-URL]
    $ git commit -m "Initial Commit"
    $ git tag 1.0.0
    $ git push origin master --tags

Now other packages can depend on version 1.0.0 of this package using the github url.  
Example of a published package: https://github.com/apple/example-package-fisheryates

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


## Working on Apps and Packages Side-by-Side (Top of the tree development)

If you are developing an app that consumes a package and you need to work on that package simultaneously then you can use editable packages as a workaround until we have dedicated tooling for it.

Consider you have a package `foo` which depends on `bar`.

```swift
import PackageDescription

let package = Package(
    name: "foo",
    dependencies: [
        .Package(url: "http://url/to/bar", majorVersion: 1),
    ]
)
```

If you want to develop on `bar` as well as `foo`, navigate to `foo` directory and put `bar` in edit mode:

    $ cd foo
    $ swift package edit bar --revision master

Then remove the `bar` directory created in `Packages/` and instead create a symbolic link to the path of `bar` package on your filesystem. This will make sure the package manager uses the sources in your local `bar`, and does not try and resolve `bar` based on the version specification in the manifest.

    $ cd Packages
    $ rm -r bar
    $ ln -s ln -s /path/to/bar bar

Now go ahead and make changes in `bar`, building `foo` will pick `bar` sources from the local copy of `bar` package. Once you're done editing you can unedit the package:

    $ swift package unedit bar #--force

### Packaging legacy code

You may be working with code that builds both as a package and not. For example, you may be packaging a project that also builds with Xcode.

In these cases, you can use the build configuration `SWIFT_PACKAGE` to conditionally compile code for Swift packages.

```swift
#if SWIFT_PACKAGE
import Foundation
#endif
```

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

### Editable Packages

Swift package manager supports editing dependencies, when your work requires making a change to one of your dependencies (for example, to fix a bug, or add a new API). The package manager moves the dependency into a location under `Packages/` directory where it can be edited.

For the packages which are in the editable state, `swift build` will always use the exact sources in this directory to build, regardless of its state, git repository status, tags, or the tag desired by dependency resolution. In other words, this will _just build_ against the sources that are present. When an editable package is present, it will be used to satisfy all instances of that package in the depencency graph. It is possible to edit all, some, or none of the packages in a dependency graph, without restriction.

Editable packages are best used to do experimentation with dependency code or create and submit a patch in the dependency owner's repository (upstream).  
There are two ways to put a package in editable state:

    $ swift package edit Foo --branch bugFix

This will create a branch called `bugFix` from currently resolved version and put the dependency Foo in `Packages/` directory. 

    $ swift package edit Foo --revision 969c6a9

This is similar to previous version except that the Package Manager will leave the dependency at a detched HEAD on the specified revision.

Note: It is necessary to provide either a branch or revision option. The rationale here is that checking out the currently resolved version would leave the repository on a detached HEAD, which is confusing. Explict options makes the action predictable for user.

Once a package is in an editable state, you can navigate to the directory `Packages/Foo` to make changes, build and then push the changes or open a pull request to the upstream repository.

You can end editing a package using `unedit` command:

    $ swift package unedit Foo

This will remove the edited dependency from `Packages/` and put the originally resolved version back. 

This command fails if there are uncommited changes or changes which are not pushed to the remote repository. If you want to discard these changes and unedit, you can use the `--force` option:

    $ swift package unedit Foo --force

You can read the Swift evolution proposal [here](https://github.com/apple/swift-evolution/blob/master/proposals/0082-swiftpm-package-edit.md).
