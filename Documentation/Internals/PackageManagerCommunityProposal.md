# Swift Package Manager Community Proposal

> **PLEASE NOTE** This document represents the initial proposal for Swift Package Manger, and is provided for historical purposes only. It does not represent the current state or future direction of the project. For current documentation, see the main Swift Package Manager [documentation](README.md).

--- 

Package managers play a significant role in modern language ecosystems, and are as varied as the languages for which they are created. We designed the Swift Package Manager to solve the specific challenges of distributing and managing Swift code, drawing upon ideas we've seen from other systems and improving upon some of their shortcomings.

This initial release is just a starting point, and we invite you to help us to build the best tool possible. To help you get started with the project, we have prepared the following Community Proposal.

> For more information about contributing to Swift and the Swift Package Manager, see the ["Contributing" section of Swift.org](https://swift.org/contributing)

* * *

## Problem Statement

The world is full of fascinating problems waiting to be solved. Software is created to solve some of these problems.

Problems can be recursively decomposed into subproblems, such that any problem can be understood in terms of small, clearly defined tasks. Likewise, code can be organized into individual components, such that each one is responsible for a particular piece of functionality.

No problem should ever have to be solved twice. By extracting code that solves a problem into a separate component, it can be reused in other situations where that problem arises.

However, code reuse has an associated coordination cost. The question is how to minimize that cost.

### Packaging

Code must first be organized in a way that allows for reuse. We define a _package_ to be a grouping of software and associated resources intended for distribution. Packages are identified by a chosen name and may include additional information, such as a list of authors and license information.

### Versioning

As code is developed, it may add new features, remove existing features, or change underlying behavior. To track changes to code over time, a package defines an external _version number_, which corresponds to a particular revision. A version number typically takes the form of `MAJOR.MINOR.PATCH`, which semantically identifies different versions of the same package.

### Dependencies

A package may also specify one or more other packages as _dependencies_, which are required to build the package. When a package declares a dependency, it may constrain the dependent package to a subset of available versions by specifying a set of _requirements_. For example, an `Orchestra` package may specify a `Cello` package as a dependency, with the requirement that the dependency's version is at least `2.0.0`.

### "Dependency Hell"

When a project's packages have requirements that conflict with one another, it creates a situation known colloquially as _"dependency hell"_. This term is used to describe a number of different problems that may arise as new requirements are added to a project, such as inappropriate versioning and incompatible version requirements. Such situations often significantly decrease developer productivity and may prevent the adoption of security fixes and other important changes in updated versions of a dependency.

### Resolution

We believe that the best solution to the problems stated above is a _package manager_ --- a tool that automates the processes of downloading packages, building and linking package modules, and resolving dependencies. Such a tool can take steps to prevent and mitigate certain forms of dependency hell. And for situations that cannot be avoided, it can provide tools to clearly diagnose problems when they arise. The tool should adapt a flexible distribution and collaboration model, rooted in strong conventions and sensible defaults, making it easy to use and well-suited to the needs of developers.

* * *

## Aspects of the Design

Although the Swift Package Manager is still an early work-in-progress, many of our design goals are reflected in the current product. We'd like to specifically call out the following design decisions:

- A Build System for Swift Packages
- Convention-Based Configuration
- Swift Code as Manifest Format
- Explicit Dependency Declaration
- Packages and Modules
- System Library Access with Module Maps
- Semantic Versioning
- Build Environment Isolation
- Source-Based Distribution
- Package Decentralization

Creating an infinitely flexible tool to satisfy every conceivable use case is specifically a _non-goal_ of this project. Instead, we are prioritizing conventions and designs that minimize the friction for distributing Swift code for individuals, and promote the development of a healthy package ecosystem for the community.

### A Build System for Swift Packages

Swift is a compiled language. As such, the Swift Package Manager provides a _build system_ for Swift (`swift build`), which knows how to invoke build tools, like the Swift compiler (`swiftc`), to produce built products from Swift source files.

By design, the Swift Package Manager tightly integrates features across package definitions and the Swift compiler. This allows for the build system to introspect package definitions and use insights from the compiler to manage their configuration.

### Convention-Based Configuration

Rather than requiring that every detail of a package is explicitly configured, the Swift Package Manager establishes a set of conventions about how packages are structured.

A package is simply a directory containing a manifest file, called `Package.swift`. By default, the Swift Package Manager will automatically infer the information it needs to build the package from the layout of the directory itself:

* Any source code files in the root directory or in a top-level `Sources/` or `src/` directory will be automatically included by the build system.
* Any subdirectories of the `Sources/` or `src/` directory will automatically define separate modules.
* If the root directory contains a file called `main.swift`, that file will be used to create an executable with the name of the package.

Taking this approach also has the benefit of allowing this default behavior to evolve and improve over time without requiring any changes to existing packages.

The manifest format will eventually allow for additional configuration, such as any dependencies the package has or any custom build flags to set on individual source files, to accommodate any deviation from conventional expectations.

### Swift Code as Manifest Format

The manifest file, `Package.swift`, defines a `Package` object in Swift code.

Using Swift as a manifest file format allows us to provide a great authoring experience with the tools you already use to work with Swift. However, this could make it difficult for tools to automatically modify the manifest. To mitigate this issue, the manifest file format will eventually be more structured. Although it will remain valid Swift code, the manifest file will be divided into a declarative section, which is easily machine-editable, and an optional section of additional code, which can be ignored by tools.

The manifest file is used to specify any configuration that isn't expressed by convention. Currently, any dependencies a package has are declared in its manifest. In the future, additional configuration, such as custom build flags, will be supported as well. Packages that do not conform to the conventional-based structure will also be able to specify their source files explicitly.
 
Unlike some other build systems, the provided APIs do not interact with the project build environment directly. This allows the Swift build system to evolve over time, without breaking existing packages. Instead, the APIs provided are used to create a declarative model of your package, which is then used by the Swift Package Manager to build the products. By defining a clear, descriptive API for defining packages, we allow developers to communicate their intent while still allowing the Package Manager to evolve.

### Explicit Dependency Declaration

Package dependencies are explicitly declared in the manifest, each specifying a source URL and version requirements.

The source URL corresponds to a Git repository that is accessible to the user building the package. The version requirements correspond to tagged releases in the repository.

When a package is built, the sources of its dependencies are cloned from their respective repository URLs as needed. This process continues with any sub-dependencies, until all of the dependent packages are found. Next, the version requirements of each dependency declaration are resolved. If a dependency has no explicit version requirements, the most recent version is used.

### Packages and Modules

Swift organizes code into _modules_. Each module specifies a namespace and enforces access control on which parts of that code can be used outside of that module.

By default, the module name of each dependency is derived from its source URL. For example, a dependency with the source URL `git://path/to/PlayingCard.git` would be imported in code with `import PlayingCard`. A custom module name for a dependency can be specified in its declaration in the manifest.

### System Library Access with Module Maps

A package may depend on one or more _system module packages_, which allow system libraries written in C to be imported and used in Swift code.

Like any package, a system module package must contain a `Package.swift` file. However, instead of Swift source files, a system module package contains only a `module.modulemap` file, which maps the headers of the system library.

### Semantic Versioning

Swift packages are expected to follow [Semantic Versioning](http://semver.org) (SemVer), a standard for assigning version numbers to software releases.

With SemVer, a version number takes the form `MAJOR.MINOR.PATCH`, where `MAJOR`, `MINOR`, and `PATCH` are non-negative integers. You increment the `MAJOR` version when you make an incompatible API change, the `MINOR` version when you add functionality in a backwards-compatible manner, and the `PATCH` version when you make backwards-compatible bugfixes. When you increment the `MINOR` version, the `PATCH` version is reset to `0`, and when you increment the `MAJOR` version, both the `MINOR` and `PATCH` versions are reset to `0`.

Each release corresponds to a commit in the repository that is tagged with a version number. To see all of the releases of a package, use the `git tag` command with no arguments:

```shell
$ git tag
1.0.0
1.0.1
1.0.2
1.1.0
1.1.1
```

To create a new release, use the `git tag` command passing the version number as the first argument:

```shell
$ git tag 2.0.0
```

By adopting a common versioning convention, package maintainers can more clearly communicate the impact a new version of their code will have, and developers can better understand the changes between versions of a package.

### Build Environment Isolation

A package exists in a self-contained directory containing cloned dependency sources and built products. Each package directory is considered independently from the rest of the file system.

Developing software in isolation, with all dependencies explicitly declared, ensures that even packages with complex requirements can be reliably built and deployed to different environments. Implicit dependencies on the availability of system libraries, with the exception of platform-standard libraries, is strongly discouraged.

### Source-Based Distribution

Packages are distributed and consumed as source code, rather than pre-compiled binaries.

Although it requires additional computational resources, this approach guarantees that developers can adopt new features on platforms they support, without being reliant on vendors to supply updated dependencies. This also has the advantage of allowing tools to do things like automated testing and API analysis of package dependencies.

### Package Decentralization

There is no single centralized index of packages.

A package's metadata and dependencies are specified in its manifest file, which is stored along with the code in its repository. Any package whose source URL is accessible to the current user can be used as a dependency for any other package.

Indexes can be created to aid in the discoverability and curation of Swift packages, without compromising the flexibility and freedom afforded by decentralization. For example, a package could easily switch between a canonical version of a package from an index to a private fork, simply by changing the source URL of the dependency declaration.

* * *

## Future Features

Again, this initial release of the Swift Package Manager is just a starting point. Here is a list of some features we'd like to see in future releases (in no particular order):

- Automated Testing
- Documentation Generation
- Cross-Platform Packages
- Support for Other Languages
- Support for Other Build Systems
- Support for Other Version Control Systems
- Library-Based Architecture
- Standardized Licensing
- Security and Signing
- A Package Index
- Dynamic Libraries
- Enforced Semantic Versioning
- Importing Dependencies by Source URL
- Packaging Resources
- Module Interdependency Determination
- Dependency Resolution
- Resource Management
- Package Flavors
- User-Global Installation

Many of these ideas will eventually become concrete proposals following the [Swift evolution process](https://github.com/apple/swift-evolution). We welcome your input on which features to prioritize or how we might design and implement them. And we're excited to hear about any other ideas for new features.

### Automated Testing

We would like to add support for building and running automated tests for packages.

This should be supported in a standardized way to encourage all packages to provide tests and allow users to easily run the tests for all of a package's dependencies. A package index could use the testing support as a way to validate package submissions to the index. An automated test harness for known packages could also allow the Swift project to validate changes to the Swift compiler, to the Swift Package Manager, or to popular packages with many clients.

The Swift Package Manager may explicitly support [XCTest](https://swift.org/core-libraries/#xctest), from the Swift Core Libraries, as the native testing library.

### Documentation Generation

We would like to establish a standard for documenting packages and provide tools for automatically generating that documentation.

Package maintainers would be encouraged to adequately document their packages, and to provide their documentation in a standardized manner. In addition, a package index could, as part of the submission process, serve generated documentation alongside the package.

### Cross-Platform Packages

We intend to improve the authoring experience for packages that work across multiple platforms (e.g. Linux and OS X).

Currently this is difficult for nontrivial packages, as the current support for system modules often requires a package to depend on a specific module map with platform-specific header paths.

### Support for Other Languages

We would like to add support to the Swift Package Manager for languages other than Swift. This includes support for mixing and matching Swift with other languages.

Specifically, we are most interested in support for C-based languages, because the existing ecosystem of Swift code is heavily reliant on C-based code --- up to and including Objective-C runtime support in Swift itself on Apple platforms.

### Support for Other Build Systems

We are considering supporting hooks for the Swift Package Manager to call out to other build systems, and/or to invoke shell scripts.

Adding this feature would further improve the process of adapting existing libraries for use in Swift code.

We intend to tread cautiously here, as incorporating shell scripts and other external build processes significantly limits the ability of the Swift Package Manager to understand and analyze the build process.

### Support for Other Version Control Systems

We are investigating ways to support version control systems other than Git for the distribution of Swift packages.

Any version control system that allows source code to be addressed by a single URL and has some mechanism for tagged releases should be supported.

### Library-Based Architecture

Currently, the Swift Package Manager is packaged as a command line interface, exposed as a subcommand of the `swift` command. In the future, we would like to make it available as a library with a clearly defined API, so that other tools can more easily be built on top of it.

We would also like to make it possible for an IDE to control Package Manager workflow, such as updating a package's dependencies to the latest versions.  All of the major features of the package manager should be exposed through these APIs, allowing great integration with IDEs like Xcode.

### Standardized Licensing

We would like to provide a mechanism for managing the licenses of dependencies.

The Swift Package Manager could check the license(s) of each package in the dependency tree, and verify that all of them fall within a specified acceptance policy. For example, a package may specify that all of its dependencies must have at least one license specified, or that none of its dependencies are licensed with certain licenses.  Some licenses are known to be incompatible, and the package manager should be able to flag such issues.

### Security and Signing

We would like to provide a built-in security mechanism to sign and verify packages.

This would ensure that packages are not altered after publication. By default, the package manager might reject any remote packages that aren't signed, with an option to override this behavior.

We may additionally incorporate a chain of trust mechanism to validate the source of a package. The Swift Package Manager could be configured to accept only packages signed by a valid signing certificate in the chain of trust of a trusted authority.

### A Package Index

Although the Swift Package Manager is designed to be decentralized, there are certain advantages to centralized package indexes.

Centralized indexes can aid in the discoverability and curation of Swift packages. They can be used to host source code, generate and serve documentation, run automated tests and code analyzers, or visualize changes to APIs over time. For example, by analyzing the interfaces of all submitted packages, an index could allow maintainers to identify the impact of any change to the public API of a package to any registered packages that depend on it.

The index could also act as a naming authority, designating certain packages with canonical names. As a naming authority and software distributor, a centralized index would have a responsibility to ensure the integrity of packages, the security of identities, and the availability of resources, as well as the ability to revoke fraudulent or malicious packages.

We would like to provide a package index in the future, and are investigating possible solutions.

### Dynamic Libraries

We would like to add support for dynamic libraries (and, at least on OS X, framework bundles).

By default, we plan to continue to build packages as static libraries, which incur less runtime overhead than dynamic libraries.

### Enforced Semantic Versioning

We would like to be able to automatically detect changes to the public API of a package as a way to help maintainers select an appropriate semantic version component for each release.

For example, if you change only the implementation of a method, a new `PATCH` version would be allowed, as this change is unlikely to break dependent packages. If a new method is added to the public API, the `MINOR` version should be updated. If you remove a method from the public API or change a public method's signature, the Swift Package Manager would require the next version to update the `MAJOR` version. By doing so, maintainers can avoid inadvertently pushing incompatible release of their packages, and consumers can regularly upgrade packages for security or performance improvements without fear of breaking changes to the API.

Relatedly, we may decide at some point in the future to restrict packages from pulling in dependencies which do not yet define a public API, as indicated by a `1.0.0` release. If this restriction is imposed, it would be possible to override these requirements in your local manifest, thereby allowing development of pre-1.0 packages, without encouraging their proliferation.

#### Importing Dependencies by Source URL

In the future, we may allow remote packages to be imported into source files by passing a source URL to an `import` statement.

This would allow developers to quickly evaluate packages with no setup cost. This would also allow Swift scripts to make use of the packaging ecosystem. The one restriction would be that, in order to publish a package, all `import` statements would have to be resolved to a versioned dependency declared in the manifest.

### Module Interdependency Determination

Currently, if you add `import B` to a source file in module A, you would also need to specify this dependency in the manifest file. If the dependency is not specified, builds will fail because module B must be built before module A. We would like to provide a command that would calculate your module inter-dependencies and alter the machine editable portion of `Package.swift` for you.

It may be possible for the package manager to calculate this every build, but doing so might introduce significant overhead to the build process.

### Dependency Resolution

The Swift Package Manager does not currently provide a mechanism for automatically resolving conflicts in a dependency tree. However, this will be provided in the future.

### Resource Management

OS X provides a resource management solution for libraries in the form of framework bundles. We would like to provide a cross-platform solution for packages that have resources to manage.

This might involve bringing frameworks to Linux. It could instead mean that packages with resources are built as frameworks on OS X, but are built on Linux as libraries with some associated autogenerated glue code for accessing resources.

### Package Flavors

We may wish to consider supporting "flavors" of a package (similar to the condition sets that Xcode calls "Build Configurations").

One type of flavor is along predefined axes, such as platform or architecture.

We could also chose to support user-defined flavors. For example, a graphics library might offer a high-precision version and a fast-math version. User-defined flavors are problematic, as they can easily lead to "dependency hell" situations, such as if two packages of a dependency tree require different flavors of the same package.

### User-Global Installation

In the future, the Swift Package Manager may allow packages to be built and installed to a "user-global" directory located in the current user's home directory, which could be used to build utilities for ad-hoc use.

* * *

If you have any questions about this document, or would like to share any thoughts about existing features, please contact the mailing list for Swift Package Manager development: <swift build-dev@swift.org>

For information about contributing to Swift or the Swift Package Manager, check out ["Contributing to Swift" on Swift.org](https://swift.org/contributing).

If you want to discuss new or planned features, see the [Swift evolution process](https://swift.org/contributing#participating-in-the-swift-evolution-process).
