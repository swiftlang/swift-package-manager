# Introducing Packages

Learn to create and use a Swift package.

## Overview

A package consists of a `Package.swift` manifest file along with source files, resources, and other assets. 
The manifest file, or package manifest, defines the package's name and its contents using the [PackageDescription](https://developer.apple.com/documentation/packagedescription) module.

Each package declares `Products`, a list of what the package produces.
Types of products include libraries, executables, and plugins:

- A library defines one or more modules that can be imported by other code.
- An executable is a program that can be run by the operating system.
- A plugin is executable code that the Swift Package Manager may use to provide additional commands or build capabilities.

A package may declare `Dependencies`, that provide products from other Swift packages.
A dependency may also be defined to a system library or binary (non-source) artifact.

Each product is made up of one or more `Targets`, the basic building block of a Swift package.
Each target specifies an module, may declare one or more dependencies on other targets within the same package and on products vended by the package’s dependencies.
A target may define a library, a test suite, an executable, an macro, a binary file, and so on.

### About Modules

A Swift package organizes code into _modules_, a unit of code distribution.
A module specifies a namespace and enforces access controls on which parts of the code can be used outside of that module.
Each target you define in a Swift package is a module.

When you expose a library from a package, you expose the public API from your targets that make up that library for other packages to use.
When you import a library in Swift, you're importing the modules that make up that library to use from your code, regardless of what language was used to create that module.
A Swift package can also host C, C++, or Objective-C code as modules.
Like Swift, these are also units of code distribution, but unlike Swift you expose the API that by hand-authoring a module-defining file (`module.modulemap`) that references a header or collection of headers with the API to expose.

A program may have all of its code in a single module, or it may import other modules as _dependencies_.
Aside from the handful of system-provided modules, such as Darwin on macOS or Glibc on Linux, most dependencies require code to be downloaded and built in order to be used.

Extracting code that solves a particular problem into a separate module allows for that code to be reused in other situations. 
For example, a module that provides functionality for making network requests could be shared between a photo sharing app and a program that displays the weather forecast. 
And if a new module comes along that does a better job, it can be swapped in easily, with minimal change. 
By embracing modularity, you can focus on the interesting aspects of the problem at hand, rather than getting bogged down solving problems you encounter along the way.

As a rule of thumb: more modules are probably better than fewer modules. 
The package manager is designed to make creating both packages and apps with multiple modules as easy as possible.

### About Dependencies

Modern development is accelerated by the use of external dependencies (for better and worse). 
This is great for allowing you to get more done in less time, but adding dependencies to a project has an associated coordination cost.

In addition to downloading and building the source code for a dependency, that dependency's own dependencies must be downloaded and built as well, and so on, until the entire dependency graph is satisfied. 
To complicate matters further, a dependency may specify version requirements, which may have to be reconciled with the version requirements of other modules with the same dependency.

The role of the package manager is to automate the process of downloading and building all of the dependencies for a project, and minimize the coordination costs associated with code reuse.
A good package manager should be designed from the start to minimize the risk of failing to resolve dependencies, and where this is not possible, to mitigate it and provide tooling so that the user can solve the scenario with a minimum of trouble.
Read <doc:AddingDependencies> for more information on adding dependencies, and <doc:ResolvingPackageVersions> for how the package manager resolves and records dependencies.
