/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

/// A grouping of related source files.
public struct Sources: Codable {
    /// The root of the sources.
    public let root: AbsolutePath

    /// The subpaths within the root.
    public var relativePaths: [RelativePath]

    /// The list of absolute paths of all files.
    public var paths: [AbsolutePath] {
        return relativePaths.map({ root.appending($0) })
    }

    public init(paths: [AbsolutePath], root: AbsolutePath) {
        let relativePaths = paths.map({ $0.relative(to: root) })
        self.relativePaths = relativePaths.sorted(by: { $0.pathString < $1.pathString })
        self.root = root
    }

    /// Returns true if the sources contain C++ files.
    public var containsCXXFiles: Bool {
        return paths.contains(where: {
            guard let ext = $0.extension else {
                return false
            }
            return SupportedLanguageExtension.cppExtensions.contains(ext)
        })
    }

    /// Returns true if the sources contain C++ files.
    public var containsObjcFiles: Bool {
        return paths.contains(where: {
            guard let ext = $0.extension else {
                return false
            }
            return ext == SupportedLanguageExtension.m.rawValue
        })
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
    /// Assembly
    case s
    case S

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

    /// Returns a set of valid assembly file extensions.
    public static var assemblyExtensions: Set<String> = {
        SupportedLanguageExtension.stringSet(.s, .S)
    }()

    /// Returns a set of valid extensions in clang targets.
    public static func clangTargetExtensions(toolsVersion: ToolsVersion) -> Set<String> {
        var validExts = cExtensions.union(cppExtensions)
        if toolsVersion >= .v5 {
            validExts.formUnion(assemblyExtensions)
        }
        return validExts
    }

    /// Returns a set of all file extensions we support.
    public static func validExtensions(toolsVersion: ToolsVersion) -> Set<String> {
        return swiftExtensions.union(clangTargetExtensions(toolsVersion: toolsVersion))
    }

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
