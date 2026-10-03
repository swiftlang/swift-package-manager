# Testing Manifest and Plugin API changes

To test the ergonomics of package manifest or plugin API changes while making them, the best approach would be to create an example package that exercises the features and live it in VSCode Swift. To do that, you need to create a custom toolchain and link over the build artifacts from the build output of the development workspace. This document describes how to do that on MacOS when using Xcode. Contributions would be appreciated for similar tools for the the other host platforms.

## Set up the workspace

Prepare the three main repos that SwiftPM developers use into the same directory.

```
git clone https://github.com/swiftlang/swift-build
git clone https://github.com/swiftlang/swift-package-manager
git clone https://github.com/swiftlang/sourcekit-lsp
```

In that directory, also create an xcworkspace directory, e.g. `myNewFeature.xcworkspace`. In that directory create a `contents.xcworkspacedata` file with the following contents.

```
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:swift-build">
   </FileRef>
   <FileRef
      location = "group:swift-package-manager">
   </FileRef>
   <FileRef
      location = "group:sourcekit-lsp">
   </FileRef>
</Workspace>
```

Open the xcworkspace file in Xcode. Create a scheme to build the necessary components for the toolchain and add the following targets into the Build section of that scheme:

```
PackageDescription
PackagePlugin
swift-package
swift-build
swift-test
swiftpm-testing-helper
sourcekit-lsp
```

Build the scheme to produce the artifacts and then run the `mk-toolchain` script in this directory from the directory containing the git repos and the xcworkspace file. This script creates a copy of the XcodeDefault.xctoolchain from the currently xcode-selected Xcode. It locates the derived data for the workspace and overwrites the files in the toolchain copy with soft links over to the build artifacts above.

Make sure you recreate the toolchain every time your Xcode updates to ensure you are using the same version of the toolchain and SDK files.

To test this new toolchain, create a new plugin package in a new directory.

```
swift package init --type build-tool-plugin
```

Open VSCode in that directory pointing the TOOLCHAINS environment variable at the name you selected for your xcworkspace.

```
TOOLCHAINS=myNewFeature code .
```

Make sure that VSCode is able to resolve the package. Execute a build on the package and make sure that succeeds. Add some tests and ensure the tests are detected and run. In the Package.swift file and start to add a new target and make sure you get content assist that shows you the different target functions. Do the same for the plugin Swift file by trying content assist on the `context` and `target` parameters of the `createBuildCommands` function.

If all those succeed, you have a working toolchain and an environment with which to test your changes.
