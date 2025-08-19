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

/// A struct that represents a package's trait.
///
/// Use traits to represent and expose extended API for a package.
/// When you define a trait on a package, the package manager exposes the name of that trait as a conditional block to conditionally enable imports or code paths.
/// For example, a trait with the canonical name `MyTrait` allows you to use the name as a conditional block:
///
/// ```swift
/// #if Trait1
/// // additional imports or APIs that Trait1 enables
/// #endif // Trait1
/// ```
///
/// - Important: Traits must be strictly additive. Enabling a trait **must not** remove API.
@available(_PackageDescription, introduced: 6.1)
public struct Trait: Hashable, ExpressibleByStringLiteral {
    /// Declares the default traits for this package.
    public static func `default`(enabledTraits: Set<String>) -> Self {
        .init(
            name: "default",
            description: "The default traits of this package.",
            enabledTraits: enabledTraits
        )
    }

    /// The trait's canonical name.
    ///
    /// Use the trait's name to enable the trait or when referring to it from other modifiers in the manifest.
    ///
    /// The following rules are enforced on trait names:
    /// - The first character must be a [Unicode XID start character](https://unicode.org/reports/tr31/#Figure_Code_Point_Categories_for_Identifier_Parsing)
    /// (most letters), a digit, or `_`.
    /// - Subsequent characters must be a [Unicode XID continue character](https://unicode.org/reports/tr31/#Figure_Code_Point_Categories_for_Identifier_Parsing)
    /// (a digit, `_`, or most letters), `-`, or `+`.
    /// - The names `default` and `defaults` (in any letter casing combination) aren't allowed as trait names to avoid confusion with default traits.
    public var name: String

    /// The trait's description.
    ///
    /// Use the description to explain the functionality the trait enables.
    public var description: String?

    /// A set of other traits of this package that this trait enables.
    public var enabledTraits: Set<String>

    /// Creates a new trait with a name, and optionally a description and set of enabled traits.
    ///
    /// - Parameters:
    ///   - name: The trait's canonical name.
    ///   - description: The trait's description.
    ///   - enabledTraits: A set of other traits of this package that this trait enables.
    public init(
        name: String,
        description: String? = nil,
        enabledTraits: Set<String> = []
    ) {
        self.name = name
        self.description = description
        self.enabledTraits = enabledTraits
    }

    /// Creates a trait with the name you provide.
    /// - Parameter value: The trait's canonical name.
    public init(stringLiteral value: StringLiteralType) {
        self.init(name: value)
    }

    /// Creates a new trait with a name, and optionally a description and set of enabled traits.
    ///
    /// - Parameters:
    ///   - name: The trait's canonical name.
    ///   - description: The trait's description.
    ///   - enabledTraits: A set of other traits of this package that this trait enables.
    public static func trait(
        name: String,
        description: String? = nil,
        enabledTraits: Set<String> = []
    ) -> Trait {
        .init(
            name: name,
            description: description,
            enabledTraits: enabledTraits
        )
    }
}
