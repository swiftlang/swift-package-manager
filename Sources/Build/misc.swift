/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel

import func POSIX.getenv
import func POSIX.popen

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
    // Returns language specific arguments for a ClangModule.
    var languageLinkArgs: [String] {
        var args = [String]() 
        // Check if this module contains any cpp file.
        var linkCpp = self.containsCppFiles

        // Otherwise check if any of its dependencies contains a cpp file.
        // FIXME: It is expensive to iterate over all of the dependencies.
        // Figure out a way to cache this kind of lookups.
        if !linkCpp {
            for case let dep as ClangModule in recursiveDependencies {
                if dep.containsCppFiles {
                    linkCpp = true
                    break
                }
            }
        }
        // Link C++ if found any cpp source. 
        if linkCpp {
            args += ["-lstdc++"]
        }
        return args
    }

    var containsCppFiles: Bool {
        return sources.paths.contains { $0.isCpp }
    }
}
