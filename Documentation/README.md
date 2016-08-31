# Swift Package Manager

The Swift Package Manager is a tool for managing distribution of source code, aimed at making it easy to share your code and reuse others’ code. The tool directly addresses the challenges of compiling and linking Swift packages, managing dependencies, versioning, and supporting flexible distribution and collaboration models.

We’ve designed the system to make it really easy to share packages on services like GitHub, but packages are also great for private personal development, sharing code within a team, or at any other granularity.

***

## Table of Contents

* [**Overview**](README.md)
  * [About Packages](#about-packages)
  * [About Modules](#about-modules)
    * [Building Swift Modules](#building-swift-modules)
  * [About Products](#about-products)
  * [About Dependencies](#about-dependencies)
    * [Dependency Hell](#dependency-hell)
* [Usage](Usage.md)
* [Reference](Reference.md)
* [Resources](Resources.md)

---

## About Packages

A package consists of Swift source files and a manifest file. The manifest file, called Package.swift, defines the package’s name and its contents using the PackageDescription module. A package has one or more targets. Each target specifies a product and may declare one or more dependencies.

---

## About Modules

Swift organizes code into _modules_. Each module specifies a namespace and enforces access controls on which parts of that code can be used outside of that module.

A program may have all of its code in a single module, or it may import other modules as _dependencies_. Aside from the handful of system-provided modules, such as Darwin on OS X or GLibc on Linux, most dependencies require code to be downloaded and built in order to be used.

Extracting code that solves a particular problem into a separate module allows for that code to be reused in other situations. For example, a module that provides functionality for making network requests could be shared between a photo sharing app and a program that displays the weather forecast. And if a new module comes along that does a better job, it can be swapped in easily, with minimal change. By embracing modularity, you can focus on the interesting aspects of the problem at hand, rather than getting bogged down solving problems you encounter along the way.

As a rule of thumb: more modules is probably better than fewer modules. The package manager is designed to make creating both packages and apps with multiple modules as easy as possible.

### Building Swift Modules

The Swift Package Manager and its build system needs to understand how to compile your source code. To do this, it uses a convention-based approach which uses the organization of your source code in the file system to determine what you mean, but allows you to fully override and customize these details. A simple example could be:

    foo/Package.swift
    foo/Sources/main.swift

> `Package.swift` is the manifest file that contains metadata about your package. `Package.swift` is documented in a later section.

If you then run the following command in the directory `foo`:

```sh
swift build
```

Swift will build a single executable called `foo`.

To the package manager, everything is a package, hence `Package.swift`. However, this does not mean you have to release your software to the wider world: you can develop your app without ever publishing it in a place where others can see or use. On the other hand, if one day you decide that your project _should_ be  available to a wider audience your sources are already in a form ready to be published.  The package manager is also independent of specific forms of distribution, so you can use it to share code within your personal projects, within your workgroup, team or company, or with the world.

Of course, the package manager is used to build itself, so its own source files are laid out following these conventions as well.

---

## About Products

A target may build either a library or an executable as its product. A library contains a module that can be imported by other Swift code. An executable is a program that can be run by the operating system.

---

## About Dependencies

Modern development is accelerated by the exponential use of external dependencies (for better and worse).  This is great for allowing you to get more done with less time, but adding dependencies to a project has an associated coordination cost.

In addition to downloading and building the source code for a dependency, that dependency's own dependencies must be downloaded and built as well, and so on, until the entire dependency graph is satisfied. To complicate matters further, a dependency may specify version requirements, which may have to be reconciled with the version requirements of other modules with the same dependency.

The role of the package manager is to automate the process of downloading and building all of the dependencies for a project, and minimize the coordination costs associated with code reuse.

Dependencies are specified in your `Package.swift` manifest file.

### Dependency Hell

“Dependency Hell” is the colloquialism for a situation where the graph of dependencies required by a project cannot be met. The end-user is then required to solve the scenario; usually a difficult task:

1. The conflict may be in unfamiliar dependencies (of dependencies) that the user did not explicitly request
2. Due to the nature of development it would be rare for two dependency graphs to be the same. Thus the amount of help other users (often even the package authors) can offer is limited. Internet searches will likely prove fruitless.

A good package manager should be designed from the start to minimize the risk of dependency hell and where this is not possible, to mitigate it and provide tooling so that the end-user can solve the scenario with a minimum of trouble. The [Package Manager Community Proposal](PackageManagerCommunityProposal.md) contains our thoughts on how we intend to iterate with these hells in mind.

The following are some of the most common “dependency hell” scenarios:

* Inappropriate Versioning - A package may specify an inappropriate version for a release. For example, a version is tagged `1.2.3`, but introduces extensive, breaking API changes that should be reflected by a major version bump to `2.0.0`.

* Incompatible Major Version Requirements - A package may have dependencies with incompatible version requirements for the same package. For example, if `Foo` depends on `Baz` at version `~>1.0` and `Bar` depends on `Baz` at version `~>2.0`, then there is no one version of `Baz` that can satisfy both requirements. This situation often arises when a dependency shared by many packages updates to a new major version, and it takes a long time for all of those packages to update their dependency.

* Incompatible Minor or Update Version Requirements - A package may have dependencies that are specified too strictly, such that version requirements are incompatible for different minor or update versions. For example, if `Foo` depends on `Baz` at version `==2.0.1` and `Bar` depends on `Baz` at version `==2.0.2`, once again, there is no one version of `Baz` that can satisfy both requirements. This is often the result of a regression introduced in a patch release of a dependency, which causes a package to lock that dependency to a particular version.

* Namespace Collision - A package may have two or more dependencies that have the same name. For example, a `Person` package depends on an `Addressable` package that defines a protocol for assigning a mailing address to a person, as well as an `Addressable` package that defines a protocol for speaking formally to another person.

* Broken Software - A package may have a dependency with an outstanding bug that is impacting usability, security, or performance. This may simply be a matter of timeliness on the part of the package maintainers, or a disagreement about their expectations for the package.

* Global State Conflict - A package may have two or more dependencies that presume to have exclusive access to the same global state. For example, one package may not be able to accommodate another package writing to a particular file path while reading from that same file path.

*  Package Becomes Unavailable - A package may have a dependency on a package that becomes unavailable. This may be caused by the source URL becoming inaccessible, or maintainers deleting a published version.

