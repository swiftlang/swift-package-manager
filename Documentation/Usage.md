# Usage

## Table of Contents

* [Overview](README.md)
* [**Usage**](Usage.md)
  * [Create a Package](#create-a-package)
    * [Create a library package](#create-a-library-package)
    * [Create an executable package](#create-an-executable-package)
  * [Define Dependencies](#define-dependencies)
  * [Publish a package](#publish-a-package)
  * [Require System Libraries](#require-system-libraries)
  * [Packaging legacy code](#packaging-legacy-code)
  * [Handling version-specific logic](#handling-version-specific-logic)
  * [Editable Packages](#editable-packages)
  * [Top of Tree Development](#top-of-tree-development)
  * [Package Pinning](#package-pinning)
  * [Swift Tools Version](#swift-tools-version)
  * [Prefetching Dependencies](#prefetching-dependencies)
  * [Testing](#testing)
  * [Running](#running)
  * [Build Configurations](#build-configurations)
    * [Debug](#debug)
    * [Release](#release)
  * [Depending on Apple Modules](#depending-on-apple-modules)
  * [C language targets](#c-language-targets)
  * [Shell completion scripts](#shell-completion-scripts)
* [PackageDescription API Version 3](PackageDescriptionV3.md)
* [PackageDescription API Version 4](PackageDescriptionV4.md)
* [Resources](Resources.md)

---

## Create a Package

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
Reference](Reference.md#target-format-reference).

### Create an executable package

SwiftPM can create native binary which can be executed from command line. To
get started: 

    $ mkdir MyExecutable
    $ cd MyExecutable
    $ swift package init --type executable
    $ swift build
    $ .build/debug/MyExecutable
    Hello, World!

This creates the directory structure needed for executable targets. Any target
can be turned into a executable target if there is a `main.swift` present in
its sources. Complete reference for layout is
[here](Reference.md#target-format-reference).

## Define Dependencies

All you need to do to depend on a package is define the dependency and the
version, in manifest of your package.  For e.g. if you want to use
https://github.com/apple/example-package-playingcard as a dependency, add the
github URL in dependencies of your `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .Package(url: "https://github.com/apple/example-package-playingcard.git", majorVersion: 3),
    ]
)
```

Now you should be able to `import PlayingCard` anywhere in your package and use
the public APIs.

## Publish a package

To publish a package, you just have to initialize a git repository and create a
semantic version tag:

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

## Require System Libraries

You can link against system libraries using the package manager. To do so,
there needs to be a special package for each system library that contains a
module map for that library. Such a wrapper package does not contain any code
of its own.

Let's see an example of using [libgit2](https://libgit2.github.com) from an
executable.

First, create a directory called `example`, and initialize it as a package that
builds an executable:

    $ mkdir example
    $ cd example
    example$ swift package init --type executable

Edit the `Sources/main.swift` so it consists of this code:

```swift
import Clibgit

let options = git_repository_init_options()
print(options)
```

To `import Clibgit`, the package manager requires that the libgit2 library has
been installed by a system packager (eg. `apt`, `brew`, `yum`, etc.).  The
following files from the libgit2 system-package are of interest:

    /usr/local/lib/libgit2.dylib      # .so on Linux
    /usr/local/include/git2.h

Swift packages that provide module maps for system libraries are handled
differently from regular Swift packages.

Note that the system library may be located elsewhere on your system, such as
`/usr/` rather than `/usr/local/`.

Create a directory called `Clibgit` next to the `example` directory and
initialize it as a package that builds a system module:

    example$ cd ..
    $ mkdir Clibgit
    $ cd Clibgit
    Clibgit$ swift package init --type system-module

This creates `Package.swift` and `module.modulemap` files in the directory.
Edit `Package.swift` and add `pkgConfig` parameter:

```swift
import PackageDescription

let package = Package(
    name: "Clibgit",
    pkgConfig: "libgit2"
)
```

The `pkgConfig` parameter helps SwiftPM in figuring out the include and library
search paths for the system library.  Note: If you don't want to use pkgConfig
paramater you can pass the path to directory containing library using
commandline when building your app:

    example$ swift build -Xlinker -L/usr/local/lib/

Edit `module.modulemap` so it consists of the following:

    module Clibgit [system] {
      header "/usr/local/include/git2.h"
      link "git2"
      export *
    }

> The convention we hope the community will adopt is to prefix such modules
> with `C` and to camelcase the modules as per Swift module name conventions.
> Then the community is free to name another module simply `libgit` which
> contains more “Swifty” function wrappers around the raw C interface.

Packages are Git repositories, tagged with semantic versions, containing a
`Package.swift` file at their root.  Initializing the package created a
`Package.swift` file, but to make it a usable package we need to initialize a
Git repository with at least one version tag:

    Clibgit$ git init
    Clibgit$ git add .
    Clibgit$ git commit -m "Initial Commit"
    Clibgit$ git tag 1.0.0

Now to use the Clibgit package we must declare our dependency in our example
app’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "example",
    dependencies: [
        .Package(url: "../Clibgit", majorVersion: 1)
    ]
)
```

Here we used a relative URL to speed up initial development. If you push your
module map package to a public repository you must change the above URL
reference so that it is a full, qualified git URL.

Now if we type `swift build` in our example app directory we will create an
executable:

    example$ swift build
    …
    example$ .build/debug/example
    git_repository_init_options(version: 0, flags: 0, mode: 0, workdir_path: nil, description: nil, template_path: nil, initial_head: nil, origin_url: nil)
    example$


Let’s see another example of using [IJG’s JPEG library](http://www.ijg.org)
from an executable which has some caveats.

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

Install JPEG library using a system packager e.g `$ brew install jpeg`

Create a directory called `CJPEG` next to the `example` directory and
initialize it as a package that builds a system module:

    example$ cd ..
    $ mkdir CJPEG
    $ cd CJPEG
    CJPEG$ swift package init --type system-module

This creates `Package.swift` and `module.modulemap` files in the directory.
Edit `module.modulemap` so it consists of the following:

    module CJPEG [system] {
        header "shim.h"
        header "/usr/local/include/jpeglib.h"
        link "jpeg"
        export *
    }

Create a `shim.h` file in the same directory and add `#include <stdio.h>` in
it.

    $ echo '#include <stdio.h>' > shim.h 

This is because `jpeglib.h` is not a correct module. You can also add `#include
<stdio.h>` to the top of jpeglib.h and avoid creating `shim.h` file.

Create a Git repository and tag it:

    CJPEG$ git init
    CJPEG$ git add .
    CJPEG$ git commit -m "Initial Commit"
    CJPEG$ git tag 1.0.0

Now to use the CJPEG package we must declare our dependency in our example
app’s `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "example",
    dependencies: [
        .Package(url: "../CJPEG", majorVersion: 1)
    ]
)
```

Now if we type `swift build` in our example app directory we will create an
executable:

    example$ swift build -Xlinker -L/usr/local/lib/
    …
    example$ .build/debug/example
    jpeg_common_struct(err: nil, mem: nil, progress: nil, client_data: nil, is_decompressor: 0, global_state: 0)
    example$

We have to specify path where the libjpeg is present using `-Xlinker` because
there is no pkg-config file for it. We plan to provide solution to avoid
passing the flag in commandline.

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
happen. If these link errors occur to consumers of a package that consumes your
package the link errors can be especially difficult to debug.


### Cross-platform Module Maps

Module maps must contain absolute paths, thus they are not cross-platform. We
intend to provide a solution for this in the package manager. Long term we hope
that system libraries and system packagers will provide module maps and thus
this component of the package manager will become redundant.

*Notably* the above steps will not work if you installed JPEG and JasPer with
[Homebrew](http://brew.sh) since the files will be installed to `/usr/local`
for now adapt the paths, but as said, we plan to support basic relocations like
these.


### Module Map Versioning

Version the module maps semantically. The meaning of semantic version is less
clear here, so use your best judgement. Do not follow the version of the system
library the module map represents, version the module map(s) independently.

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

## Packaging legacy code

You may be working with code that builds both as a package and not. For
example, you may be packaging a project that also builds with Xcode.

In these cases, you can use the build configuration `SWIFT_PACKAGE` to
conditionally compile code for Swift packages.

```swift
#if SWIFT_PACKAGE
import Foundation
#endif
```

## Handling version-specific logic

The package manager is designed to support packages which work with a variety
of Swift project versions, including both the language and the package manager
version.

In most cases, if you want to support multiple Swift versions in a package you
should do so by using the language-specific version checks available in the
source code itself. However, in some circumstances this may become
unmanageable; in particular, when the package manifest itself cannot be written
to be Swift version agnostic (for example, because it optionally adopts new
package manager features not present in older versions).

The package manager has support for a mechanism to allow Swift version-specific
customizations for the both package manifest and the package versions which
will be considered.

### Version-specific tag selection

The tags which define the versions of the package available for clients to use
can _optionally_ be suffixed with a marker in the form of `@swift-3`. When the
package manager is determining the available tags for a repository, _if_ a
version-specific marker is available which matches the current tool version,
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

## Editable Packages

Swift package manager supports editing dependencies, when your work requires
making a change to one of your dependencies (for example, to fix a bug, or add
a new API). The package manager moves the dependency into a location under
`Packages/` directory where it can be edited.

For the packages which are in the editable state, `swift build` will always use
the exact sources in this directory to build, regardless of its state, git
repository status, tags, or the tag desired by dependency resolution. In other
words, this will _just build_ against the sources that are present. When an
editable package is present, it will be used to satisfy all instances of that
package in the depencency graph. It is possible to edit all, some, or none of
the packages in a dependency graph, without restriction.

Editable packages are best used to do experimentation with dependency code or
create and submit a patch in the dependency owner's repository (upstream).
There are two ways to put a package in editable state:

    $ swift package edit Foo --branch bugFix

This will create a branch called `bugFix` from currently resolved version and
put the dependency Foo in `Packages/` directory. 

    $ swift package edit Foo --revision 969c6a9

This is similar to previous version except that the Package Manager will leave
the dependency at a detched HEAD on the specified revision.

Note: It is necessary to provide either a branch or revision option. The
rationale here is that checking out the currently resolved version would leave
the repository on a detached HEAD, which is confusing. Explict options makes
the action predictable for user.

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


## Top of Tree Development

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

## Package Pinning

Swift package manager has package pinning feature, also called _dependency
locking_ in some dependency managers. Pinning refers to the practice of
controlling exactly which specific version of a dependency is selected by the
dependency resolution algorithm, independent from the semantic versioning
specification. Thus, it is a way of instructing the package manager to select a
particular version from among all of the versions of a package which could be
chosen while honoring the dependency constraints. 

The package manager uses a file named `Package.pins`("pins file") to record the
pinning information. The exact file format is unspecified/implementation
defined, however, in practice it is a JSON data file. This file may be checked
into SCM by the user, so that its effects apply to all users of the package.
However, it may also be maintained only locally (e.g., placed in the
`.gitignore` file). We intend to leave it to package authors to decide which
use case is best for their project. We will recommend that it not be checked in
by library authors, at least for released versions, since pins are not
inherited and thus this information may be confusing.

In the presence of a top-level `Package.pins` file, the package manager will
respect the pinned dependencies recorded in the file whenever it needs to do
dependency resolution (e.g., on the initial checkout or when updating).
In the absence of a top-level `Package.pins` file, the package manager will
operate based purely on the requirements specified in the package manifest, but
will then automatically record the choices it makes into a `Package.pins` file
as part of the _automatic pinning_ feature. 

### Automatic Pinning

The package manager has automatic pinning enabled by default (this is
equivalent to `swift package pin --enable-autopin`). The package manager will
automatically record all package dependencies in the pins file. Package project
owners can choose to disable this if they wish to have more fine grained
control over their pinning behavior, for e.g. pin only certain dependencies.

The automatic pinning behavior works as follows:

* When enabled, the package manager will write all dependency versions into the
  pin file after any operation which changes the set of active working
  dependencies (for example, if a new dependency is added).

* A package author can still change the individual pinned versions using the
  package pin commands (explained below), these will simply update the pinned
  state.

* Some commands do not make sense when automatic pinning is enabled; for
  example, it is not possible to `unpin` and attempts to do so will produce an
  error.

Since package pin information is *not* inherited across dependencies, our
recommendation is that packages which are primarily intended to be consumed by
other developers either disable automatic pinning or put the `Package.pins`
file into `.gitignore`, so that users are not confused why they get different
versions of dependencies that are those being used by the library authors while
they develop.

### Pinning Commands (Manual Pinning)

1. Pinning:

        $ swift package pin ( --all | <package-name> [--version <version>] ) [--message <message>]
        
    The `package-name` refers to the name of the package as specified in its
    manifest.
        
    This command pins one or all dependencies. The command which pins a single
    version can optionally take a specific version to pin to, if unspecified
    (or with `--all`) the behavior is to pin to the current package version in
    use. Examples:
        
   * `$ swift package pin --all` - pins all the dependencies. 
   * `$ swift package pin Foo` - pins Foo at current resolved version.  
   * `$ swift package pin Foo --version 1.2.3` - pins `Foo` at 1.2.3. The specified version should be valid and resolvable.  
        
   The `--message` option is an optional argument to document the reason for
   pinning a dependency. This could be helpful for user to later remember why a
   dependency was pinned. Example:
        
        $ swift package pin Foo --message "The patch updates for Foo are really unstable and need screening."

2. Toggle automatic pinning:

        $ swift package pin ( [--enable-autopin] | [--disable-autopin] )

    These will enable or disable automatic pinning for the package (this state
    is recorded in the `Package.pins` file).

3. Unpinning:

        $ swift package unpin [<package-name>]

    This is the counterpart to the pin command, and unpins packages.

    Note: It is an error to attempt to unpin when automatic pinning is enabled.

4. Package update with pinning:

        $ swift package update [--repin]

    The default behavior is to update all unpinned packages to the latest
    possible versions which can be resolved while respecting the existing pins.
    
    The `--repin` argument can be used to lift the version pinning
    restrictions. In this case, the behavior is that all packages are updated,
    and packages which were previously pinned are then repinned to the latest
    resolved versions.
    
    When automatic pinning is enabled, package update act as if `--repin` was
    specified.

## Swift Tools Version

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

### Swift Tools Version Specification

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

Some Examples:

    // swift-tools-version:3.1
    // swift-tools-version:3.0.2
    // swift-tools-version:4.0

### Tools Version Commands

The following Swift tools version commands are supported:

* Report tools version of the package:

        $ swift package tools-version

* Set the package's tools version to the version of the tools currently in use:

        $ swift package tools-version --set-current 

* Set the tools version to a given value:

        $ swift package tools-version --set <value> 

## Prefetching Dependencies

You can pass `--enable-prefetching` option to `swift build`, `swift package`
and `swift test` to enable prefetching of dependencies. That means the missing
dependencies will be cloned in parallel. For e.g.:

```sh
$ swift build --enable-prefetching
```
## Testing

Use `swift test` tool to run tests of a Swift package. For more information on
the test tool, run `swift test --help`.

## Running

Use `swift run [executable [arguments...]]` tool to run an executable product of a Swift
package. The executable's name is optional when running without arguments and when there
is only one executable product. For more information on the run tool, run
`swift run --help`.

## Build Configurations

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

## Depending on Apple Modules

At this time there is no explicit support for depending on UIKit, AppKit, etc,
though importing these modules should work if they are present in the proper
system location. We will add explicit support for system dependencies in the
future. Note that at this time the Package Manager has no support for iOS,
watchOS, or tvOS platforms.

## C language targets

The C language targets are similar to Swift targets except that the C langauge
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
swift package generate-completion-script bash > ~/.swift-package-complete.bash
echo -e "source ~/.swift-package-complete.bash\n" >> ~/.bash_profile
source ~/.swift-package-complete.bash
```

### ZSH

Use the following commands to install the ZSH completions to `~/.zsh/_swift`. You can chose a different folder, but the filename should be `_swift`. This will also add `~/.zsh` to your `$fpath` using your `~/.zshrc` file.

```bash
mkdir ~/.zsh
swift package generate-completion-script zsh > ~/.zsh/_swift
echo -e "fpath=(~/.zsh \$fpath)\n" >> ~/.zshrc
compinit
```
