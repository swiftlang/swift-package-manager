//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A resource to bundle with the Swift package.
///
/// If a Swift package declares a Swift tools version of 5.3 or later, it can
/// include resource files. Similar to source code, Swift Package Manager scopes resources to a
/// target, so you must put them into the folder that corresponds to the target
/// they belong to. For example, any resources for the `MyLibrary` target must
/// reside in `Sources/MyLibrary`. Use subdirectories to organize your resource
/// files in a way that simplifies file identification and management. For
/// example, put all resource files into a directory named `Resources`, so they
/// reside at `Sources/MyLibrary/Resources`.
///
/// By default, Swift Package Manager handles common resources types for Apple platforms
/// automatically. For example, you don't need to declare XIB files,
/// storyboards, Core Data file types, and asset catalogs as resources in your
/// package manifest. However, you must explicitly declare other file types — for
/// example, image files — as resources using the
/// ``Resource/process(_:localization:)`` or ``Resource/copy(_:)`` rules.
/// Alternatively, exclude resource files from a target by passing them to the
/// target initializer's ``Target/exclude`` parameter.
///
/// To learn more about package resources, see
/// <doc:bundling-resources-with-a-swift-package>.
@available(_PackageDescription, introduced: 5.3)
public struct Resource: Sendable {

    /// Defines the explicit type of localization for resources.
    public enum Localization: String, Sendable {

        /// A constant that represents default localization.
        case `default`

        /// A constant that represents base internationalization.
        case base
    }

    /// The rule for the resource.
    let rule: String
	
    /// The path of the resource.
    let path: String

    /// The explicit type of localization for the resource.
    let localization: Localization?

    private init(rule: String, path: String, localization: Localization?) {
        self.rule = rule
        self.path = path
        self.localization = localization
    }

    /// Applies a platform-specific rules to the resource at the given path.
    ///
    /// Use the `process` rule to process resources at the given path according
    /// to the platform Swift Package Manager builds the target for. For example, Swift Package Manager may
    /// optimize image files for platforms that support such optimizations. If
    /// no optimization is available for a file type, Swift Package Manager copies the file.
    ///
    /// If the given path represents a directory, Swift Package Manager applies the process rule
    /// recursively to each file in the directory.
    ///
    /// If possible, use this rule instead of ``Resource/copy(_:)``.
    ///
    /// - Parameters:
    ///   - path: The path for a resource.
    ///   - localization: The explicit localization type for the resource.
    /// - Returns: A `Resource` instance.
    public static func process(_ path: String, localization: Localization? = nil) -> Resource {
        return Resource(rule: "process", path: path, localization: localization)
    }

    /// Applies the copy rule to a resource at the given path.
    ///
    /// If possible, use ``Resource/process(_:localization:)`` and automatically
    /// apply optimizations to resources.
    ///
    /// If your resources must remain untouched or must retain a specific folder
    /// structure, use the `copy` rule. It copies resources at the given `path`,
    /// as is, to the top level in the package's resource bundle. If the given
    /// path represents a directory, Swift Package Manager preserves its structure.
    ///
    /// - Parameter path: The path for a resource.
    /// - Returns: A `Resource` instance.
    public static func copy(_ path: String) -> Resource {
        return Resource(rule: "copy", path: path, localization: nil)
    }

    /// Applies the embed rule to a resource at the given path.
    ///
    /// You can use the embed rule to embed the contents of the resource into the executable code.
    /// - Parameter path: The path for a resource.
    /// - Returns: A `Resource` instance.
    @available(_PackageDescription, introduced: 5.9)
    public static func embedInCode(_ path: String) -> Resource {
        return Resource(rule: "embedInCode", path: path, localization: nil)
    }
}
