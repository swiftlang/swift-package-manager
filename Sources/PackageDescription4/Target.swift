/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A target, the basic building block of a Swift package.
/// 
/// Each target contains a set of source files that are compiled into a module or test suite.
/// You can vend targets to other packages by defining products that include the targets.
/// 
/// A target may depend on other targets within the same package and on products vended by the package's dependencies.
public final class Target {

    /// The different types of a target.
    public enum TargetType: String, Encodable {
        case regular
        case test
        case system
    }

    /// The different types of a target's dependency on another entity.
    public enum Dependency {
      #if PACKAGE_DESCRIPTION_4
        case targetItem(name: String)
        case productItem(name: String, package: String?)
        case byNameItem(name: String)
      #else
        case _targetItem(name: String)
        case _productItem(name: String, package: String?)
        case _byNameItem(name: String)
      #endif
    }

    /// The name of the target.
    public var name: String

    /// The path of the target, relative to the package root.
    ///
    /// If the path is `nil`, the Swift Package Manager looks for a targets source files at predefined search paths
    /// and in a subdirectory with the target's name.
    ///
    /// The predefined search paths are the following directories under the package root:
    ///   - For regular targets: `Sources`, `Source`, `src`, and `srcs`
    ///   - For test targets: `Tests`, `Sources`, `Source`, `src`, `srcs`
    ///
    /// For example, the Swift Package Manager will look for source files inside the `[PackageRoot]/Sources/[TargetName]` directory.
    ///
    /// Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
    public var path: String?

    /// The source files in this target.
    ///
    /// If this property is `nil`, all valid source files in the target's path will be included and specified paths are relative to the target path.
    ///
    /// A path can be a path to a directory or an individual source file. In case of a directory, the Swift Package Manager searches for valid source files
    /// recursively inside it.
    public var sources: [String]?

    /// The explicit list of resource files in the target.
    @available(_PackageDescription, introduced: 5.2)
    public var resources: [Resource]? {
        get { _resources }
        set { _resources = newValue }
    }
    private var _resources: [Resource]?

    /// The paths you want to exclude from source inference.
    ///
    /// Excluded paths are relative to the target path.
    /// This property has precedence over the `sources` property.
    public var exclude: [String]

    /// A boolean value that indicates if this is a test target.
    public var isTest: Bool {
        return type == .test
    }

    /// The target's dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]

    /// The path to the directory containing public headers of a C-family target.
    ///
    /// If this is `nil`, the directory will be set to `include`.
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

    /// Construct a target.
    private init(
        name: String,
        dependencies: [Dependency],
        path: String?,
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
        linkerSettings: [LinkerSetting]? = nil
    ) {
        self.name = name
        self.dependencies = dependencies
        self.path = path
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

        switch type {
        case .regular, .test:
            precondition(pkgConfig == nil && providers == nil)
        case .system: break
        }
    }

    /// Create a library or executable target.
    ///
    /// A target can either contain Swift or C-family source files and you can't
    /// mix Swift and C-family source files within a target. A target is
    /// considered to be an executable target if there is a `main.swift`,
    /// `main.m`, `main.c`, or `main.cpp` file in the target's directory. All
    /// other targets are considered to be library targets.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that should not be considered source files. This path is relative to the target's directory.
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. In case of a directory, the Swift Package Manager searches for valid source files
    ///       recursively.
    ///   - publicHeadersPath: The path to the directory containing public headers of a C-family target.
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

    /// Create a library or executable target.
    ///
    /// A target can either contain Swift or C-family source files. You can't
    /// mix Swift and C-family source files within a target. A target is
    /// considered to be an executable target if there is a `main.swift`,
    /// `main.m`, `main.c`, or `main.cpp` file in the target's directory. All
    /// other targets are considered to be library targets.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid..
    ///   - exclude: A list of paths to files or directories that should not be considered source files. This path is relative to the target's directory.
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. In case of a directory, the Swift Package Manager searches for valid source files
    ///       recursively.
    ///   - publicHeadersPath: The directory containing public headers of a C-family family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5, obsoleted: 5.2)
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

    /// Create a library or executable target.
    ///
    /// A target can either contain Swift or C-family source files. You can't
    /// mix Swift and C-family source files within a target. A target is
    /// considered to be an executable target if there is a `main.swift`,
    /// `main.m`, `main.c`, or `main.cpp` file in the target's directory. All
    /// other targets are considered to be library targets.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid..
    ///   - exclude: A list of paths to files or directories that should not be considered source files. This path is relative to the target's directory.
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. In case of a directory, the Swift Package Manager searches for valid source files
    ///       recursively.
    ///   - resources: An explicit list of resources files.
    ///   - publicHeadersPath: The directory containing public headers of a C-family family library target.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5.2)
    public static func target(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        // FIXME: Underscored until the evolution process is finished.
        __resources: [Resource]? = nil,
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
            resources: __resources,
            publicHeadersPath: publicHeadersPath,
            type: .regular,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        )
    }

    /// Create a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that should not be considered source files. This path is relative to the target's directory.
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. In case of a directory, the Swift Package Manager searches for valid source files
    ///       recursively.
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

    /// Create a test target.
    ///
    /// Write test targets using the XCTest testing framework.
    /// Test targets generally declare a dependency on the targets they test.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - dependencies: The dependencies of the target. A dependency can be another target in the package or a product from a package dependency.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
    ///   - exclude: A list of paths to files or directories that should not be considered source files. This path is relative to the target's directory.
    ///       This parameter has precedence over the `sources` parameter.
    ///   - sources: An explicit list of source files. In case of a directory, the Swift Package Manager searches for valid source files
    ///       recursively.
    ///   - cSettings: The C settings for this target.
    ///   - cxxSettings: The C++ settings for this target.
    ///   - swiftSettings: The Swift settings for this target.
    ///   - linkerSettings: The linker settings for this target.
    @available(_PackageDescription, introduced: 5)
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


  #if !PACKAGE_DESCRIPTION_4
    /// Create a system library target.
    /// 
    /// Use system library targets to adapt a library installed on the system to work with Swift packages.
    /// Such libraries are generally installed by system package managers (such as Homebrew and apt-get)
    /// and exposed to Swift packages by providing a `modulemap` file along with other metadata such as the library's `pkgConfig` name.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - path: The custom path for the target. By default, a targets sources are expected to be located in the predefined search paths,
    ///       such as `[PackageRoot]/Sources/[TargetName]`.
    ///       Do not escape the package root; that is, values like `../Foo` or `/Foo` are invalid.
     ///  - pkgConfig: The name of the `pkg-config` file for this system library.
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
  #endif
}

extension Target: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case path
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(sources, forKey: .sources)
        try container.encode(_resources, forKey: .resources)
        try container.encode(exclude, forKey: .exclude)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(publicHeadersPath, forKey: .publicHeadersPath)
        try container.encode(type, forKey: .type)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)

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
    public static func target(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .targetItem(name: name)
      #else
        return ._targetItem(name: name)
      #endif
    }

    /// Creates a dependency on a product from a package dependency.
    ///
    /// - parameters:
    ///   - name: The name of the product.
    ///   - package: The name of the package.
    public static func product(name: String, package: String? = nil) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .productItem(name: name, package: package)
      #else
        return ._productItem(name: name, package: package)
      #endif
    }

    /// Creates a by-name dependency that resolves to either a target or a product but
    /// after the package graph has been loaded.
    ///
    /// - parameters:
    ///   - name: The name of the dependency, either a target or a product.
    public static func byName(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .byNameItem(name: name)
      #else
        return ._byNameItem(name: name)
      #endif
    }
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
        self = ._byNameItem(name: value)
      #endif
    }
}
