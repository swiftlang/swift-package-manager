/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2018 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

/// A target, the basic building block of a Swift package.
///
/// Each target contains a set of source files that are compiled into a module or test suite.
/// You can vend targets to other packages by defining products that include the targets.
///
/// A target may depend on other targets within the same package and on products vended by the package's dependencies.
public final class Target {
    
    /// The different types of a target.
    public enum TargetType: String, Encodable {
        /// A target that contains code for the Swift package’s functionality.
        case regular
        /// A target that contains code for an executable's main module.
        case executable
        /// A target that contains tests for the Swift package’s other targets.
        case test
        /// A target that adapts a library on the system to work with Swift packages.
        case system
        /// A target that references a binary artifact.
        case binary
        /// A target that provides a package plugin.
        case plugin
    }
    
    /// The different types of a target's dependency on another entity.
    public enum Dependency {
        case targetItem(name: String, condition: TargetDependencyCondition?)
        case productItem(name: String, package: String?, moduleAliases: [String: String]?, condition: TargetDependencyCondition?)
        case byNameItem(name: String, condition: TargetDependencyCondition?)
    }
    
    /// The name of the target.
    public var name: String
    
    /// The path of the target, relative to the package root.
    ///
    /// If the path is `nil`, the Swift Package Manager looks for a target's source files at predefined search paths
    /// and in a subdirectory with the target's name.
    ///
    /// The predefined search paths are the following directories under the package root:
    ///   - `Sources`, `Source`, `src`, and `srcs` for regular targets
    ///   - `Tests`, `Sources`, `Source`, `src`, and `srcs` for test targets
    ///
    /// For example, the Swift Package Manager looks for source files inside the `[PackageRoot]/Sources/[TargetName]` directory.
    ///
    /// Don't escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
    public var path: String?
    
    /// The URL of a binary target.
    ///
    /// The URL points to a ZIP file that contains an XCFramework at its root.
    /// Binary targets are only available on Apple Platforms.
    @available(_PackageDescription, introduced: 5.3)
    public var url: String? {
        get { _url }
        set { _url = newValue }
    }
    private var _url: String?
    
    /// The source files in this target.
    ///
    /// If this property is `nil`, the Swift Package Manager includes all valid source files in the target's path and treats specified paths as relative to the target’s path.
    ///
    /// A path can be a path to a directory or an individual source file. In case of a directory, the Swift Package Manager searches for valid source files
    /// recursively inside it.
    public var sources: [String]?
    
    /// The explicit list of resource files in the target.
    @available(_PackageDescription, introduced: 5.3)
    public var resources: [Resource]? {
        get { _resources }
        set { _resources = newValue }
    }
    private var _resources: [Resource]?
    
    /// The paths to source and resource files you don’t want to include in the target.
    ///
    /// Excluded paths are relative to the target path.
    /// This property has precedence over the ``sources`` and ``resources`` properties.
    public var exclude: [String]
    
    /// A boolean value that indicates if this is a test target.
    public var isTest: Bool {
        return type == .test
    }
    
    /// The target's dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]
    
    /// The path to the directory containing public headers of a C-family target.
    ///
    /// This path should be relative to the path specified in `path`.
    /// If this is `nil`, the directory is set to `include`.
    public var publicHeadersPath: String?
    
    /// The type of the target.
    public let type: TargetType
    
    /// The `pkgconfig` name to use for a system library target.
    ///
    /// If present, the Swift Package Manager tries for every pkg-config 
    /// name separated by a space to search for the `<name>.pc` file 
    /// to get the additional flags needed for the system target.
    public let pkgConfig: String?
    
    /// The providers array for a system library target.
    public let providers: [SystemPackageProvider]?
    
    /// The capability provided by a package plugin target.
    @available(_PackageDescription, introduced: 5.5)
    public var pluginCapability: PluginCapability? {
        get { return _pluginCapability }
        set { _pluginCapability = newValue }
    }
    private var _pluginCapability: PluginCapability?
    
    /// The different types of capability that a plugin can provide. In this
    /// version of SwiftPM, only build tool and command plugins are supported;
    /// this enum will be extended as new plugin capabilities are added.
    public enum PluginCapability {
        case _buildTool
        @available(_PackageDescription, introduced: 5.6)
        case _command(intent: PluginCommandIntent, permissions: [PluginPermission])
    }
    
    /// The target's C build settings.
    @available(_PackageDescription, introduced: 5)
    public var cSettings: [CSetting]? {
        get { return _cSettings }
        set { _cSettings = newValue }
    }
    private var _cSettings: [CSetting]?
    
    /// The target's C++ build settings.
    @available(_PackageDescription, introduced: 5)
    public var cxxSettings: [CXXSetting]? {
        get { return _cxxSettings }
        set { _cxxSettings = newValue }
    }
    private var _cxxSettings: [CXXSetting]?
    
    /// The target's Swift build settings.
    @available(_PackageDescription, introduced: 5)
    public var swiftSettings: [SwiftSetting]? {
        get { return _swiftSettings }
        set { _swiftSettings = newValue }
    }
    private var _swiftSettings: [SwiftSetting]?
    
    /// The target's linker settings.
    @available(_PackageDescription, introduced: 5)
    public var linkerSettings: [LinkerSetting]? {
        get { return _linkerSettings }
        set { _linkerSettings = newValue }
    }
    private var _linkerSettings: [LinkerSetting]?
    
    /// The checksum for the ZIP file that contains the referenced XCFramework.
    @available(_PackageDescription, introduced: 5.3)
    public var checksum: String? {
        get { _checksum }
        set { _checksum = newValue }
    }
    private var _checksum: String?
    
    /// The usages of package plugins by the target.
    @available(_PackageDescription, introduced: 5.5)
    public var plugins: [PluginUsage]? {
        get { return _pluginUsages }
        set { _pluginUsages = newValue }
    }
    private var _pluginUsages: [PluginUsage]?
    
    public enum PluginUsage {
        case _pluginItem(name: String, package: String?)
    }
    
    /// Construct a target.
    private init(
        name: String,
        dependencies: [Dependency],
        path: String?,
        url: String? = nil,
        exclude: [String],
        sources: [String]?,
        resources: [Resource]? = nil,
        publicHeadersPath: String?,
        type: TargetType,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        pluginCapability: PluginCapability? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        checksum: String? = nil,
        pluginUsages: [PluginUsage]? = nil
    ) {
        self.name = name
        self.dependencies = dependencies
        self.path = path
        self._url = url
        self.publicHeadersPath = publicHeadersPath
        self.sources = sources
        self._resources = resources
        self.exclude = exclude
        self.type = type
        self.pkgConfig = pkgConfig
        self.providers = providers
        self._pluginCapability = pluginCapability
        self._cSettings = cSettings
        self._cxxSettings = cxxSettings
        self._swiftSettings = swiftSettings
        self._linkerSettings = linkerSettings
        self._checksum = checksum
        self._pluginUsages = pluginUsages
        
        switch type {
        case .regular, .executable, .test:
            precondition(
                url == nil &&
                pkgConfig == nil &&
                providers == nil &&
                pluginCapability == nil &&
                checksum == nil
            )
        case .system:
            precondition(
                url == nil &&
                dependencies.isEmpty &&
                exclude.isEmpty &&
                sources == nil &&
                resources == nil &&
                publicHeadersPath == nil &&
                pluginCapability == nil &&
                cSettings == nil &&
                cxxSettings == nil &&
                swiftSettings == nil &&
                linkerSettings == nil &&
                checksum == nil &&
                pluginUsages == nil
            )
        case .binary:
            precondition(
                dependencies.isEmpty &&
                exclude.isEmpty &&
                sources == nil &&
                resources == nil &&
                publicHeadersPath == nil &&
                pkgConfig == nil &&
                providers == nil &&
                pluginCapability == nil &&
                cSettings == nil &&
                cxxSettings == nil &&
                swiftSettings == nil &&
                linkerSettings == nil &&
                pluginUsages == nil
            )
        case .plugin:
            precondition(
                url == nil &&
                resources == nil &&
                publicHeadersPath == nil &&
                pkgConfig == nil &&
                providers == nil &&
                pluginCapability != nil &&
                cSettings == nil &&
                cxxSettings == nil &&
                swiftSettings == nil &&
                linkerSettings == nil &&
                pluginUsages == nil
            )
        }
    }
    
    /// Creates a library or executable target.
    ///
    /// A target can contain either Swift or C-family source files, but not both. The Swift Package Manager
    /// considers a target to be an executable target if its directory contains a `main.swift`, `main.m`, `main.c`,
    /// or `main.cpp` file. The Swift Package Manager considers all other targets to be library targets.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    @available(_PackageDescription, introduced: 4, obsoleted: 5)
    public static func target(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        publicHeadersPath: String? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: publicHeadersPath,
            type: .regular
        )
    }
    
    /// Creates a library or executable target.
    ///
    /// A target can contain either Swift or C-family source files, but not both. The Swift Package Manager
    /// considers a target to be an executable target if its directory contains a `main.swift`, `main.m`, `main.c`,
    /// or `main.cpp` file. The Swift Package Manager considers all other targets to be library targets.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       Paths are relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5, obsoleted: 5.3)
    public static func target(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        publicHeadersPath: String? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: publicHeadersPath,
            type: .regular,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }
    
    /// Creates a regular target.
    ///
    /// A target can contain either Swift or C-family source files, but not both. It contains code that is built as
    /// a regular module that can be included in a library or executable product, but that cannot itself be used as
    /// the main target of an executable product.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.3, obsoleted: 5.5)
    public static func target(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        publicHeadersPath: String? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: publicHeadersPath,
            type: .regular,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }
    
    /// Creates a regular target.
    ///
    /// A target can contain either Swift or C-family source files, but not both. It contains code that is built as
    /// a regular module that can be included in a library or executable product, but that cannot itself be used as
    /// the main target of an executable product.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    ///   - plugins: The plugins used by this target.
    @available(_PackageDescription, introduced: 5.5)
    public static func target(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        publicHeadersPath: String? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        plugins: [PluginUsage]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: publicHeadersPath,
            type: .regular,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings,
            pluginUsages: plugins
        )
    }
    
    /// Creates an executable target.
    ///
    /// An executable target can contain either Swift or C-family source files, but not both. It contains code that
    /// is built as an executable module that can be used as the main target of an executable product. The target
    /// is expected to either have a source file named `main.swift`, `main.m`, `main.c`, or `main.cpp`, or a source
    /// file that contains the `@main` keyword.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.4, obsoleted: 5.5)
    public static func executableTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        publicHeadersPath: String? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: publicHeadersPath,
            type: .executable,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }
    
    /// Creates an executable target.
    ///
    /// An executable target can contain either Swift or C-family source files, but not both. It contains code that
    /// is built as an executable module that can be used as the main target of an executable product. The target
    /// is expected to either have a source file named `main.swift`, `main.m`, `main.c`, or `main.cpp`, or a source
    /// file that contains the `@main` keyword.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    ///   - plugins: The plugins used by this target.
    @available(_PackageDescription, introduced: 5.5)
    public static func executableTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        publicHeadersPath: String? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        plugins: [PluginUsage]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: publicHeadersPath,
            type: .executable,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings,
            pluginUsages: plugins
        )
    }
    
    /// Creates a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    @available(_PackageDescription, introduced: 4, obsoleted: 5)
    public static func testTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: nil,
            type: .test
        )
    }
    
    /// Creates a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5, obsoleted: 5.3)
    public static func testTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: nil,
            type: .test,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }
    
    /// Creates a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.3, obsoleted: 5.5)
    public static func testTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: nil,
            type: .test,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }
    
    /// Creates a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that the Swift Package Manager shouldn't consider to be source or resource files.
    ///       A path is relative to the target's directory.
    ///       This parameter has precedence over the ``sources`` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    ///   - plugins: The plugins used by this target.
    @available(_PackageDescription, introduced: 5.5)
    public static func testTarget(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource]? = nil,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        plugins: [PluginUsage]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: nil,
            type: .test,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings,
            pluginUsages: plugins
        )
    }
    
    /// Creates a system library target.
    ///
    /// Use system library targets to adapt a library installed on the system to work with Swift packages.
    /// Such libraries are generally installed by system package managers (such as Homebrew and apt-get)
    /// and exposed to Swift packages by providing a `modulemap` file along with other metadata such as the library's `pkgConfig` name.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - path: The custom path for the target. By default, the Swift Package Manager requires a target's sources to reside at predefined search paths;
    ///       for example, `[PackageRoot]/Sources/[TargetName]`.
    ///       Don't escape the package root; for example, values like `../Foo` or `/Foo` are invalid.
    ///   - pkgConfig: The name of the `pkg-config` file for this system library.
    ///   - providers: The providers for this system library.
    public static func systemLibrary(
        name: String,
        path: String? = nil,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: [],
            path: path,
            exclude: [],
            sources: nil,
            publicHeadersPath: nil,
            type: .system,
            pkgConfig: pkgConfig,
            providers: providers)
    }
    
    /// Creates a binary target that references a remote artifact.
    ///
    /// A binary target provides the url to a pre-built binary artifact for the target. Currently only supports
    /// artifacts for Apple platforms.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - url: The URL to the binary artifact. This URL must point to an archive file
    ///       that contains a binary artifact in its root directory.
    ///   - checksum: The checksum of the archive file that contains the binary artifact.
    ///
    /// Binary targets are only available on Apple platforms.
    @available(_PackageDescription, introduced: 5.3)
    public static func binaryTarget(
        name: String,
        url: String,
        checksum: String
    ) -> Target {
        return Target(
            name: name,
            dependencies: [],
            path: nil,
            url: url,
            exclude: [],
            sources: nil,
            publicHeadersPath: nil,
            type: .binary,
            checksum: checksum)
    }
    
    /// Creates a binary target that references an artifact on disk.
    ///
    /// A binary target provides the path to a pre-built binary artifact for the target.
    /// The Swift Package Manager only supports binary targets for Apple platforms.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - path: The path to the binary artifact. This path can point directly to a binary artifact
    ///       or to an archive file that contains the binary artifact at its root.
    ///
    /// Binary targets are only available on Apple platforms.
    @available(_PackageDescription, introduced: 5.3)
    public static func binaryTarget(
        name: String,
        path: String
    ) -> Target {
        return Target(
            name: name,
            dependencies: [],
            path: path,
            exclude: [],
            sources: nil,
            publicHeadersPath: nil,
            type: .binary)
    }
    
    /// Defines a new package plugin target with a given name, declaring it as
    /// providing a capability of adding custom build commands to SwiftPM (and to
    /// any IDEs based on libSwiftPM).
    ///
    /// The capability determines what kind of build commands it can add. Besides
    /// determining at what point in the build those commands run, the capability
    /// determines the context that is available to the plugin and the kinds of
    /// commands it can create.
    ///
    /// In the initial version of this proposal, three capabilities are provided:
    /// prebuild, build tool, and postbuild. See the declaration of each capability
    /// under `PluginCapability` for more information.
    ///
    /// The package plugin itself is implemented using a Swift script that is
    /// invoked for each target that uses it. The script is invoked after the
    /// package graph has been resolved, but before the build system creates its
    /// dependency graph. It is also invoked after changes to the target or the
    /// build parameters.
    ///
    /// Note that the role of the package plugin is only to define the commands
    /// that will run before, during, or after the build. It does not itself run
    /// those commands. The commands are defined in an IDE-neutral way, and are
    /// run as appropriate by the build system that builds the package. The exten-
    /// sion itself is only a procedural way of generating commands and their input
    /// and output dependencies.
    ///
    /// The package plugin may specify the executable targets or binary targets
    /// that provide the build tools that will be used by the generated commands
    /// during the build. In the initial implementation, prebuild actions can only
    /// depend on binary targets. Build tool and postbuild plugins can depend
    /// on executables as well as binary targets. This is because of limitations
    /// in how SwiftPM constructs its build plan, and the goal is to remove this
    /// restriction in a future release.
    @available(_PackageDescription, introduced: 5.5)
    public static func plugin(
        name: String,
        capability: PluginCapability,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: nil,
            type: .plugin,
            pluginCapability: capability)
    }
}

extension Target.Dependency {
    /// Creates a dependency on a target in the same package.
    ///
    /// - parameters:
    ///   - name: The name of the target.
    @available(_PackageDescription, obsoleted: 5.3)
    public static func target(name: String) -> Target.Dependency {
        return .targetItem(name: name, condition: nil)
    }
    
    /// Creates a dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    @available(_PackageDescription, obsoleted: 5.2, message: "the 'package' argument is mandatory as of tools version 5.2")
    public static func product(name: String, package: String? = nil) -> Target.Dependency {
        return .productItem(name: name, package: package, moduleAliases: nil, condition: nil)
    }

    /// Creates a dependency on a product from a dependent package.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - moduleAliases: The module aliases for targets in the product.
    ///   - package: The name of the package.
    @available(_PackageDescription, introduced: 999.0)
    public static func product(name: String, package: String? = nil, moduleAliases: [String: String]? = nil) -> Target.Dependency {
        return .productItem(name: name, package: package, moduleAliases: moduleAliases, condition: nil)
    }

    /// Creates a dependency that resolves to either a target or a product with the specified name.
    ///
    /// - parameters:
    ///   - name: The name of the dependency, either a target or a product.
    ///
    /// The Swift Package Manager creates the by-name dependency after it has loaded the package graph.
    @available(_PackageDescription, obsoleted: 5.3)
    public static func byName(name: String) -> Target.Dependency {
        return .byNameItem(name: name, condition: nil)
    }
    
    /// Creates a dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    @available(_PackageDescription, introduced: 5.2, obsoleted: 5.3)
    public static func product(
        name: String,
        package: String
    ) -> Target.Dependency {
        return .productItem(name: name, package: package, moduleAliases: nil, condition: nil)
    }
    
    /// Creates a dependency on a target in the same package.
    ///
    /// - parameters:
    ///   - name: The name of the target.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @available(_PackageDescription, introduced: 5.3)
    public static func target(name: String, condition: TargetDependencyCondition? = nil) -> Target.Dependency {
        return .targetItem(name: name, condition: condition)
    }
    
    /// Creates a target dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @_disfavoredOverload
    @available(_PackageDescription, introduced: 5.3, obsoleted: 5.7)
    public static func product(
        name: String,
        package: String,
        condition: TargetDependencyCondition? = nil
    ) -> Target.Dependency {
        return .productItem(name: name, package: package, moduleAliases: nil, condition: condition)
    }

    /// Creates a target dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    ///   - moduleAliases: The module aliases for targets in the product.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @available(_PackageDescription, introduced: 5.7)
    public static func product(
      name: String,
      package: String,
      moduleAliases: [String: String]? = nil,
      condition: TargetDependencyCondition? = nil
    ) -> Target.Dependency {
        return .productItem(name: name, package: package, moduleAliases: moduleAliases, condition: condition)
    }

    /// Creates a by-name dependency that resolves to either a target or a product but after the Swift Package Manager
    /// has loaded the package graph.
    ///
    /// - parameters:
    ///   - name: The name of the dependency, either a target or a product.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @available(_PackageDescription, introduced: 5.3)
    public static func byName(name: String, condition: TargetDependencyCondition? = nil) -> Target.Dependency {
        return .byNameItem(name: name, condition: condition)
    }
}

/// A condition that limits the application of a target's dependency.
public struct TargetDependencyCondition: Encodable {
    private let platforms: [Platform]?

    private init(platforms: [Platform]?) {
        self.platforms = platforms
    }

    /// Creates a target dependency condition.
    ///
    /// - Parameters:
    ///   - platforms: The applicable platforms for this target dependency condition.
    @_disfavoredOverload
    @available(_PackageDescription, obsoleted: 5.7, message: "using .when with nil platforms is obsolete")
    public static func when(
        platforms: [Platform]? = nil
    ) -> TargetDependencyCondition {
        // FIXME: This should be an error, not a precondition.
        precondition(!(platforms == nil))
        return TargetDependencyCondition(platforms: platforms)
    }

    /// Creates a target dependency condition.
    ///
    /// - Parameters:
    ///   - platforms: The applicable platforms for this target dependency condition.
    @available(_PackageDescription, introduced: 5.7)
    public static func when(
        platforms: [Platform]
    ) -> TargetDependencyCondition? {
        return !platforms.isEmpty ? TargetDependencyCondition(platforms: platforms) : .none
    }
}

extension Target.PluginCapability {
    
    /// Specifies that the plugin provides a build tool capability. The plugin
    /// will be applied to each target that uses it and should create commands
    /// that will run before or during the build of the target.
    @available(_PackageDescription, introduced: 5.5)
    public static func buildTool() -> Target.PluginCapability {
        return ._buildTool
    }

    /// Specifies that the plugin provides a user command capability. It will
    /// be available to invoke manually on one or more targets in a package.
    /// The package can specify the verb that is used to invoke the command.
    @available(_PackageDescription, introduced: 5.6)
    /// Plugins that specify a `command` capability define commands that can be run
    /// using the SwiftPM CLI (`swift package <verb>`), or in an IDE that supports
    /// Swift Packages.
    public static func command(
        /// The semantic intent of the plugin (either one of the predefined intents,
        /// or a custom intent).
        intent: PluginCommandIntent,

        /// Any permissions needed by the command plugin. This affects what the
        /// sandbox in which the plugin is run allows. Some permissions may require
        /// approval by the user.
        permissions: [PluginPermission] = []
    ) -> Target.PluginCapability {
        return ._command(intent: intent, permissions: permissions)
    }
}

@available(_PackageDescription, introduced: 5.6)
public enum PluginCommandIntent {
    case _documentationGeneration
    case _sourceCodeFormatting
    case _custom(verb: String, description: String)
}

@available(_PackageDescription, introduced: 5.6)
public extension PluginCommandIntent {
    /// The intent of the command is to generate documentation, either by parsing the
    /// package contents directly or by using the build system support for generating
    /// symbol graphs. Invoked by a `generate-documentation` verb to `swift package`.
    static func documentationGeneration() -> PluginCommandIntent {
        return _documentationGeneration
    }
    
    /// The intent of the command is to modify the source code in the package based
    /// on a set of rules. Invoked by a `format-source-code` verb to `swift package`.
    static func sourceCodeFormatting() -> PluginCommandIntent {
        return _sourceCodeFormatting
    }

    /// An intent that doesn't fit into any of the other categories, with a custom
    /// verb through which it can be invoked.
    static func custom(verb: String, description: String) -> PluginCommandIntent {
        return _custom(verb: verb, description: description)
    }
}

@available(_PackageDescription, introduced: 5.6)
public enum PluginPermission {
    case _writeToPackageDirectory(reason: String)
}

@available(_PackageDescription, introduced: 5.6)
public extension PluginPermission {
    /// The command plugin wants permission to modify the files under the package
    /// directory. The `reason` string is shown to the user at the time of request
    /// for approval, explaining why the plugin is requesting this access.
    static func writeToPackageDirectory(reason: String) -> PluginPermission {
        return _writeToPackageDirectory(reason: reason)
    }
}

extension Target.PluginUsage {
    /// Specifies use of a plugin target in the same package.
    ///
    /// - parameters:
    ///   - name: The name of the plugin target.
    @available(_PackageDescription, introduced: 5.5)
    public static func plugin(name: String) -> Target.PluginUsage {
        return ._pluginItem(name: name, package: nil)
    }
    
    /// Specifies use of a plugin product in a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the plugin product.
    ///   - package: The name of the package in which it is defined.
    @available(_PackageDescription, introduced: 5.5)
    public static func plugin(name: String, package: String) -> Target.PluginUsage {
        return ._pluginItem(name: name, package: package)
    }
}


// MARK: ExpressibleByStringLiteral

extension Target.Dependency: ExpressibleByStringLiteral {

    /// Creates a target dependency instance with the given value.
    ///
    /// - parameters:
    ///   - value: A string literal.
    public init(stringLiteral value: String) {
        self = .byNameItem(name: value, condition: nil)
    }
}

extension Target.PluginUsage: ExpressibleByStringLiteral {

    /// Specifies use of a plugin target in the same package.
    ///
    /// - parameters:
    ///   - value: A string literal.
    public init(stringLiteral value: String) {
        self = ._pluginItem(name: value, package: nil)
    }
}

