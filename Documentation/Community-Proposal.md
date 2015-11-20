# Community Proposal

The Swift Package Manager is a tool for managing distribution of source code,
aimed at making it easy to share your code and reuse others' code. The tool
directly addresses the challenges of compiling and linking Swift packages,
managing dependencies, versioning, and supporting flexible distribution and
collaboration models.

Package managers are essential to modern language ecosystems, and are as
varied as the languages for which they are built. We would like an elegant
solution for Swift, and have drawn on the best ideas we have seen from other
systems, while fixing or avoiding some of their pitfalls.

This proposal and the initial release is just a starting point. It
demonstrates our current ideas for how to solve these problems, but we invite
you to get involved and help us build the best package manager possible.

* * *

The purpose of this document is to describe our approach and design goals, to
provide context for the current implementation, and to offer direction in the
development of future features. The ideas for future features presented here
will eventually become concrete proposals, with community input, using the
Swift evolution process.

To learn more about how to contribute to the Swift Package Manager,
instructions and guidelines, as well as a link to our mailing list, can be
found in the [README][].

* * *

## What is a Package?

We define a _package_ to be a grouping of software and associated resources
intended for distribution. Along with source code, packages are distinguished
by a name and version number, and can include additional information such as a
list of authors, license information, and documentation. A package may also
specify one or more other packages as _dependencies_, which are required to
build the package.

As a package is developed, it may add new features, remove existing features,
or change underlying behavior. To keep track of this, a package defines an
external _version number_, which corresponds to a particular revision. A
version number typically takes the form of `MAJOR.MINOR.UPDATE`, which
semantically identifies changes between different versions of the same
package.

When a package declares a dependency, it may constrain the dependent package
to a subset of available versions by specifying a set of _requirements_. For
example, a package `Foo` may specify the `Bar` package as a dependency, with
the requirement that its version is at least `2.0.0`.

## What is a Package Manager?

A _package manager_ is a tool that downloads and builds or installs packages.
Although there are a variety of different package managers, they can be
broadly divided into one of two categories:

- **System Package Managers**,
  which are responsible for building and installing software to system directories
  _(for example, [APT][], [Homebrew][], and [yum][])_.
  System packages are generally installed individually from the command line or a GUI.

- **Language Package Managers**,
  which are responsible for building and installing libraries for a particular language
  _(for example, [CPAN][], [npm][], and [RubyGems][])_.
  Language packages are often installed from a project _manifest file_,
  although language packages can be installed like a system package as well.
  For each entry in a manifest file,
  the package manager recursively enumerates all of the dependencies
  and attempts to reconcile the requirements of the entire project
  into a single graph of packages.
  If successful, the package manager then downloads and builds each package accordingly.

The Swift Package Manager is a _language_ package manager for Swift, which
installs to a specified isolated directory structure. It does not install
software to system directories. A system package manager can use the Swift
Package Manager to build code written in Swift, and then install the products
into system directories.

## Aspects of the Design

Although the Package Manager is still an early work-in-progress, many of our
design goals are reflected in the current product.

### A Build System for Swift Packages

Swift is a compiled language. The Swift Package Manager provides a _build
system_ for Swift (hence `swift build`). It knows how to invoke build tools,
like the Swift compiler, to produce built products from your Swift source
files.

The Swift Package Manager follows a convention-based approach to configuration,
removing the burden of manual configuration from package authors and allowing us
to provide an easy-to-use, cross-platform tool for building Swift programs and
libraries.

This design is intended to allow the Package Manager to tightly integrate
features across package definitions, the build system, and the Swift compiler.
For example, we can take feedback from the compiler and use that to
automatically modify or describe the package.

### Deliberate Design

The design choices we have made for the Swift Package Manager limit its
flexibility in certain ways. While some of this flexibility will undoubtedly
be added over time, it is not our intent to make an infinitely flexible tool.
Instead, we are prioritizing conventions and requirements which make package
development low-hassle and easy to learn, allow us to add powerful new
capabilities to the Package Manager that leverage those conventions, and
encourage a healthy ecosystem of shared Swift code. When developing proposals
for new functionality, we ask that the community consider the costs of added
flexibility, and design with ecosystem consequences in mind.

### Convention-Based Configuration Model

By taking a "convention over configuration" approach, Swift packages can be
created and maintained with minimal hassle.

A package is simply a directory containing a manifest file, called
`Package.swift`. By default, the Swift Package Manager will automatically
infer the information it needs to build the package from the layout of the
directory itself, following a set of conventions. The manifest provides a
suitable place for additional configuration, such as dependencies the package
has on other Swift packages, and (in the future) a license for the package, or
custom build flags on individual source files.

Beyond that minimal explicit configuration, the rest of the information needed
to build a the package can usually be inferred from the package's directory
structure:

* Any source code files in the root directory or in a top-level `Sources/` or
 `src/` directory will be automatically included by the build system.
* Any subdirectories of the `Sources/` or `src/` directory will automatically
 define separate modules.
* If the root directory contains a file called `main.swift`, that file will be
  used to create an executable with the name of the package.

> If your package has a non-conventional structure, it will eventually be
> possible to explicitly specify which source files to include in the
> manifest. The intent of this approach is not to limit what is possible, but
> rather to make the common case as easy as possible.

### Swift Manifest

The manifest file, `Package.swift`, defines a `Package` object in Swift code.
This allows us to provide a great authoring experience with the tools you
already use to write Swift, without needing to learn another manifest file
format.

Using Swift as the manifest file format could make it difficult to create
tools that automatically modify the manifest. To mitigate this issue, the file
format will eventually become somewhat more restrictive. While the file will
remain valid Swift, it will be divided into a declarative section which is
easily machine-editable, and an optional section of additional code which can
be ignored by machine-editing tools.

The Swift Package Manager manifest format uses real Swift APIs in order to
describe the contents of a package. Unlike some build systems, we do not
provide APIs that can directly interact with the project build environment;
such APIs can limit the ability of those build systems to evolve over time.
Instead, the APIs provided are used to create a declarative model of your
package, which is then used by the Package Manager to build the package. By
defining a clear, descriptive API for defining packages, we allow developers
to communicate their intent while still allowing the Package Manager to
evolve. This also enables other tools to be developed which make use of the
package data and augment the ecosystem.

### Built in an Isolated Environment

The Swift Package Manager builds and manages self-contained directories that
contain cloned dependency sources and built products. Each package tree is
given its own self-contained directory, which is considered independently of
the rest of the file system.

Developing software in isolation, with all dependencies explicitly declared,
ensures that even packages with complex requirements can be reliably built and
deployed to different environments. Implicit dependencies on the availability
of system libraries, with the exception of platform-standard libraries, is
strongly discouraged.

In the future, the Swift Package Manager may allow packages to be built and
installed to a "user-global" directory located in the current user's home
directory, which could be used to build utilities for ad-hoc use.

### Importing Dependencies

Package dependencies are explicitly declared in the manifest, each specifying
a source URL and version requirements. The source URL corresponds to a Git
repository that is accessible to the user building the package. The version
requirements correspond to tagged releases in the repository.

When a package is built, the sources of its dependencies are cloned from their
respective repository URLs as needed. This process continues with any sub-
dependencies, until all of the dependent packages are found. Next, the version
requirements of each dependency declaration are resolved. If a dependency has
no explicit version requirements, the most recent version is used.

There is currently no dependency resolution mechanism for when a package is
depended upon by more than one package. However, this will be provided in the
future.

By default, the module name of each dependency is derived from its source URL.
For example, a dependency with the source URL `git:///FooBar.git` would be
imported in code with `import FooBar`. A custom module name for a dependency
can be specified in the manifest.

### Decentralized

There is no single centralized index of packages. A package's metadata and
dependencies are specified in its manifest file, which is stored along with
the code in its repository.

We would like to have a package index in the future. Such an index would
supplement the decentralized system that the Package Manager currently uses,
and serve to aid developers in finding high quality packages for their
particular use cases. An index would not replace the ability for a package to
specify dependencies in a decentralized manner when desired. This is important
for when a package author might prefer to depend on a private fork of another
package, rather than one registered in the index.

### Semantic Versioning

Swift packages are expected to follow semantic versioning. [Semantic
Versioning](http://semver.org) (SemVer) is a standard for assigning version
numbers to software releases. By adopting a common versioning convention,
developers can more clearly communicate the impact a new version of their code
will have, and better understand the changes between versions of dependencies.

With SemVer, version number takes the form `MAJOR.MINOR.PATCH`, where `MAJOR`,
`MINOR`, and `PATCH` are non-negative integers. You increment the `MAJOR`
version when you make an incompatible API change, the `MINOR` version when you
add functionality in a backwards-compatible manner, and the `UPDATE` version
when you make backwards-compatible bugfixes. When you increment the `MINOR`
version, the `UPDATE` version is reset to `0`, and when you increment the
`MAJOR` version, both the `MINOR` and `UPDATE` versions are reset to `0`.

As a convention, in the future the Swift Package Manager might restrict packages
from pulling in dependencies which do not yet define a public API, as indicated
by a `1.0.0` release. If this restriction is imposed it would be possible to
override these requirements in your local manifest thus allowing development of
pre-1.0 packages, but not encouraging their proliferation.

Each release corresponds to a commit in the repository that is tagged with a
version number. To see all of the releases of a package, you do `$ git tag`:

```shell
$ git tag
1.0.0
1.0.1
1.0.2
1.1.0
1.1.1
```

To create a new release, you do `$ git tag VERSION`:

```shell
$ git tag 2.0.0
```

Semantic versioning was chosen because it is a common standard which clearly
expresses the information a package author needs to provide to clients of that
package. Correct use of semantic versioning is not always followed even in
those communities which use it as a standard, so in the future we will explore
ways to help enforce correct use of semantic versioning with the Swift Package
Manager.

### Source-based Distribution

The Swift Package Manager is designed to support the distribution and
consumption of source code. By design, it does not include support for binary
packages.

This decision will result in developers more often having source code for
their non-system dependencies. That allows developers to adopt new features in
the platforms they support without needing to wait for the vendors that supply
their dependencies to catch up. We can build the best user experience,
including API analysis tools and automated testing of your dependencies,
around a Swift package ecosystem which uses source code.

### Importing System Libraries

A package can depend on a "System Module Package". Such packages allow the
import of system libraries written in C.

These packages must be git repositories with semantically versioned tags and a
`Package.swift` — just like regular Swift packages. However, they contain a
single `module.modulemap` file instead of other Swift sources.

The module.modulemap describes the headers and libraries in the system
library.

The community could create a GitHub organization that centralizes the home for
system packages, and thus avoid too much duplicated effort and dependency
hell.

## Future Features

The Package Manager as it exists today is just the beginning. We have many
plans and ideas for the future. We welcome the community to contribute to our
plans and to help us make these features a reality.

### Testing Support

We would like to add support for building and running automated tests for a
Swift package. This should be supported in a standardized way to encourage all
packages to provide tests and allow a user to easily run the tests for all of
a package's dependencies.

The Swift Package Manager may explicitly support [XCTest][], from the Swift
Core Libraries, as the native testing library.

In the future, if we provide a package index, we could use the testing support
as a way to validate package submissions to the index. An automated test
harness for known packages could also allow us to validate changes to the
Swift compiler, to the Package Manager, or to popular packages with many
clients.

### Cross-Platform Packages

We intend for it to be easy to author packages which work across multiple
platforms (e.g. Linux and OS X). Currently this is difficult for nontrivial
packages, as our current support for system modules often requires a package
to depend on a specific module map with platform-specific header paths.

### Support for Other Languages

The Swift Package Manager currently only supports pure Swift packages, but we
would like to add support for other languages as well. This would come in the
form of native support for C-based languages, mixed language support, and
support for running other build systems.

#### Support for C-based Languages

It is likely that we will extend the Swift Package Manager to natively support
building the languages supported by the Clang compiler (C, C++, and
Objective-C). This is because the existing ecosystem of Swift code is heavily
reliant on C-based code, up to and including Objective-C runtime support in
Swift itself on Apple platforms.

#### Mixed Language Support

We would like to support building products which contain a mixture of Swift
code and C/C++/Objective-C code. The mechanism for doing so will need to
bridge APIs between Swift and C-based languages.

#### Support for Other Build Systems

We are considering supporting hooks for the Swift Package Manager to call out
to other build systems, and/or to invoke shell scripts. Adding this support
would greatly increase the scope of packages which it will be possible to
support, and may be necessary to allow Swift packages which depend on the
products of other build systems to fully specify their dependencies.

We wish to tread cautiously here, as incorporating shell scripts and other
external build processes significantly limits the ability of the Swift Package
Manager to analyze the build process and to provide some of our planned future
features in a robust way.

### Library-Based Architecture

The Swift Package Manager is currently packaged as a command line tool
(exposed as a subcommand of `swift`). In the future we would like to make it
available as a library with a clearly defined API, so that other tools can
more easily be built on top of it.

This includes adding support for integrating with IDEs that wish to support
the Package Manager. An IDE should be able to work closely with the Package
Manager to incorporate Swift packages into the IDE's build process and
incorporate the resulting products into products built by the IDE. We would
also like to make it possible for an IDE to control Package Manager workflow,
such as updating a package's dependencies to the latest versions.

### Standardized Licensing

We would like the Package Manager to assist in managing the licenses of your
dependencies. This would require packages to specify their license(s) in their
manifests. The Package Manager could then report on the licenses used by a
package's dependency tree, and could allow you to specifically blacklist
certain licenses to prevent you from accidentally using them.

### Standardized Documentation

We would like to establish a standard for package documentation and provide
tools for automatically presenting that documentation. Package maintainers
should be encouraged to adequately document their packages, and to provide
their documentation in a standard manner.

### Security and Signing

We would like to provide a built-in security mechanism to sign and verify
packages, to ensure that packages you consume are not altered after
publication. By default, the package manager might not integrate remote
packages that aren't signed, although you would be able to opt-out of this
behavior.

We may additionally incorporate a chain of trust mechanism to validate the
source of a package. The Package Manager could be configured to accept only
packages signed by a valid signing certificate in the chain of trust of a
trusted authority.

### A Package Index

Providing a centralized package index could aid package discoverability and
enable many useful features. It also poses some challenges. With a fully
decentralized model, the onus of verifying the integrity of packages lies on
the client of those packages. When an index exists, rightly or wrongly it may
be expected to ensure the integrity of the packages it advertises. This could
be expensive or impractical for the index maintainer.

One way an index could provide a measure of integrity is by leveraging an
existing chain of trust. An authority which issues certificates tied to a
verifiable identity could be trusted, and the index could require that all
registered packages in the index be signed by an identity verified by the
authority. This could also allow for a certificate revocation mechanism in
case malware is discovered in a signed package.

In addition to providing a naming authority to allow packages to be referenced
by well-known names, an index could leverage Swift language integration to
provide some innovative features. For example, the index could analyze the
interface usage of all packages and allow a user to query to find all (index-
registered) downstream packages that would be affected by changing or removing
a given method from a package.

An index could also allow us to leverage native testing support to build and
test all registered packages against new platforms, or against language or
compiler changes.

### Static & Dynamic Libraries

While the Package Manager currently supports only static libraries, we would
like to support dynamic libraries as well (and, at least on OS X, framework
bundles). By default, we plan to continue to build packages as static
libraries, which incur less runtime overhead than dynamic libraries.

### Language Integration

By integrating tightly with the Swift compiler, the Swift Package Manager can
implement useful features based on analysis of the package's source code.

#### Enforcing Semantic Versioning

We would like to make the Package Manager automatically detect changes to the
public API of a package and help you update the appropriate semantic version
component. For example, if a you change only the implementation of a method, a
new `PATCH` version would be allowed, as this change is unlikely to break a
consumer of the API. If a new method is added to the public API, the `MINOR`
version should be updated. If you remove a method from the public API or
change a public method's signature, the package manager would require the next
version to update the `MAJOR` version. By doing so, maintainers can avoid
inadvertently pushing incompatible release of their packages, and consumers
can regularly upgrade packages for security or performance improvements
without fear of breaking changes to the API.

#### Importing Dependency URLs

In the future, we may allow remote packages to be imported into source files
by passing a URL to an `import` statement. This would allow developers to
quickly evaluate packages with no setup cost and allow Swift scripting to make
use of the packaging ecosystem. However, in order to publish a package, all
import statements must be resolved to a versioned dependency declared in the
manifest.

#### Automatic Module Interdependency Determination

Currently if you added `import B` to a source file in module A you would also
need to specify this dependency between the targets in your `Package.swift`.
If the dependency is not specified builds will fail because module B must be
built before module A.

We would like to provide a command that would calculate your module inter-
dependencies and alter the machine editable portion of your `Package.swift`
for you.

It may be possible for the package manager to calculate this every build, but
to do so might introduce significant overhead to the build process.

### Resource Management

OS X provides a resource management solution for libraries in the form of
framework bundles. We would like to provide a cross-platform solution for
packages which have resources to manage. This might involve bringing
frameworks to Linux. It could instead mean that packages with resources are
built as frameworks on OS X, but are built on Linux as libraries with some
associated autogenerated glue code for accessing resources.

### Preventing "Dependency Hell"

There are a number of situations, colloquially termed "dependency hell", that
can arise when the requirements or state of multiple of a project’s
dependencies conflict with each other. These situations are often difficult to
resolve, and can slow the adoption of security fixes and other important
updates from a project’s dependencies. To the degree possible we would like to
design the Package Manager to help prevent dependency hell situations. In
situations we can’t prevent, we would like to provide tools to clearly
diagnose what dependency problem a project faces and assist in resolving it.

### Package Flavors

We may wish to consider supporting "flavors" of a package (similar to the
condition sets that Xcode calls "Build Configurations"). One type of flavor is
along predefined axes, such as platform or architecture. We could also chose
to support user-defined flavors; for example, a graphics library might offer a
high-precision version and a fast-math version.

User-defined flavors are problematic, as they can easily lead to "dependency
hell" situations. For example, if two packages in your package dependency tree
require the same graphics library, but one specifies the fast-math version and
the other specifies the high-precision version, it is not clear how to resolve
that conflict.

[README]: https://github.com/apple/swift-package-manager/blob/master/README.md
[Homebrew]: http://brew.sh
[APT]: https://en.wikipedia.org/wiki/Advanced_Packaging_Tool
[yum]: https://en.wikipedia.org/wiki/Yellowdog_Updater,_Modified
[RubyGems]: https://rubygems.org
[npm]: https://www.npmjs.com
[CPAN]: http://www.cpan.org
[XCTest]: https://swift.org/core-libraries/#xctest
