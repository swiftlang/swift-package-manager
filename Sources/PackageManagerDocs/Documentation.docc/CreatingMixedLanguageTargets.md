# Creating Mixed Language Targets

Combine Swift and C/C++/Objective-C sources in a single target.

## Overview

Targets in Swift packages which have adopted a tools version of 6.5 or later can leverage Swift's interoperability features to include both Swift and C/C++/Objective-C sources.

### Exporting an Underlying Clang Module

A Swift module can reexport an underlying Clang module with the same name, providing a unified Swift and C API surface to clients through a single import. To create a mixed language target with an underlying Clang module, specify a `publicHeadersPath` for a target which contains Swift source files. By default, SwiftPM will generate a module map for the headers within the `publicHeadersPath` according to the following rules:

- If the public headers directory contains a `module.modulemap` file, it will be used and no modulemap will be generated. When using an explicit `module.modulemap`, it's important to ensure it defines a module whose name matches the name of the target's Swift module.
- If the public headers directory contains a header whose basename matches the module name, a module map will be generated using that header as the umbrella header.
- If the public headers directory contains a directory whose name matches the module name, that directory contains a header whose basename also matches the module name, and the top-level public headers directory is otherwise empty, a module map will be generated using that header as the umbrella header.
- Otherwise, a module map will be generated using the public headers directory as an umbrella directory.

When the target's Swift sources are compiled, it will implicitly import the underlying Clang module, allowing use of its API from the target's Swift sources. The Swift module also reexports the underlying Clang module, allowing any Swift client which imports the target's Swift API will also be able to access the API defined in its underlying Clang module.

### Configuring a Bridging Header

As an alternative to organizing its C/C++/Objective-C interface into a Clang module, a mixed source target may also specify a bridging header. A bridging header allows the Swift sources in the module to import non-modular C/C++/Objective-C code. A target can configure a bridging header by specifying the `bridgingHeader` option in its `swiftSettings` list:

```swift
  .target(
    name: "MyTarget",
    swiftSettings: [
      .bridgingHeader("My-Bridging-Header.h", visibility: .public)
    ]
  )
```

A bridging header's path is specified relative to the target's sources directory, and must not be inside the target's public headers directory. Bridging header visibility may be `.public` or `.internal`, and determines whether API imported via a bridging header may appear in public declarations of the consumer. Regular (library) targets are only allowed to import a bridging header with `.internal` visibility to ensure they present a consistent interface to downstream targets. The existing `interoperabilityMode` setting determines how the bridging header is interpreted.

As a general guideline, package authors should prefer to modularize their C code where possible instead of using a bridging header. However, modularization can be resource intensive when first adopting Swift as part of a large existing C codebase. Bridging headers are a good fit when they're used to facilitate incremental adoption of Swift, and allow packages to quickly get up and running with interoperability as they fully modularize over a longer period of time.

### Exposing the Swift Generated Header to C/C++/Objective-C clients

A Swift module provides a generated header which exposes `@c`/`@objc` annotated API to C/C++/Objective-C code, including sources in the same target:

```c
   #include "MyTarget-Swift.h" // C/C++ clients
   #import "MyTarget-Swift.h"  // Objective-C clients
```

If a mixed language target has an underlying Clang module, SwiftPM will automatically include the Swift generated header in that module when generating a modulemap.
