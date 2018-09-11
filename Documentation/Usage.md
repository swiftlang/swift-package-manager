# Usage

## Table of contents

* [Overview](README.md)
* [**Usage**](Usage.md)
  * [Create a package](#create-a-package)
    * [Create a library package](#create-a-library-package)
    * [Create an executable package](#create-an-executable-package)
  * [Define dependencies](#define-dependencies)
  * [Publish a package](#publish-a-package)
  * [Import system libraries](#import-system-libraries)
  * [Packaging legacy code](#packaging-legacy-code)
  * [Handling version-specific logic](#handling-version-specific-logic)
  * [Editable packages](#editable-packages)
  * [Top of tree development](#top-of-tree-development)
  * [Resolved versions (Package.resolved file)](#resolved-versions-packageresolved-file)
  * [Swift tools version](#swift-tools-version)
  * [Testing](#testing)
  * [Running](#running)
  * [Build configurations](#build-configurations)
    * [Debug](#debug)
    * [Release](#release)
  * [Depending on Apple modules](#depending-on-apple-modules)
  * [C language targets](#c-language-targets)
  * [Shell completion scripts](#shell-completion-scripts)
* [PackageDescription API Version 3](PackageDescriptionV3.md)
* [PackageDescription API Version 4](PackageDescriptionV4.md)
* [PackageDescription API Version 4.2](PackageDescriptionV4_2.md)
* [Resources](Resources.md)

---

## Create a package

Simply put: a package is a git repository with semantically versioned tags,
that contains Swift sources and a `Package.swift` manifest file at its root.

### Create a library package

A library package contains code which other packages can use and depend on. To
get started, create a directory and run `swift package init` command:

    $ mkdir MyPackage
    $ cd MyPackage
    $ swift package init # or swift package init --type library
    $ swift build
    $ swift test

This will create the directory structure needed for a library package with a
target and the corresponding test target to write unit tests. A library package
can contain multiple targets as explained in [Target Format
Reference](PackageDescriptionV4.md#target-format-reference).

### Create an executable package

SwiftPM can create native binary which can be executed from command line. To
get started: 

    $ mkdir MyExecutable
    $ cd MyExecutable
    $ swift package init --type executable
    $ swift build
    $ swift run
    Hello, World!

This creates the directory structure needed for executable targets. Any target
can be turned into a executable target if there is a `main.swift` present in
its sources. Complete reference for layout is
[here](PackageDescriptionV4.md#target-format-reference).

## Define dependencies

To depend on a package, define the dependency and the version in manifest of
your package, and add a product from that package as a dependency. For e.g. if
you want to use https://github.com/apple/example-package-playingcard as
a dependency, add the GitHub URL in dependencies of your `Package.swift`:

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

Now you should be able to `import PlayingCard` in the `MyPackage` target.

## Publish a package

To publish a package, create and push a semantic version tag:

    $ git init
    $ git add .
    $ git remote add origin [github-URL]
    $ git commit -m "Initial Commit"
    $ git tag 1.0.0
    $ git push origin master --tags

Now other packages can depend on version 1.0.0 of this package using the github
url.  
Example of a published package:
https://github.com/apple/example-package-fisheryates

## Import system libraries

As of Swift 4.2, the package manager is capable of importing C libraries from the system without requiring a special wrapper package. We’ll import [Cairo](cairographics.org), a popular 2D vector graphics library, as an example. This guide assumes you already know how to include and link a system library in a C or C++ project.

For our example, we’ll create a new package called `example`:

```bash 
$ mkdir example 
$ cd example 
$ swift package init --type executable
```

The `example` folder should look something like this:

```
.
├── Package.swift
├── README.md
└── Sources
    └── example
        └── main.swift
```

Create a module in the `Sources/` directory called `cairo/`, and create two files, `cairo.h` and `module.modulemap`:

```bash
cd Sources 
mkdir cairo 
cd cairo 
touch cairo.h 
touch module.modulemap
```

```
.
├── Package.swift
├── README.md
└── Sources
    ├── cairo
    │   ├── cairo.h
    │   └── module.modulemap
    └── example
        └── main.swift
```

The `module.modulemap` file tells Swift how to import and link the system library. Add the following lines to it:

```
module cairo {
    umbrella header "cairo.h"
    link "cairo"
}
```

The `module cairo` declaration specifies the name of the module as Swift sees it. In this example, we will be able to import the library from Swift code with `import cairo`.
The `umbrella header "cairo.h"` line specifies the path to a C header file to include, in this case, the `cairo.h` file we created.
The `link "cairo"` line specifies the linker flag used to link the system library, roughly equivalent to `-lcairo` in C.

In the `cairo.h` file, add the following line:

```c
#include <cairo.h>
```

This file functions just like a normal C header, where the `<>` brackets tell `clang` to look for the `cairo.h` header installed by your system in the usual locations. While it’s possible to reference the Cairo header directly in the `module.modulemap` file, including it through a local shim prevents you from having to specify an exact path to it. Many popular C libraries also allow (and even require) you to perform some customization at the inclusion site, so the local header file gives you a place to do this.

Next, we have to tell the package manager about the system library module. Go into your `Package.swift` and add a `systemLibrary` target. Don’t forget to specify it as a dependency of your Swift `example` module:

```swift
let package = Package(
    name: "example",
    targets: [
        .systemLibrary(name: "cairo", pkgConfig: "cairo"),
        .target(name: "example", dependencies: ["cairo"])
    ]
)
```

The `pkgConfig:` parameter specifies the name of the system package that the package manager will ask the system `pkg-config` tool about. Without this information, `clang` may not know where to look for the installed Cairo headers. You can see what `pkg-config` will tell the package manager by running the tool directly in the terminal:

```bash
$ pkg-config --cflags cairo
```
```
-I/usr/include/cairo -I/usr/include/glib-2.0 -I/usr/lib/x86_64-linux-gnu/glib-2.0/include 
-I/usr/include/pixman-1 -I/usr/include/freetype2 -I/usr/include/libpng16 
-I/usr/include/freetype2 -I/usr/include/libpng16
```

Unlike Swift targets, the `name:` parameter in a system library target is only used by the package manager; the name of the module as seen by Swift is entirely determined by the `module cairo` declaration in the `module.modulemap` file. You are free to use a different name for the module within the package description:

```swift
let package = Package(
    name: "example",
    targets: [
        // by default the package manager assumes the module lives in a folder of the 
        // same name underneath the `Sources/` directory
        .systemLibrary(name: "Foo", path: "Sources/cairo", pkgConfig: "cairo"),
        .target(name: "example", dependencies: ["Foo"])
    ]
)
```

In our `main.swift` we can import and use the system module like any other module:

```swift
import cairo

let surface:OpaquePointer = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 120, 120)
print(surface)
```

Projects that depend on system libraries can of course, only be built if the system libraries are installed. We can specify package names in the `providers:` parameter of the target, which should cause the package manager display a helpful hint if the user does not have a required library installed on their system. (Note: this does not seem to be working in current versions of the package manager.)

```swift
let package = Package(
    name: "example",
    targets: [
        .systemLibrary(name: "cairo", pkgConfig: "cairo", providers: [.apt(["libcairo2-dev"])]),
        .target(name: "example", dependencies: ["cairo"])
    ]
)
```

Older versions of Swift required system libraries to exist in separate, individual wrapper packages. Such packages contain no code of their own. Although this method is deprecated, you may still often see packages importing system libraries using this method. Here’s an example using [libgit2](https://libgit2.github.com).

Add these lines of code to your `main.swift` in your `example` package:

```swift
import git2

let options:git_repository_init_options = .init()
print(options)
```

To `import` `git2`, the package manager requires that the `libgit2-dev` library has
been installed by a system packager (eg. `apt`, `brew`, `yum`, etc.).  The
following files from the `libgit2` system package are of interest:

```
/usr/lib/x86_64-linux-gnu/libgit2.so
/usr/include/git2.h
```

> Note that the system library may be located elsewhere on your system, such as `/usr/local/` rather than `/usr/`.

Legacy Swift system library module map packages are handled
differently from regular Swift packages.

Leave the `example` directory and create a new directory called `Clibgit`. Initialize it as a package that builds a system module:

```bash
$ cd ..
$ mkdir git2
$ cd git2
$ swift package init --type system-module
```

```
.
├── example
│   ├── Package.swift
│   ├── README.md
│   └── Sources
│       ├── cairo
│       │   ├── cairo.h
│       │   └── module.modulemap
│       └── example
│           └── main.swift
└── git2
    ├── module.modulemap
    ├── Package.swift
    └── README.md
```

> Warning: the package manager may insert an extraneous comma into the `Package.swift` manifest, causing package builds to fail. Delete this comma to fix this error.

```
Fetching ../git2
../git2 @ 1.0.0: error: manifest parse error(s):
/tmp/TemporaryFile.ca2vxD.swift:12:1: error: unexpected ',' separator
)
```

Like a `systemLibrary` target, such a `Package.swift` takes a `pkgConfig` parameter:

```swift
import PackageDescription

let package = Package(name: "git2", pkgConfig: "libgit2")
```

If you don't want to use the `pkgConfig` parameter you can pass the path of a directory containing the library explicitly using the `-Xlinker` and `-L` flags:

```bash
$ swift build -Xlinker -L/usr/lib/x86_64-linux-gnu/
```

If it does not already, edit `module.modulemap` so it consists of the following:

```
module git2 [system] {
    header "/usr/include/git2.h"
    link "git2"
    export *
}
```

Creating a system library package this way requires a git repository tagged with semantic versions:

```bash
$ git init
$ git add .
$ git commit -m "initial commit"
$ git tag 1.0.0
```

The `git2` package then needs to be declared as a dependency of our `example` package:

```swift
let package = Package(
    name: "example",
    dependencies: [.package(url: "../git2", from: "1.0.0")],
    targets: [
        .systemLibrary(name: "cairo", pkgConfig: "cairo", providers: [.apt(["libcairo2-dev"])]),
        .target(name: "example", dependencies: ["cairo"])
    ]
)
```

Type `swift build` in our example app directory to create an executable:

```bash
$ swift build 
```
```
'git2' .build/checkouts/git2-bbb5c2d4: warning: system packages are deprecated; use system library targets instead
Compile Swift Module 'example' (1 sources)
Linking ./.build/x86_64-unknown-linux/debug/example
```
```bash 
$ .build/debug/example
```
```
git_repository_init_options(version: 0, flags: 0, mode: 0, workdir_path: nil, description: nil, template_path: nil, initial_head: nil, origin_url: nil)
```

### Packages that provide multiple libraries

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
happen. If these link errors occur to consumers of a package that consumes your
package the link errors can be especially difficult to debug.


### Cross-platform module maps

Module maps must contain absolute paths, thus they are not cross-platform. We
intend to provide a solution for this in the package manager. Long term we hope
that system libraries and system packagers will provide module maps and thus
this component of the package manager will become redundant.

*Notably* the above steps will not work if you installed JPEG and JasPer with
[Homebrew](http://brew.sh) since the files will be installed to `/usr/local` for
now adapt the paths, but as said, we plan to support basic relocations like
these.


### Module map versioning

Version the module maps semantically. The meaning of semantic version is less
clear here, so use your best judgement. Do not follow the version of the system
library the module map represents, version the module map(s) independently.

Follow the conventions of system packagers; for example, the debian package for
python3 is called python3, as there is not a single package for python and
python is designed to be installed side-by-side. Were you to make a module map
for python3 you should name it `CPython3`.

### System libraries with optional dependencies

At this time you will need to make another module map package to represent
system packages that are built with optional dependencies.

For example, `libarchive` optionally depends on `xz`, which means it can be
compiled with `xz` support, but it is not required. To provide a package that
uses libarchive with xz you must make a `CArchive+CXz` package that depends on
`CXz` and provides `CArchive`.

## Packaging legacy code

You may be working with code that builds both as a package and not. For example,
you may be packaging a project that also builds with Xcode.

In these cases, you can use the build configuration `SWIFT_PACKAGE` to
conditionally compile code for Swift packages.

```swift
#if SWIFT_PACKAGE
import Foundation
#endif
```

## Handling version-specific logic

The package manager is designed to support packages which work with a variety of
Swift project versions, including both the language and the package manager
version.

In most cases, if you want to support multiple Swift versions in a package you
should do so by using the language-specific version checks available in the
source code itself. However, in some circumstances this may become unmanageable;
in particular, when the package manifest itself cannot be written to be Swift
version agnostic (for example, because it optionally adopts new package manager
features not present in older versions).

The package manager has support for a mechanism to allow Swift version-specific
customizations for the both package manifest and the package versions which will
be considered.

### Version-specific tag selection

The tags which define the versions of the package available for clients to use
can _optionally_ be suffixed with a marker in the form of `@swift-3`. When the
package manager is determining the available tags for a repository, _if_
a version-specific marker is available which matches the current tool version,
then it will *only* consider the versions which have the version-specific
marker. Conversely, version-specific tags will be ignored by any non-matching
tool version.

For example, suppose the package `Foo` has the tags `[1.0.0, 1.2.0@swift-3,
1.3.0]`. If version 3.0 of the package manager is evaluating the available
versions for this repository, it will only ever consider version `1.2.0`.
However, version 4.0 would consider only `1.0.0` and `1.3.0`.

This feature is intended for use in the following scenarios:

1. A package wishes to maintain support for Swift 3.0 in older versions, but
   newer versions of the package require Swift 4.0 for the manifest to be
   readable. Since Swift 3.0 will not know to ignore those versions, it would
   fail when performing dependency resolution on the package if no action is
   taken. In this case, the author can re-tag the last versions which supported
   Swift 3.0 appropriately.

2. A package wishes to maintain dual support for Swift 3.0 and Swift 4.0 at the
   same version numbers, but this requires substantial differences in the code.
   In this case, the author can maintain parallel tag sets for both versions.

It is *not* expected the packages would ever use this feature unless absolutely
necessary to support existing clients. In particular, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift
version.

The package manager supports looking for any of the following marked tags, in
order of preference:

1. `MAJOR.MINOR.PATCH` (e.g., `1.2.0@swift-3.1.2`)
2. `MAJOR.MINOR` (e.g., `1.2.0@swift-3.1`)
3. `MAJOR` (e.g., `1.2.0@swift-3`)

### Version-specific manifest selection

The package manager will additionally look for a version-specific marked
manifest version when loading the particular version of a package, by searching
for a manifest in the form of `Package@swift-3.swift`. The set of markers
looked for is the same as for version-specific tag selection.

This feature is intended for use in cases where a package wishes to maintain
compatibility with multiple Swift project versions, but requires a
substantively different manifest file for this to be viable (e.g., due to
changes in the manifest API).

It is *not* expected the packages would ever use this feature unless absolutely
necessary to support existing clients. In particular, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift
version.

## Editable packages

Swift package manager supports editing dependencies, when your work requires
making a change to one of your dependencies (for example, to fix a bug, or add
a new API). The package manager moves the dependency into a location under
`Packages/` directory where it can be edited.

For the packages which are in the editable state, `swift build` will always use
the exact sources in this directory to build, regardless of its state, git
repository status, tags, or the tag desired by dependency resolution. In other
words, this will _just build_ against the sources that are present. When an
editable package is present, it will be used to satisfy all instances of that
package in the dependency graph. It is possible to edit all, some, or none of
the packages in a dependency graph, without restriction.

Editable packages are best used to do experimentation with dependency code or
create and submit a patch in the dependency owner's repository (upstream).
There are two ways to put a package in editable state:

    $ swift package edit Foo --branch bugFix

This will create a branch called `bugFix` from currently resolved version and
put the dependency Foo in `Packages/` directory. 

    $ swift package edit Foo --revision 969c6a9

This is similar to previous version except that the Package Manager will leave
the dependency at a detached HEAD on the specified revision.

Note: If branch or revision option is not provided, the Package Manager will
checkout the currently resolved version on a detached HEAD.

Once a package is in an editable state, you can navigate to the directory
`Packages/Foo` to make changes, build and then push the changes or open a pull
request to the upstream repository.

You can end editing a package using `unedit` command:

    $ swift package unedit Foo

This will remove the edited dependency from `Packages/` and put the originally
resolved version back. 

This command fails if there are uncommited changes or changes which are not
pushed to the remote repository. If you want to discard these changes and
unedit, you can use the `--force` option:

    $ swift package unedit Foo --force


## Top of tree development

This feature allows overriding a dependency with a local checkout on the
filesystem. This checkout is completely unmanaged by the package manager and
will be used as-is. The only requirement is — the package name in the
overridden checkout should not change. This is extremely useful when developing
multiple packages in tandem or when working on packages alongside an
application.

The command to attach (or create) a local checkout is:

    $ swift package edit <package name> --path <path/to/dependency>

For e.g., if `Foo` depends on `Bar` and you have a checkout of `Bar` at
`/workspace/bar`:

    foo$ swift package edit Bar --path /workspace/bar

A checkout of `Bar` will be created if it doesn't exist at the given path. If
checkout a exists, package manager will validate the package name at the given
path and attach to it.

The package manager will also create a symlink in `Packages/` directory to the
checkout path.

Use unedit command to stop using the local checkout:

    $ swift package unedit <package name>
    # Example:
    $ swift package unedit Bar

## Resolved versions (Package.resolved file)

The package manager records the result of dependency resolution in
a `Package.resolved` file in the top-level package, and when this file is
already present in the top-level package it is used when performing dependency
resolution, rather than the package manager finding the latest eligible version
of each package. Running `swift package update` updates all dependencies to the
latest eligible versions and update the `Package.resolved` file accordingly.

Resolved versions will always be recorded by the package manager. Some users may
choose to add the Package.resolved file to their package's .gitignore file. When
this file is checked in, it allows a team to coordinate on what versions of the
dependencies they should use. If this file is gitignored, each user will
separately choose when to get new versions based on when they run the swift
package update command, and new users will start with the latest eligible
version of each dependency. Either way, for a package which is a dependency of
other packages (e.g. a library package), that package's `Package.resolved` file
will not have any effect on its client packages.

The `swift package resolve` command resolves the dependencies, taking into
account the current version restrictions in the `Package.swift` manifest and
`Package.resolved` resolved versions file, and issuing an error if the graph
cannot be resolved. For packages which have previously resolved versions
recorded in the `Package.resolved` file, the resolve command will resolve to
those versions as long as they are still eligible. If the resolved versions file
changes (e.g.  because a teammate pushed a new version of the file) the next
resolve command will update packages to match that file. After a successful
resolve command, the checked out versions of all dependencies and the versions
recorded in the resolved versions file will match. In most cases the resolve
command will perform no changes unless the `Package.swift manifest or
`Package.resolved` file have changed.

Most SwiftPM commands will implicitly invoke the swift package resolve
functionality before running, and will cancel with an error if dependencies
cannot be resolved.

## Swift tools version

The tools version declares the minimum version of the Swift tools required to
use the package, determines what version of the PackageDescription API should
be used in the Package.swift manifest, and determines which Swift language
compatibility version should be used to parse the Package.swift manifest.

When resolving package dependencies, if the version of a dependency that would
normally be chosen specifies a Swift tools version which is greater than the
version in use, that version of the dependency will be considered ineligible
and dependency resolution will continue with evaluating the next-best version.
If no version of a dependency (which otherwise meets the version requirements
from the package dependency graph) supports the version of the Swift tools in
use, a dependency resolution error will result.

### Swift tools version specification

The Swift tools version is specified by a special comment in the first line of
the Package.swift manifest. To specify a tools version, a Package.swift file
must begin with the string `// swift-tools-version:`, followed by a version
number specifier.

The version number specifier follows the syntax defined by semantic versioning
2.0, with an amendment that the patch version component is optional and
considered to be 0 if not specified. The semver syntax allows for an optional
pre-release version component or build version component; those components will
be completely ignored by the package manager currently.  
After the version number specifier, an optional `;` character may be present;
it, and anything else after it until the end of the first line, will be ignored
by this version of the package manager, but is reserved for the use of future
versions of the package manager. 

Some examples:

    // swift-tools-version:3.1
    // swift-tools-version:3.0.2
    // swift-tools-version:4.0

### Tools version commands

The following Swift tools version commands are supported:

* Report tools version of the package:

        $ swift package tools-version

* Set the package's tools version to the version of the tools currently in use:

        $ swift package tools-version --set-current 

* Set the tools version to a given value:

        $ swift package tools-version --set <value> 

## Testing

Use `swift test` tool to run tests of a Swift package. For more information on
the test tool, run `swift test --help`.

## Running

Use `swift run [executable [arguments...]]` tool to run an executable product of a Swift
package. The executable's name is optional when running without arguments and when there
is only one executable product. For more information on the run tool, run
`swift run --help`.

## Build configurations

SwiftPM allows two build configurations: Debug (default) and Release.

### Debug

By default, running `swift build` will build in debug configuration.
Alternatively, you can also use `swift build -c debug`. The build artifacts are
located in directory called `debug` under build folder.  A Swift target is built
with following flags in debug mode:  

* `-Onone`: Compile without any optimization.
* `-g`: Generate debug information.
* `-enable-testing`: Enable Swift compiler's testability feature.

A C language target is build with following flags in debug mode:

* `-O0`: Compile without any optimization.
* `-g`: Generate debug information.

### Release

To build in release mode, type: `swift build -c release`. The build artifacts
are located in directory called `release` under build folder.  A Swift target is
built with following flags in release mode:  

* `-O`: Compile with optimizations.
* `-whole-module-optimization`: Optimize input files (per module) together
  instead of individually.

A C language target is build with following flags in release mode:

* `-O2`: Compile with optimizations.

## Depending on Apple modules

At this time there is no explicit support for depending on UIKit, AppKit, etc,
though importing these modules should work if they are present in the proper
system location. We will add explicit support for system dependencies in the
future. Note that at this time the Package Manager has no support for iOS,
watchOS, or tvOS platforms.

## C language targets

The C language targets are similar to Swift targets except that the C language
libraries should contain a directory named `include` to hold the public headers.  

To allow a Swift target to import a C language target, add a [target
dependency](#targets) in the manifest file. Swift Package Manager will
automatically generate a modulemap for each C language library target for these
3 cases:

* If `include/Foo/Foo.h` exists and `Foo` is the only directory under the
  include directory then `include/Foo/Foo.h` becomes the umbrella header.

* If `include/Foo.h` exists and `include` contains no other subdirectory then
  `include/Foo.h` becomes the umbrella header.

* Otherwise if the `include` directory only contains header files and no other
  subdirectory, it becomes the umbrella directory.

In case of complicated `include` layouts, a custom `module.modulemap` can be
provided inside `include`. SwiftPM will error out if it can not generate
a modulemap w.r.t the above rules.

For executable targets, only one valid C language main file is allowed i.e. it
is invalid to have `main.c` and `main.cpp` in the same target.

## Shell completion scripts

SwiftPM ships with completion scripts for both Bash and ZSH. These files should be generated in order to use them.

### Bash

Use the following commands to install the Bash completions to `~/.swift-package-complete.bash` and automatically load them using your `~/.bash_profile` file.

```bash
swift package completion-tool generate-bash-script > ~/.swift-package-complete.bash
echo -e "source ~/.swift-package-complete.bash\n" >> ~/.bash_profile
source ~/.swift-package-complete.bash
```

Alternatively, add the following commands to your `~/.bash_profile` file to directly load completions:

```bash
# Source Swift completion
if [ -n "`which swift`" ]; then
	eval "`swift package completion-tool generate-bash-script`"
fi
```

### ZSH

Use the following commands to install the ZSH completions to `~/.zsh/_swift`. You can chose a different folder, but the filename should be `_swift`. This will also add `~/.zsh` to your `$fpath` using your `~/.zshrc` file.

```bash
mkdir ~/.zsh
swift package completion-tool generate-zsh-script > ~/.zsh/_swift
echo -e "fpath=(~/.zsh \$fpath)\n" >> ~/.zshrc
compinit
```
