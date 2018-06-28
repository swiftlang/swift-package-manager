/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The description for an individual target.
public final class Target {

    /// The type of this target.
    public enum TargetType: String {
        case regular
        case test
        case system
    }

    /// Represents a target's dependency on another entity.
    public enum Dependency: Equatable {
      #if PACKAGE_DESCRIPTION_4_2
        case _targetItem(name: String)
        case _productItem(name: String, package: String?)
        case _byNameItem(name: String)
      #else
        case targetItem(name: String)
        case productItem(name: String, package: String?)
        case byNameItem(name: String)
      #endif
    }

    /// The name of the target.
    public var name: String

    /// The path of the target, relative to the package root.
    ///
    /// If nil, package manager will search the predefined paths to look
    /// for this target.
    public var path: String?

    /// The source files in this target.
    ///
    /// If nil, all valid source files found in the target's path will be included.
    ///
    /// This can contain directories and individual source files. Directories
    /// will be searched recursively for valid source files.
    ///
    /// Paths specified are relative to the target path.
    public var sources: [String]?

    /// List of paths to be excluded from source inference.
    ///
    /// Exclude paths are relative to the target path.
    /// This property has more precedence than sources property.
    public var exclude: [String]

    /// If this is a test target.
    public var isTest: Bool {
        return type == .test
    }

    /// Dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]

    /// The path to the directory containing public headers of a C language target.
    ///
    /// If a value is not provided, the directory will be set to "include".
    public var publicHeadersPath: String?

    /// The type of target.
    public let type: TargetType

    /// `pkgconfig` name to use for system library target. If present, swiftpm will try to
    /// search for <name>.pc file to get the additional flags needed for the
    /// system target.
    public let pkgConfig: String?

    /// Providers array for the System library target.
    public let providers: [SystemPackageProvider]?

    /// Construct a target.
    init(
        name: String,
        dependencies: [Dependency],
        path: String?,
        exclude: [String],
        sources: [String]?,
        publicHeadersPath: String?,
        type: TargetType,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil
    ) {
        self.name = name
        self.dependencies = dependencies
        self.path = path
        self.publicHeadersPath = publicHeadersPath
        self.sources = sources
        self.exclude = exclude
        self.type = type
        self.pkgConfig = pkgConfig
        self.providers = providers

        switch type {
        case .regular, .test:
            precondition(pkgConfig == nil && providers == nil)
        case .system: break
        }
    }

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
            type: .regular)
    }

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
            type: .test)
    }

  #if !PACKAGE_DESCRIPTION_4
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

extension Target.Dependency {
    /// A dependency on a target in the same package.
    public static func target(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4_2
        return ._targetItem(name: name)
      #else
        return .targetItem(name: name)
      #endif
    }

    /// A dependency on a product from a package dependency.
    public static func product(name: String, package: String? = nil) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4_2
        return ._productItem(name: name, package: package)
      #else
        return .productItem(name: name, package: package)
      #endif
    }

    // A by-name dependency that resolves to either a target or a product,
    // as above, after the package graph has been loaded.
    public static func byName(name: String) -> Target.Dependency {
      #if PACKAGE_DESCRIPTION_4_2
        return ._byNameItem(name: name)
      #else
        return .byNameItem(name: name)
      #endif
    }
}

// MARK: Equatable

extension Target: Equatable {
    public static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.name == rhs.name &&
               lhs.dependencies == rhs.dependencies
    }
}

// MARK: ExpressibleByStringLiteral

extension Target.Dependency: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
      #if PACKAGE_DESCRIPTION_4_2
        self = ._byNameItem(name: value)
      #else
        self = .byNameItem(name: value)
      #endif
    }
}
