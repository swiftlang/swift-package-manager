/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

public protocol Toolchain {
    /// Path of the `swiftc` compiler.
    var swiftCompiler: AbsolutePath { get }

    /// Path containing the macOS Swift stdlib.
    var macosSwiftStdlib: AbsolutePath { get }

    /// Path of the `clang` compiler.
    func getClangCompiler() throws -> AbsolutePath

    // FIXME: This is a temporary API until index store is widely available in
    // the OSS clang compiler. This API should not used for any other purpose.
    /// Returns true if clang compiler's vendor is Apple and nil if unknown.
    func _isClangCompilerVendorApple() throws -> Bool?

    /// Additional flags to be passed to the C compiler.
    var extraCCFlags: [String] { get }

    /// Additional flags to be passed to the Swift compiler.
    var extraSwiftCFlags: [String] { get }

    /// Additional flags to be passed when compiling with C++.
    var extraCPPFlags: [String] { get }
}

extension Toolchain {
    public func _isClangCompilerVendorApple() throws -> Bool? {
        return nil
    }

    public var macosSwiftStdlib: AbsolutePath { 
        return resolveSymlinks(swiftCompiler).appending(RelativePath("../../lib/swift/macosx"))
    }

    public var toolchainLibDir: AbsolutePath {
        // FIXME: Not sure if it's better to base this off of Swift compiler or our own binary.
        return resolveSymlinks(swiftCompiler).appending(RelativePath("../../lib"))
    }
}
