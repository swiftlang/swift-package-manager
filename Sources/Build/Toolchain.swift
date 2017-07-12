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

    /// Path of the `clang` compiler.
    var clangCompiler: AbsolutePath { get }

    /// Additional flags to be passed to the C compiler.
    var extraCCFlags: [String] { get }

    /// Additional flags to be passed to the Swift compiler.
    var extraSwiftCFlags: [String] { get }

    /// Additional flags to be passed when compiling with C++.
    var extraCPPFlags: [String] { get }

    /// The dynamic library extension, for e.g. dylib, so.
    var dynamicLibraryExtension: String { get }
}
