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

/// A package trait.
///
/// A trait is a package feature that expresses conditional compilation and potentially optional dependencies.
/// It is typically used to expose additional or extended API for the package.
///
/// When you define a trait on a package, the package manager uses the name of that trait as a conditional block for the package's code.
/// Use the conditional block to enable imports or code paths for that trait.
/// For example, a trait with the canonical name `MyTrait` allows you to use the name as a conditional block:
///
/// ```swift
/// #if Trait1
/// // additional imports or APIs that Trait1 enables
/// #endif // Trait1
/// ```
///
/// - Important: Traits must be strictly additive. Enabling a trait **must not** remove API.
///
/// If your conditional code requires an dependency that you want to enable only when the trait is enabled,
/// add a conditional declaration to the target dependencies,
/// then include the import statement within the conditional block.
/// The following example illustrates enabling the dependency `MyDependency` when the trait `Trait1` is enabled:
///
/// ```swift
/// targets: [
///    .target(
///        name: "MyTarget",
///        dependencies: [
///            .product(
///                name: "MyAPI",
///                package: "MyDependency",
///                condition: .when(traits: ["Trait1"])
///            )
///        ]
///    ),
/// ]
/// ```
///
/// Coordinate a declaration like the example above with code that imports the dependency in a conditional block:
///
/// ```swift
/// #if Trait1
/// import MyAPI
/// #endif // Trait1
/// ```
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
    /// The trait's name also defines the conditional block that the compiler supports when the trait is active.
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
    /// Use the description to explain the additional functionality that the trait enables.
    public var description: String?

    /// A set of other traits of this package that this trait enables.
    public var enabledTraits: Set<String>

    /// Creates a trait with a name, a description, and set of additional traits it enables.
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

    /// Creates a trait with a name, a description, and set of additional traits it enables.
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
