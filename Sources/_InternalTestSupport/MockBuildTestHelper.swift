//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import struct PackageGraph.ModulesGraph
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedProduct
import PackageModel
import SPMBuildCore
import TSCUtility
import XCTest

public struct MockToolchain: PackageModel.Toolchain {
    #if os(Windows)
    public let librarianPath = AbsolutePath("/fake/path/to/link.exe")
    #elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
    public let librarianPath = AbsolutePath("/fake/path/to/libtool")
    #else
    public let librarianPath = AbsolutePath("/fake/path/to/llvm-ar")
    #endif
    public let swiftCompilerPath = AbsolutePath("/fake/path/to/swiftc")
    public let includeSearchPaths = [AbsolutePath]()
    public let librarySearchPaths = [AbsolutePath]()
    public let swiftResourcesPath: AbsolutePath?
    public let swiftStaticResourcesPath: AbsolutePath? = nil
    public let sdkRootPath: AbsolutePath? = nil
    public let extraFlags = PackageModel.BuildFlags()
    public let installedSwiftPMConfiguration = InstalledSwiftPMConfiguration.default
    public let swiftPMLibrariesLocation = ToolchainConfiguration.SwiftPMLibrariesLocation(
        manifestLibraryPath: AbsolutePath("/fake/manifestLib/path"), pluginLibraryPath: AbsolutePath("/fake/pluginLibrary/path")
    )

    public func getClangCompiler() throws -> AbsolutePath {
        "/fake/path/to/clang"
    }

    public func _isClangCompilerVendorApple() throws -> Bool? {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    public init(swiftResourcesPath: AbsolutePath? = nil) {
        self.swiftResourcesPath = swiftResourcesPath
    }
}

extension Basics.Triple {
    public static let x86_64MacOS = try! Self("x86_64-apple-macosx")
    public static let x86_64Linux = try! Self("x86_64-unknown-linux-gnu")
    public static let arm64Linux = try! Self("aarch64-unknown-linux-gnu")
    public static let arm64Android = try! Self("aarch64-unknown-linux-android")
    public static let windows = try! Self("x86_64-unknown-windows-msvc")
    public static let x86_64Windows = try! Self("x86_64-unknown-windows-msvc")
    public static let arm64Windows = try! Self("aarch64-unknown-windows-msvc")
    public static let wasi = try! Self("wasm32-unknown-wasi")
    public static let arm64iOS = try! Self("arm64-apple-ios")
}

public let hostTriple = try! UserToolchain.default.targetTriple
#if os(macOS)
public let defaultTargetTriple: String = hostTriple.tripleString(forPlatformVersion: "10.13")
#else
public let defaultTargetTriple: String = hostTriple.tripleString
#endif

public func mockBuildParameters(
    destination: BuildParameters.Destination,
    buildPath: AbsolutePath? = nil,
    config: BuildConfiguration = .debug,
    toolchain: PackageModel.Toolchain = MockToolchain(),
    flags: PackageModel.BuildFlags = PackageModel.BuildFlags(),
    buildSystemKind: BuildSystemProvider.Kind = .native,
    shouldLinkStaticSwiftStdlib: Bool = false,
    shouldDisableLocalRpath: Bool = false,
    canRenameEntrypointFunctionName: Bool = false,
    triple: Basics.Triple = hostTriple,
    indexStoreMode: BuildParameters.IndexStoreMode = .off,
    useExplicitModuleBuild: Bool = false,
    linkerDeadStrip: Bool = true,
    linkTimeOptimizationMode: BuildParameters.LinkTimeOptimizationMode? = nil,
    omitFramePointers: Bool? = nil,
    prepareForIndexing: BuildParameters.PrepareForIndexingMode = .off
) -> BuildParameters {
    try! BuildParameters(
        destination: destination,
        dataPath: buildPath ?? AbsolutePath("/path/to/build").appending(triple.tripleString),
        configuration: config,
        toolchain: toolchain,
        triple: triple,
        flags: flags,
        buildSystemKind: buildSystemKind,
        pkgConfigDirectories: [],
        workers: 3,
        indexStoreMode: indexStoreMode,
        prepareForIndexing: prepareForIndexing,
        debuggingParameters: .init(
            triple: triple,
            shouldEnableDebuggingEntitlement: config == .debug,
            omitFramePointers: omitFramePointers
        ),
        driverParameters: .init(
            canRenameEntrypointFunctionName: canRenameEntrypointFunctionName,
            useExplicitModuleBuild: useExplicitModuleBuild
        ),
        linkingParameters: .init(
            linkerDeadStrip: linkerDeadStrip,
            linkTimeOptimizationMode: linkTimeOptimizationMode,
            shouldDisableLocalRpath: shouldDisableLocalRpath,
            shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib
        )
    )
}

public func mockBuildParameters(
    destination: BuildParameters.Destination,
    environment: BuildEnvironment
) -> BuildParameters {
    let triple: Basics.Triple
    switch environment.platform {
    case .macOS:
        triple = Triple.x86_64MacOS
    case .linux:
        triple = Triple.arm64Linux
    case .android:
        triple = Triple.arm64Android
    case .windows:
        triple = Triple.windows
    default:
        fatalError("unsupported platform in tests")
    }

    return mockBuildParameters(
        destination: destination,
        config: environment.configuration ?? .debug,
        triple: triple
    )
}
