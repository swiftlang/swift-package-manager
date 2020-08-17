/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
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
        /// A target that contains tests for the Swift package’s other targets.
        case test
        /// A target that adapts a library on the system to work with Swift packages.
        case system
        /// A target that references a binary artifact.
        case binary
    }

    /// The different types of a target's dependency on another entity.
    public enum Dependency {
      #if PACKAGE_DESCRIPTION_4
        case targetItem(name: String)
        case productItem(name: String, package: String?)
        case byNameItem(name: String)
      #else
        case _targetItem(name: String, condition: TargetDependencyCondition?)
        case _productItem(name: String, package: String?, condition: TargetDependencyCondition?)
        case _byNameItem(name: String, condition: TargetDependencyCondition?)
      #endif
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
    public var url: String? {
        get { _url }
        set { _url = newValue }
    }
    public var _url: String?

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
    /// This property has precedence over the `sources` and `resources` properties.
    public var exclude: [String]

    /// A boolean value that indicates if this is a test target.
    public var isTest: Bool {
        return type == .test
    }

    /// The target's dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]

    /// The path to the directory containing public headers of a C-family target.
    ///
    /// If this is `nil`, the directory is set to `include`.
    public var publicHeadersPath: String?

    /// The type of the target.
    public let type: TargetType

    /// The `pkgconfig` name to use for a system library target.
    ///
    /// If present, the Swift Package Manager tries to
    /// search for the `<name>.pc` file to get the additional flags needed for the
    /// system target.
    public let pkgConfig: String?

    /// The providers array for a system library target.
    public let providers: [SystemPackageProvider]?

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
    public var _checksum: String?

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
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        checksum: String? = nil
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
        self._cSettings = cSettings
        self._cxxSettings = cxxSettings
        self._swiftSettings = swiftSettings
        self._linkerSettings = linkerSettings
        self._checksum = checksum

        switch type {
        case .regular, .test:
            precondition(
                url == nil &&
                pkgConfig == nil &&
                providers == nil &&
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
                cSettings == nil &&
                cxxSettings == nil &&
                swiftSettings == nil &&
                linkerSettings == nil &&
                checksum == nil
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
                cSettings == nil &&
                cxxSettings == nil &&
                swiftSettings == nil &&
                linkerSettings == nil
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
    ///       This parameter has precedence over the `sources` parameter.
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
    ///       This parameter has precedence over the `sources` parameter.
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
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.3)
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
    ///       This parameter has precedence over the `sources` parameter.
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
    ///       This parameter has precedence over the `sources` parameter.
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
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. If you provide a path to a directory,
    ///       the Swift Package Manager searches for valid source files recursively.
    ///   - resources: An explicit list of resources files.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.3)
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

  #if !PACKAGE_DESCRIPTION_4
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
  #endif
}

extension Target: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case path
        case url
        case sources
        case resources
        case exclude
        case dependencies
        case publicHeadersPath
        case type
        case pkgConfig
        case providers
        case cSettings
        case cxxSettings
        case swiftSettings
        case linkerSettings
        case checksum
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(_url, forKey: .url)
        try container.encode(sources, forKey: .sources)
        try container.encode(_resources, forKey: .resources)
        try container.encode(exclude, forKey: .exclude)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(publicHeadersPath, forKey: .publicHeadersPath)
        try container.encode(type, forKey: .type)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(_checksum, forKey: .checksum)

        if let cSettings = self._cSettings {
            try container.encode(cSettings, forKey: .cSettings)
        }

        if let cxxSettings = self._cxxSettings {
            try container.encode(cxxSettings, forKey: .cxxSettings)
        }

        if let swiftSettings = self._swiftSettings {
            try container.encode(swiftSettings, forKey: .swiftSettings)
        }

        if let linkerSettings = self._linkerSettings {
            try container.encode(linkerSettings, forKey: .linkerSettings)
        }
    }
}

extension Target.Dependency {
    /// Creates a dependency on a target in the same package.
    ///
    /// - parameters:
    ///   - name: The name of the target.
    @available(_PackageDescription, obsoleted: 5.3)
    public static func target(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .targetItem(name: name)
      #else
        return ._targetItem(name: name, condition: nil)
      #endif
    }

    /// Creates a dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    @available(_PackageDescription, obsoleted: 5.2, message: "the 'package' argument is mandatory as of tools version 5.2")
    public static func product(name: String, package: String? = nil) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .productItem(name: name, package: package)
      #else
        return ._productItem(name: name, package: package, condition: nil)
      #endif
    }

    /// Creates a dependency that resolves to either a target or a product with the specified name.
    ///
    /// - parameters:
    ///   - name: The name of the dependency, either a target or a product.
    ///
    /// The Swift package manager creates the by-name dependency after it has loaded the package graph.
    @available(_PackageDescription, obsoleted: 5.3)
    public static func byName(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .byNameItem(name: name)
      #else
        return ._byNameItem(name: name, condition: nil)
      #endif
    }

  #if !PACKAGE_DESCRIPTION_4
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
        return ._productItem(name: name, package: package, condition: nil)
    }

    /// Creates a dependency on a target in the same package.
    ///
    /// - parameters:
    ///   - name: The name of the target.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @available(_PackageDescription, introduced: 5.3)
    public static func target(name: String, condition: TargetDependencyCondition? = nil) -> Target.Dependency {
        return ._targetItem(name: name, condition: condition)
    }

    /// Creates a target dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    ///   - condition: A condition that limits the application of the target dependency. For example, only apply a
    ///       dependency for a specific platform.
    @available(_PackageDescription, introduced: 5.3)
    public static func product(
        name: String,
        package: String,
        condition: TargetDependencyCondition? = nil
    ) -> Target.Dependency {
        return ._productItem(name: name, package: package, condition: condition)
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
        return ._byNameItem(name: name, condition: condition)
    }
  #endif
}

// MARK: ExpressibleByStringLiteral

extension Target.Dependency: ExpressibleByStringLiteral {

    /// Creates a target dependency instance with the given value.
    ///
    /// - parameters:
    ///   - value: A string literal.
    public init(stringLiteral value: String) {
      #if PACKAGE_DESCRIPTION_4
        self = .byNameItem(name: value)
      #else
        self = ._byNameItem(name: value, condition: nil)
      #endif
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
    public static func when(
        platforms: [Platform]? = nil
    ) -> TargetDependencyCondition {
        // FIXME: This should be an error, not a precondition.
        precondition(!(platforms == nil))
        return TargetDependencyCondition(platforms: platforms)
    }
}
