//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

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
            return ext == SupportedLanguageExtension.m.rawValue || ext == SupportedLanguageExtension.mm.rawValue
        })
    }

    public var containsNonSwiftFiles: Bool {
        return paths.contains(where: {
            guard let ext = $0.extension else {
                return false
            }
            return !SupportedLanguageExtension.swiftExtensions.contains(ext)
        })
    }

    /// Returns true if the sources contain any Swift files.
    ///
    /// Note: the extension sets used here (`SupportedLanguageExtension`) are kept in sync
    /// with `FileRuleDescription.swift`/`.clang`/`.asm` in `PackageLoading`.
    public var hasSwiftSources: Bool {
        paths.contains { path in
            guard let ext = path.extension else { return false }
            return SupportedLanguageExtension.swiftExtensions.contains(ext)
        }
    }

    /// Returns true if the sources contain any C-family (C/C++/Objective-C) or assembly files.
    public var hasClangSources: Bool {
        let supportedClangFileExtensions = SupportedLanguageExtension.cExtensions
            .union(SupportedLanguageExtension.cppExtensions)
            .union(SupportedLanguageExtension.assemblyExtensions)
        return paths.contains { path in
            guard let ext = path.extension else { return false }
            return supportedClangFileExtensions.contains(ext)
        }
    }

    /// Returns true if the sources mix Swift and C-family sources.
    public var containsMixedLanguage: Bool {
        self.hasSwiftSources && self.hasClangSources
    }
}
