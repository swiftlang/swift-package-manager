# EnableBuildPlugin

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

A package plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package that defines it.

To get access to a plugin defined in another package, add a package dependency on the package that defines the plugin.  This will let the package access any build tool plugins and command plugins from the dependency.

### Making use of a build tool plugin

To make use of a build tool plugin, list its name in each target to which it should apply:

```swift
// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "my-plugin-example",
    dependencies: [
        .package(url: "https://github.com/example/my-plugin-package.git", from: "1.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyExample",
            plugins: [
                .plugin(name: "MyBuildToolPlugin", package: "my-plugin-package"),
            ]
        )
    ]
)
```

This will cause package manager to call the plugin, passing it a simplified version of the package model for the target to which it is being applied.  Any build commands returned by the plugin will be incorporated into the build graph and will run at the appropriate time during the build.
