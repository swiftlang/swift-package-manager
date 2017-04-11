/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The description for an individual target.
public final class Target {

    /// Represents a target's dependency on another entity.
    public enum Dependency {

        /// A dependency on a target in the same package.
        case targetItem(name: String)

        /// A dependency on a product from a package dependency.
        case productItem(name: String, package: String?)

        // A by-name dependency that resolves to either a target or a product,
        // as above, after the package graph has been loaded.
        case byNameItem(name: String)
    }

    /// The name of the target.
    public var name: String

    /// If this is a test target.
    public var isTest: Bool

    /// Dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]

    /// Construct a target.
    init(
        name: String,
        dependencies: [Dependency],
        isTest: Bool
    ) {
        self.name = name
        self.dependencies = dependencies
        self.isTest = isTest
    }

    public static func target(
        name: String,
        dependencies: [Dependency] = []
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            isTest: false
        )
    }

    public static func testTarget(
        name: String,
        dependencies: [Dependency] = []
    ) -> Target {
        return Target(
            name: name,
            dependencies: dependencies,
            isTest: true
        )
    }
}

extension Target.Dependency {
    public static func target(name: String) -> Target.Dependency {
        return .targetItem(name: name)
    }

    public static func product(name: String, package: String? = nil) -> Target.Dependency {
        return .productItem(name: name, package: package)
    }

    public static func byName(name: String) -> Target.Dependency {
        return .byNameItem(name: name)
    }
}

// MARK: Equatable

extension Target: Equatable {
    public static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.name == rhs.name &&
               lhs.dependencies == rhs.dependencies
    }
}

extension Target.Dependency: Equatable {
    public static func == (
        lhs: Target.Dependency,
        rhs: Target.Dependency
    ) -> Bool {
        switch (lhs, rhs) {
        case (.targetItem(let a), .targetItem(let b)):
            return a == b
        case (.targetItem, _):
            return false
        case (.productItem(let an, let ap), .productItem(let bn, let bp)):
            return an == bn && ap == bp
        case (.productItem, _):
            return false
        case (.byNameItem(let a), .byNameItem(let b)):
            return a == b
        case (.byNameItem, _):
            return false
        }
    }
}

// MARK: ExpressibleByStringLiteral

extension Target.Dependency: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        self = .byNameItem(name: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
}
