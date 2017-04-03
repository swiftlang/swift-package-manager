/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

public protocol Toolchain {
    /// Path of the `swiftc` compiler.
    var swiftCompiler: AbsolutePath { get }

    /// Platform-specific arguments for Swift compiler.
    var swiftPlatformArgs: [String] { get }

    /// Path of the `clang` compiler.
    var clangCompiler: AbsolutePath { get }

    /// Platform-specific arguments for Clang compiler.
    var clangPlatformArgs: [String] { get }

    /// Path of the default SDK (a.k.a. "sysroot"), if any.
    var defaultSDK: AbsolutePath? { get }
}

extension AbsolutePath {
    var isCpp: Bool {
        guard let ext = self.extension else {
            return false
        }
        return SupportedLanguageExtension.cppExtensions.contains(ext)
    }
}

extension ClangModule {
    var containsCppFiles: Bool {
        return sources.paths.contains { $0.isCpp }
    }
}
