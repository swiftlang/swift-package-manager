# Enable a build plugin

@Metadata {
    @Available("Swift", introduced: "5.6")
}

Extend the package manager with a build plugin from another package.

## Overview

A package plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package that defines it.

### Add a dependency

To use a plugin defined in another package, add a package dependency on the package that defines the plugin.
For example, to use the [swift-openapi-generator](https://github.com/apple/swift-openapi-generator), add
the following dependency:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        // other dependencies
        .package(url: "https://github.com/apple/swift-openapi-generator",
                 from: "1.0.0"),
    ],
    targets: [
        // targets
    ]
)
```


This plugin can generate models and stubs for clients and servers from an OpenAPI definition file.

### Identify the targets to enable

Add the plugin to each target to which it should apply.
For example, the following example enables the OpenAPI generator plugin on the executable target:

```swift
let package = Package(
    name: "Example",
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator",
                 from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyExample",
            plugins: [
                .plugin(name: "OpenAPIGenerator", 
                        package: "swift-openapi-generator")
            ]
        )
    ]
)
```
When package manager builds the executable target, it calls the plugin and passes it a simplified version of the package model for the target to which it is applied.
Any build commands returned by the plugin are be incorporated into the build graph and run at the appropriate time during the build.
