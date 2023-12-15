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
import Build
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
    public let swiftResourcesPath: AbsolutePath? = nil
    public let swiftStaticResourcesPath: AbsolutePath? = nil
    public let isSwiftDevelopmentToolchain = false
    public let sdkRootPath: AbsolutePath? = nil
    public let swiftPluginServerPath: AbsolutePath? = nil
    public let extraFlags = PackageModel.BuildFlags()
    public let installedSwiftPMConfiguration = InstalledSwiftPMConfiguration.default

    public func getClangCompiler() throws -> AbsolutePath {
        return "/fake/path/to/clang"
    }

    public func _isClangCompilerVendorApple() throws -> Bool? {
      #if os(macOS)
        return true
      #else
        return false
      #endif
    }

    public init() {
    }
}


extension Basics.Triple {
    public static let x86_64MacOS = try! Self("x86_64-apple-macosx")
    public static let x86_64Linux = try! Self("x86_64-unknown-linux-gnu")
    public static let arm64Linux = try! Self("aarch64-unknown-linux-gnu")
    public static let arm64Android = try! Self("aarch64-unknown-linux-android")
    public static let windows = try! Self("x86_64-unknown-windows-msvc")
    public static let wasi = try! Self("wasm32-unknown-wasi")
}

public let hostTriple = try! UserToolchain.default.targetTriple
#if os(macOS)
public let defaultTargetTriple: String = hostTriple.tripleString(forPlatformVersion: "10.13")
#else
public let defaultTargetTriple: String = hostTriple.tripleString
#endif

public func mockBuildParameters(
    buildPath: AbsolutePath = "/path/to/build",
    config: BuildConfiguration = .debug,
    toolchain: PackageModel.Toolchain = MockToolchain(),
    flags: PackageModel.BuildFlags = PackageModel.BuildFlags(),
    shouldLinkStaticSwiftStdlib: Bool = false,
    shouldDisableLocalRpath: Bool = false,
    canRenameEntrypointFunctionName: Bool = false,
    targetTriple: Basics.Triple = hostTriple,
    indexStoreMode: BuildParameters.IndexStoreMode = .off,
    useExplicitModuleBuild: Bool = false,
    linkerDeadStrip: Bool = true,
    linkTimeOptimizationMode: BuildParameters.LinkTimeOptimizationMode? = nil,
    omitFramePointers: Bool? = nil
) -> BuildParameters {
    return try! BuildParameters(
        dataPath: buildPath,
        configuration: config,
        toolchain: toolchain,
        triple: targetTriple,
        flags: flags,
        pkgConfigDirectories: [],
        workers: 3,
        indexStoreMode: indexStoreMode,
        debuggingParameters: .init(
            triple: targetTriple,
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

public func mockBuildParameters(environment: BuildEnvironment) -> BuildParameters {
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

    return mockBuildParameters(config: environment.configuration ?? .debug, targetTriple: triple)
}

enum BuildError: Swift.Error {
    case error(String)
}

public struct BuildPlanResult {

    public let plan: Build.BuildPlan
    public let targetMap: [String: TargetBuildDescription]
    public let productMap: [String: Build.ProductBuildDescription]

    public init(plan: Build.BuildPlan) throws {
        self.plan = plan
        self.productMap = try Dictionary(throwingUniqueKeysWithValues: plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.map{ ($0.product.name, $0) })
        self.targetMap = try Dictionary(throwingUniqueKeysWithValues: plan.targetMap.map{ ($0.0.name, $0.1) })
    }

    public func checkTargetsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.targetMap.count, count, file: file, line: line)
    }

    public func checkProductsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.productMap.count, count, file: file, line: line)
    }

    public func target(for name: String) throws -> TargetBuildDescription {
        guard let target = targetMap[name] else {
            throw BuildError.error("Target \(name) not found.")
        }
        return target
    }

    public func buildProduct(for name: String) throws -> Build.ProductBuildDescription {
        guard let product = productMap[name] else {
            // <rdar://problem/30162871> Display the thrown error on macOS
            throw BuildError.error("Product \(name) not found.")
        }
        return product
    }
}

extension TargetBuildDescription {
    public func swiftTarget() throws -> SwiftTargetBuildDescription {
        switch self {
        case .swift(let target):
            return target
        default:
            throw BuildError.error("Unexpected \(self) type found")
        }
    }

    public func clangTarget() throws -> ClangTargetBuildDescription {
        switch self {
        case .clang(let target):
            return target
        default:
            throw BuildError.error("Unexpected \(self) type")
        }
    }
}
