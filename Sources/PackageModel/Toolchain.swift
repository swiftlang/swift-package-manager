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

public protocol Toolchain {
    /// Path of the librarian.
    var librarianPath: AbsolutePath { get }

    /// Path of the `swiftc` compiler.
    var swiftCompilerPath: AbsolutePath { get }

    /// Path to `lib/swift`
    var swiftResourcesPath: AbsolutePath? { get }

    /// Path to `lib/swift_static`
    var swiftStaticResourcesPath: AbsolutePath? { get }

    /// Path containing the macOS Swift stdlib.
    var macosSwiftStdlib: AbsolutePath { get throws }

    /// An array of paths to search for headers and modules at compile time.
    var includeSearchPaths: [AbsolutePath] { get }

    /// An array of paths to search for libraries at link time.
    var librarySearchPaths: [AbsolutePath] { get }

    /// Configuration from the used toolchain.
    var installedSwiftPMConfiguration: InstalledSwiftPMConfiguration { get }

    /// The root path to the Swift SDK used by this toolchain.
    var sdkRootPath: AbsolutePath? { get }

    /// The manifest and library locations used by this toolchain.
    var swiftPMLibrariesLocation: ToolchainConfiguration.SwiftPMLibrariesLocation { get }

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

    public var hostLibDir: AbsolutePath {
        get throws {
            try Self.toolchainLibDir(swiftCompilerPath: self.swiftCompilerPath).appending(
                components: ["swift", "host"]
            )
        }
    }

    public var macosSwiftStdlib: AbsolutePath {
        get throws {
            try Self.toolchainLibDir(swiftCompilerPath: self.swiftCompilerPath).appending(
                components: ["swift", "macosx"]
            )
        }
    }

    public var toolchainLibDir: AbsolutePath {
        get throws {
            // FIXME: Not sure if it's better to base this off of Swift compiler or our own binary.
            try Self.toolchainLibDir(swiftCompilerPath: self.swiftCompilerPath)
        }
    }

    /// Returns the appropriate Swift resources directory path.
    ///
    /// - Parameter static: Controls whether to use the static or dynamic
    /// resources directory.
    public func swiftResourcesPath(isStatic: Bool) -> AbsolutePath? {
        isStatic ? swiftStaticResourcesPath : swiftResourcesPath
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

    package static func toolchainLibDir(swiftCompilerPath: AbsolutePath) throws -> AbsolutePath {
        try AbsolutePath(validating: "../../lib", relativeTo: resolveSymlinks(swiftCompilerPath))
    }
}
