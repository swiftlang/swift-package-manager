# Bundling resources with a Swift package

Add resource files to your Swift package and access them in your code.

## Overview

If you declare a Swift tools version of 5.3 or later in your package manifest, you can bundle resources with your source code as Swift packages. 
For example, Swift packages can contain asset catalogs, storyboards, and so on.

### Add resource files

Similar to source code, Xcode scopes resources to a target. 
Place resource files into the folder that corresponds with the target they belong to. 
For example, any resources for the MyLibrary target need to reside in `Sources/MyLibrary`.
However, consider using a subfolder for resources to distinguish them from source files. 
For example, put all resource files into a directory named Resources, resulting in all of your resource files residing at `Sources/MyLibrary/Resources`.

To add resources to a Swift package, do any of the following:

- Drag them into the Project navigator in Xcode.
- From the File menu in Xcode, choose Add Files to [packageName].
- Use Finder or the Terminal app.

When you add a resource to your Swift package, Xcode detects common resource types for Apple platforms and treats them as a resource automatically. 
For example, you don’t need to make changes to your package manifest for the following resources:

- Interface Builder files; for example, XIB files and storyboards
- Core Data files; for example, xcdatamodeld files
- Asset catalogs
- .lproj folders you use to provide localized resources

If you add a resource file that Xcode doesn’t treat as a resource by default, you must configure it in your package manifest, as described in the next section.

### Explicitly declare or exclude resources

To add a resource that Xcode can’t handle automatically, explicitly declare it as a resource in your package manifest. 
The following example assumes that text.txt resides in Sources/MyLibrary and you want to include it in the MyLibrary target. 
To explicitly declare it as a package resource, you pass its file name to the target’s initializer in your package manifest:

```swift
targets: [
    .target(
        name: "MyLibrary",
        resources: [
            .process("text.txt")]
    ),
]
```

Note how the example code above uses the [process(_:localization:)](https://developer.apple.com/documentation/PackageDescription/Resource/process(_:localization:)) function. When you explicitly declare a resource, you must choose one of these rules to determine how Xcode treats the resource file:
- term Process rule: For most use cases, use [process(_:localization:)](https://developer.apple.com/documentation/PackageDescription/Resource/process(_:localization:)) to apply this rule and have Xcode process the resource according to the platform you’re building the package for. 
For example, Xcode may optimize image files for a platform that supports such optimizations. If you apply the process rule to a directory’s path, Xcode applies the rule recursively to the directory’s contents. 
If no special processing is available for a resource, Xcode copies the resource to the resource bundle’s top-level directory.

- term Copy rule: Some Swift packages may require a resource file to remain untouched or to retain a certain directory structure for resources. 
Use the [copy(_:)](https://developer.apple.com/documentation/PackageDescription/Resource/copy(_:)) function to apply this rule and have Xcode copy the resource as is to the top level of the resource bundle. 
If you pass a directory path to the copy rule, Xcode retains the directory’s structure.

If a file resides inside a target’s folder and you don’t want it to be a package resource, pass it to the target initializer’s `exclude` parameter. The next example assumes that instructions.md is a Markdown file that contains documentation, resides at `Sources/MyLibrary` and shouldn’t be part of the package’s resource bundle. This code shows how you can exclude the file from the target by adding it to the list of excluded files:

```swift
targets: [
    .target(
        name: "MyLibrary",
        exclude:["instructions.md"]
    ),
]
```

In general, avoid placing files that aren’t resources in a target’s source folder. 
If that’s not feasible, avoid excluding every file individually, place all files you want to exclude in a directory, and add the directory path to the array of excluded files.

### Access a resource in code

When you build your Swift package, Xcode treats each target as a Swift module. 
If a target includes resources, Xcode creates a resource bundle and an internal static extension on [Bundle](https://developer.apple.com/documentation/Foundation/Bundle) to access it for each module. 
Use the extension to locate package resources. 
For example, use the following to retrieve the URL of a property list you bundle with your package:

```swift
let settingsURL = Bundle.module.url(forResource: "settings", withExtension: "plist")
```

> Important: Always use `Bundle.module` when you access resources. 
> A package shouldn’t make assumptions about the exact location of a resource.

If you want to make a package resource available to apps that depend on your Swift package, declare a public constant for it. 
For example, use the following to expose a property list file to apps that use your Swift package:

```swift
let settingsURL = Bundle.module.url(forResource: "settings", withExtension: "plist")
```

<!-- replica from https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package#Add-resource-files -->
