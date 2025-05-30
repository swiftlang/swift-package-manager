# Bundling resources with a Swift package

Add resource files to your Swift package and access them in your code.

## Overview

If you declare `// swift-tools-version: 5.3` or later in your `Package.swift` file, you can bundle resources alongside your source code in Swift packages.
For example, Swift packages can contain asset catalogs, test fixtures, and so on.

### Add resource files

Package manager treats non-source files found in the target's sources directory as assets, scoped to that target.
For example, any resources for the `MyLibrary` target reside by default in `Sources/MyLibrary`.
To easily distinguish resources from source files, create and use a subfolder for the resources. 
For example, put all resource files into a directory named `Resources`, resulting in all of your resource files residing at `Sources/MyLibrary/Resources`.

### Explicitly declare or exclude resources

To add a resource that the compiler doesn't handle automatically, explicitly declare it as a resource in your package manifest.
If you're building your package with Xcode, it automatically handles a number of kinds of resources.

For example, to include a file `text.txt` as a resource, add the file into `Sources/MyLibrary/Resources`.
Then explicitly declare it as a package resource by adding the name of the file to the list of resources for your target:

```swift
targets: [
    .target(
        name: "MyLibrary",
        resources: [
            .process("Resources/text.txt")]
    ),
]
```

The example above uses  [process(_:localization:)](https://developer.apple.com/documentation/PackageDescription/Resource/process(_:localization:)) to identify the resource.
When you explicitly declare a resource, choose a rule to determine how Swift treats the resource file.
The options include:

- term Process rule: For most use cases, use [process(_:localization:)](https://developer.apple.com/documentation/PackageDescription/Resource/process(_:localization:)). This requests the compiler to apply any processing known for the type of resource, according to the platform you’re building the package for. 
For example, Xcode may optimize image files for a platform that supports such optimizations.
If you apply the process rule to a directory’s path, Xcode applies the rule recursively to all files within the directory. 
If no special processing is available for a resource, the compiler copies the resource as is to the resource bundle’s top-level directory.

- term Copy rule: Some Swift packages may require a resource file to remain untouched or to retain a certain directory structure for resources. 
Use the [copy(_:)](https://developer.apple.com/documentation/PackageDescription/Resource/copy(_:)) function to apply this rule and copy the resource as is to the top level of the resource bundle. 
If you pass a directory path to the copy rule, the compiler retains the directory’s structure.

If a file resides inside a target’s folder and you don’t want it to be a package resource, pass it to the target initializer’s `exclude` parameter.
For example, if you have a file called `instructions.md` in the sources directory, meant only for local use and not intended to be bundled, use `exclude`:

```swift
targets: [
    .target(
        name: "MyLibrary",
        exclude:["instructions.md"]
    ),
]
```

In general, avoid placing files that aren’t resources in a target's source folder. 
If that's not feasible, avoid excluding every file individually, place all files you want to exclude in a directory, and add the directory path to the array of excluded files.
Swift Package Manager warns you about files it doesn't recognize in a target's `Sources` directory.

### Access a resource in code

If a target includes resources, the compiler creates a resource bundle and an internal static extension on [Bundle](https://developer.apple.com/documentation/Foundation/Bundle) to access it for each module. 
Use the extension to locate package resources.
For example, use the following to retrieve the URL to a property list you bundle with your package:

```swift
let settingsURL = Bundle.module.url(forResource: "settings", withExtension: "plist")
```

> Important: Always use `Bundle.module` to access resources.
> A package shouldn’t make assumptions about the exact location of a resource.

If you want to make a package resource available to apps that depend on your Swift package, declare a public constant for it.
For example, use the following to expose a property list file to apps that use your Swift package:

```swift
let settingsURL = Bundle.module.url(forResource: "settings", withExtension: "plist")
```
