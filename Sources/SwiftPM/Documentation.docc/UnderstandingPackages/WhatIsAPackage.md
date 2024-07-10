# What is a Package?

TODO:
- high level
- product
- target
- tests
- dependencies

### Modules

Swift organizes code into _modules_. Each module specifies a namespace and enforces access controls on which parts of that code can be used outside of the module.

A program may have all of its code in a single module, or it may import other modules as _dependencies_. Aside from the handful of system-provided modules, such as Darwin on macOS or Glibc on Linux, most dependencies require code to be downloaded and built in order to be used.

When you use a separate module for code that solves a particular problem, that code can be reused in other situations. For example, a module that provides functionality for making network requests can be shared between a photo sharing app and a weather app. Using modules lets you build on top of other developers' code rather than reimplementing the same functionality yourself.

### Packages

A _package_ consists of Swift source files and a manifest file. The manifest file, called `Package.swift`, defines the package's name and its contents using the `PackageDescription` module.

A package has one or more targets. Each target specifies a product and may declare one or more dependencies.

### Products

A target may build either a library or an executable as its product. A _library_ contains a module that can be imported by other Swift code. An _executable_ is a program that can be run by the operating system.

### Dependencies

A target's dependencies are modules that are required by code in the package. A dependency consists of a relative or absolute URL to the source of the package and a set of requirements for the version of the package that can be used. The role of the package manager is to reduce coordination costs by automating the process of downloading and building all of the dependencies for a project. This is a recursive process: A dependency can have its own dependencies, each of which can also have dependencies, forming a dependency graph. The package manager downloads and builds everything that is needed to satisfy the entire dependency graph.
