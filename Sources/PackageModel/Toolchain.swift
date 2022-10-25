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

import TSCBasic

public protocol Toolchain {
    /// Path of the librarian.
    var librarianPath: AbsolutePath { get }

    /// Path of the `swiftc` compiler.
    var swiftCompilerPath: AbsolutePath { get }

    /// Path of the `swiftc` compiler to use for manifest compilation.
    var swiftCompilerPathForManifests: AbsolutePath { get }

    /// Path containing the macOS Swift stdlib.
    var macosSwiftStdlib: AbsolutePath { get throws }

    /// Path of the `clang` compiler.
    func getClangCompiler() throws -> AbsolutePath

    // FIXME: This is a temporary API until index store is widely available in
    // the OSS clang compiler. This API should not used for any other purpose.
    /// Returns true if clang compiler's vendor is Apple and nil if unknown.
    func _isClangCompilerVendorApple() throws -> Bool?
    
    /// Additional flags to be passed to the build tools.
    var extraFlags: BuildFlags { get }

    /// Additional flags to be passed to the C compiler.
    @available(*, deprecated, message: "use extraFlags.cCompilerFlags instead")
    var extraCCFlags: [String] { get }

    /// Additional flags to be passed to the Swift compiler.
    @available(*, deprecated, message: "use extraFlags.swiftCompilerFlags instead")
    var extraSwiftCFlags: [String] { get }

    /// Additional flags to be passed to the C++ compiler.
    @available(*, deprecated, message: "use extraFlags.cxxCompilerFlags instead")
    var extraCPPFlags: [String] { get }
}

extension Toolchain {
    public func _isClangCompilerVendorApple() throws -> Bool? {
        return nil
    }

    public var macosSwiftStdlib: AbsolutePath {
        get throws {
            return try AbsolutePath(validating: "../../lib/swift/macosx", relativeTo: resolveSymlinks(swiftCompilerPath))
        }
    }

    public var toolchainLibDir: AbsolutePath {
        get throws {
            // FIXME: Not sure if it's better to base this off of Swift compiler or our own binary.
            return try AbsolutePath(validating: "../../lib", relativeTo: resolveSymlinks(swiftCompilerPath))
        }
    }
    
    public var extraCCFlags: [String] {
        extraFlags.cCompilerFlags
    }
    
    public var extraCPPFlags: [String] {
        extraFlags.cxxCompilerFlags
    }
    
    public var extraSwiftCFlags: [String] {
        extraFlags.swiftCompilerFlags
    }

    private static func commandLineForCompilation(compilerPath: AbsolutePath, fileSystem: FileSystem) -> [String] {
        let swiftDriverPath = compilerPath.parentDirectory.appending(component: "swift-driver")
        if fileSystem.exists(swiftDriverPath) {
            return [swiftDriverPath.pathString, "--driver-mode=swiftc"]
        } else {
            return [compilerPath.pathString]
        }
    }

    public func commandLineForManifestCompilation(fileSystem: FileSystem) -> [String] {
        return Self.commandLineForCompilation(compilerPath: swiftCompilerPathForManifests, fileSystem: fileSystem)
    }

    public func commandLineForSwiftCompilation(fileSystem: FileSystem) -> [String] {
        return Self.commandLineForCompilation(compilerPath: swiftCompilerPath, fileSystem: fileSystem)
    }
}
