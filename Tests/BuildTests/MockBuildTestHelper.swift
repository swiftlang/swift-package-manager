@testable import PackageModel
@testable import TSCUtility
@testable import Build
import Basics
import SPMBuildCore
import TSCBasic
import XCTest

struct MockToolchain: PackageModel.Toolchain {
#if os(Windows)
    let librarianPath = AbsolutePath(path: "/fake/path/to/link.exe")
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
    let librarianPath = AbsolutePath(path: "/fake/path/to/libtool")
#elseif os(Android)
    let librarianPath = AbsolutePath(path: "/fake/path/to/llvm-ar")
#else
    let librarianPath = AbsolutePath(path: "/fake/path/to/ar")
#endif
    let swiftCompilerPath = AbsolutePath(path: "/fake/path/to/swiftc")
    
    #if os(macOS)
    let extraFlags = BuildFlags(cxxCompilerFlags: ["-lc++"])
    #else
    let extraFlags = BuildFlags(cxxCompilerFlags: ["-lstdc++"])
    #endif
    func getClangCompiler() throws -> AbsolutePath {
        return AbsolutePath(path: "/fake/path/to/clang")
    }

    func _isClangCompilerVendorApple() throws -> Bool? {
      #if os(macOS)
        return true
      #else
        return false
      #endif
    }
}


extension TSCUtility.Triple {
    static let x86_64Linux = try! Triple("x86_64-unknown-linux-gnu")
    static let arm64Linux = try! Triple("aarch64-unknown-linux-gnu")
    static let arm64Android = try! Triple("aarch64-unknown-linux-android")
    static let windows = try! Triple("x86_64-unknown-windows-msvc")
    static let wasi = try! Triple("wasm32-unknown-wasi")
}

extension AbsolutePath {
    func escapedPathString() -> String {
        return self.pathString.replacingOccurrences(of: "\\", with: "\\\\")
    }
}

let hostTriple = try! UserToolchain.default.triple
#if os(macOS)
    let defaultTargetTriple: String = hostTriple.tripleString(forPlatformVersion: "10.13")
#else
    let defaultTargetTriple: String = hostTriple.tripleString
#endif

func mockBuildParameters(
    buildPath: AbsolutePath = AbsolutePath(path: "/path/to/build"),
    config: BuildConfiguration = .debug,
    toolchain: PackageModel.Toolchain = MockToolchain(),
    flags: PackageModel.BuildFlags = PackageModel.BuildFlags(),
    shouldLinkStaticSwiftStdlib: Bool = false,
    canRenameEntrypointFunctionName: Bool = false,
    destinationTriple: TSCUtility.Triple = hostTriple,
    indexStoreMode: BuildParameters.IndexStoreMode = .off,
    useExplicitModuleBuild: Bool = false,
    linkerDeadStrip: Bool = true
) -> BuildParameters {
    return BuildParameters(
        dataPath: buildPath,
        configuration: config,
        toolchain: toolchain,
        hostTriple: hostTriple,
        destinationTriple: destinationTriple,
        flags: flags,
        jobs: 3,
        shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
        canRenameEntrypointFunctionName: canRenameEntrypointFunctionName,
        indexStoreMode: indexStoreMode,
        useExplicitModuleBuild: useExplicitModuleBuild,
        linkerDeadStrip: linkerDeadStrip
    )
}

func mockBuildParameters(environment: BuildEnvironment) -> BuildParameters {
    let triple: TSCUtility.Triple
    switch environment.platform {
    case .macOS:
        triple = Triple.macOS
    case .linux:
        triple = Triple.arm64Linux
    case .android:
        triple = Triple.arm64Android
    case .windows:
        triple = Triple.windows
    default:
        fatalError("unsupported platform in tests")
    }

    return mockBuildParameters(config: environment.configuration, destinationTriple: triple)
}

enum BuildError: Swift.Error {
    case error(String)
}

struct BuildPlanResult {

    let plan: Build.BuildPlan
    let targetMap: [String: TargetBuildDescription]
    let productMap: [String: Build.ProductBuildDescription]

    init(plan: Build.BuildPlan) throws {
        self.plan = plan
        self.productMap = try Dictionary(throwingUniqueKeysWithValues: plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.map{ ($0.product.name, $0) })
        self.targetMap = try Dictionary(throwingUniqueKeysWithValues: plan.targetMap.map{ ($0.0.name, $0.1) })
    }

    func checkTargetsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.targetMap.count, count, file: file, line: line)
    }

    func checkProductsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.productMap.count, count, file: file, line: line)
    }

    func target(for name: String) throws -> TargetBuildDescription {
        guard let target = targetMap[name] else {
            throw BuildError.error("Target \(name) not found.")
        }
        return target
    }

    func buildProduct(for name: String) throws -> Build.ProductBuildDescription {
        guard let product = productMap[name] else {
            // <rdar://problem/30162871> Display the thrown error on macOS
            throw BuildError.error("Product \(name) not found.")
        }
        return product
    }
}

extension TargetBuildDescription {
    func swiftTarget() throws -> SwiftTargetBuildDescription {
        switch self {
        case .swift(let target):
            return target
        default:
            throw BuildError.error("Unexpected \(self) type found")
        }
    }

    func clangTarget() throws -> ClangTargetBuildDescription {
        switch self {
        case .clang(let target):
            return target
        default:
            throw BuildError.error("Unexpected \(self) type")
        }
    }
}
