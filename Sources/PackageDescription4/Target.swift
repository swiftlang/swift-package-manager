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
        case Target(name: String)

        /// A dependency on a product from a package dependency.
        /// The package name match the name of one of the packages named in a `.Package()` directive.
        case Product(name: String, package: String?)

        /// A by-name dependency that resolves to either a target or a product, as above, after the package graph has been loaded.
        case ByName(name: String)
    }

    /// The name of the target.
    public let name: String

    /// Dependencies on other entities inside or outside the package.
    public var dependencies: [Dependency]

    /// Construct a target.
    public init(name: String, dependencies: [Dependency] = []) {
        self.name = name
        self.dependencies = dependencies
    }
}

// MARK: ExpressibleByStringLiteral

extension Target.Dependency : ExpressibleByStringLiteral {
  public init(unicodeScalarLiteral value: String) {
    self = .ByName(name: value)
  }
  
  public init(extendedGraphemeClusterLiteral value: String) {
    self = .ByName(name: value)
  }

  public init(stringLiteral value: String) {
    self = .ByName(name: value)
  } 
}

// MARK: Equatable

extension Target : Equatable { }
public func ==(lhs: Target, rhs: Target) -> Bool {
    return (lhs.name == rhs.name &&
        lhs.dependencies == rhs.dependencies)
}

extension Target.Dependency : Equatable { }
public func ==(lhs: Target.Dependency, rhs: Target.Dependency) -> Bool {
    switch (lhs, rhs) {
    case (.Target(let a), .Target(let b)):
        return a == b
    case (.Target, _):
        return false
    case (.Product(let an, let ap), .Product(let bn, let bp)):
        return an == bn && ap == bp
    case (.Product, _):
        return false
    case (.ByName(let a), .ByName(let b)):
        return a == b
    case (.ByName, _):
        return false
    }
}
