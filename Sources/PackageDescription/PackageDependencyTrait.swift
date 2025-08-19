//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Package.Dependency {
    /// An enabled trait of a dependency.
    @available(_PackageDescription, introduced: 6.1)
    public struct Trait: Hashable, Sendable, ExpressibleByStringLiteral {
        /// Enables all default traits of the dependency.
        public static let defaults = Self.init(name: "default")

        /// A condition that limits the application of a trait for a dependency.
        public struct Condition: Hashable, Sendable {
            /// The set of traits that enable the dependencies trait.
            let traits: Set<String>?

            /// Creates a package dependency trait condition.
            ///
            /// If any of the traits you provide are enabled on this package, the package manager enables the dependency to which the condition applies.
            ///
            /// - Parameter traits: The set of traits that enable the dependencies trait.
            public static func when(
                traits: Set<String>
            ) -> Self? {
                return !traits.isEmpty ? Self(traits: traits) : nil
            }
        }

        /// The name of the enabled trait.
        public var name: String

        /// The condition under which the trait is enabled.
        public var condition: Condition?

        /// Creates a new enabled trait.
        ///
        /// - Parameters:
        ///   - name: The name of the enabled trait.
        ///   - condition: The condition under which the trait is enabled.
        public init(
            name: String,
            condition: Condition? = nil
        ) {
            self.name = name
            self.condition = condition
        }

        public init(stringLiteral value: StringLiteralType) {
            self.init(name: value)
        }

        /// Creates a new enabled trait.
        ///
        /// - Parameters:
        ///   - name: The name of the enabled trait.
        ///   - condition: The condition under which the trait is enabled.
        public static func trait(
            name: String,
            condition: Condition? = nil
        ) -> Trait {
            self.init(
                name: name,
                condition: condition
            )
        }
    }
}
