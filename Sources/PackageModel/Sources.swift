/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

/// A grouping of related source files.
public struct Sources {
    public let relativePaths: [RelativePath]
    public let root: AbsolutePath

    public var paths: [AbsolutePath] {
        return relativePaths.map({ root.appending($0) })
    }

    public init(paths: [AbsolutePath], root: AbsolutePath) {
        let relativePaths = paths.map({ $0.relative(to: root) })
        self.relativePaths = relativePaths.sorted(by: { $0.asString < $1.asString })
        self.root = root
    }
}

/// An enum representing supported source file extensions.
public enum SupportedLanguageExtension: String {
    /// Swift
    case swift
    /// C
    case c
    /// Objective C
    case m
    /// Objective-C++
    case mm
    /// C++
    case cc
    case cpp
    case cxx

    /// Returns a set of valid swift extensions.
    public static var swiftExtensions: Set<String> = {
        SupportedLanguageExtension.stringSet(swift)
    }()

    /// Returns a set of valid c extensions.
    public static var cExtensions: Set<String> = {
        SupportedLanguageExtension.stringSet(c, m)
    }()

    /// Returns a set of valid cpp extensions.
    public static var cppExtensions: Set<String> = {
        SupportedLanguageExtension.stringSet(mm, cc, cpp, cxx)
    }()

    /// Returns a set of valid c family extensions.
    public static var cFamilyExtensions: Set<String> = {
        cExtensions.union(cppExtensions)
    }()

    /// Returns a set of all file extensions we support.
    public static var validExtensions: Set<String> = {
        swiftExtensions.union(cFamilyExtensions)
    }()

    /// Converts array of LanguageExtension into a string set representation.
    ///
    /// - Parameters:
    ///     - extensions: Array of LanguageExtension to be converted to string set.
    ///
    /// - Returns: Set of strings.
    private static func stringSet(_ extensions: SupportedLanguageExtension...) -> Set<String> {
        return Set(extensions.map({ $0.rawValue }))
    }
}
