# ``PackageDescription``

Swift package manifest configuration.

## Overview

Swift packages are configured using `Package.swift` manifest files. The manifest file, or package manifest, defines the package's name and its contents using ``Package`` from the `PackageDescription` module. A package has one or more targets, defined using ``Target``. Each target specifies a ``Product`` and may declare one or more dependencies, defined using ``Package/Dependency``.

### About the Swift Tools Version

A `Package.swift` manifest file must begin with the string `// swift-tools-version:` followed by a version number specifier. The following code listing shows a few examples of valid declarations
of the Swift tools version:

    // swift-tools-version:3.0.2
    // swift-tools-version:3.1
    // swift-tools-version:4.0
    // swift-tools-version:5.0
    // swift-tools-version:5.1
    // ...
    // swift-tools-version:5.6

The Swift tools version declares the version of the `PackageDescription` library, the minimum version of the Swift tools and Swift language compatibility version to process the manifest, and the minimum version of the Swift tools that are needed to use the Swift package. Each version of Swift can introduce updates to the `PackageDescription` framework, but the previous API version will continue to be available to packages which declare a prior tools version. This behavior lets you take advantage of new releases of Swift, the Swift tools, and the `PackageDescription` library, without having to update your package's manifest or losing access to existing packages.

## Topics

### Package Definition

- ``Package``
- ``Product``
- ``Package/Dependency``
- ``Target``

### Settings

- ``BuildSettingCondition``
- ``LinkerSetting``
- ``SupportedPlatform``
- ``SwiftSetting``
- ``SwiftVersion``

### C/C++ Settings

- ``CSetting``
- ``CXXSetting``
- ``CLanguageStandard``
- ``CXXLanguageStandard``
