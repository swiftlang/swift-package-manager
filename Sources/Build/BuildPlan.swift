/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel
import PackageGraph
import PackageLoading
import func POSIX.getenv

public struct BuildParameters {

    /// Path to the module cache directory to use for SwiftPM's own tests.
    public static let swiftpmTestCache = resolveSymlinks(determineTempDirectory()).appending(component: "org.swift.swiftpm.tests-3")

    /// Returns the directory to be used for module cache.
    fileprivate var moduleCache: AbsolutePath {
        let base: AbsolutePath
        // FIXME: We use this hack to let swiftpm's functional test use shared
        // cache so it doesn't become painfully slow.
        if getenv("IS_SWIFTPM_TEST") != nil {
            base = BuildParameters.swiftpmTestCache
        } else {
            base = buildPath
        }
        return base.appending(component: "ModuleCache")
    }

    /// The path to the data directory.
    public let dataPath: AbsolutePath

    /// The build configuration.
    public let configuration: Configuration

    /// The path to the build directory (inside the data directory).
    public var buildPath: AbsolutePath {
        return dataPath.appending(component: configuration.dirname)
    }

    /// The toolchain.
    public let toolchain: Toolchain

    /// Extra build flags.
    public let flags: BuildFlags

    /// Extra flags to pass to Swift compiler.
    public var swiftCompilerFlags: [String] {
        var flags = self.flags.cCompilerFlags.flatMap({ ["-Xcc", $0] })
        flags += self.flags.swiftCompilerFlags
        flags += verbosity.ccArgs
        return flags
    }

    /// Extra flags to pass to linker.
    public var linkerFlags: [String] {
        return self.flags.linkerFlags.flatMap({ ["-Xlinker", $0] })
    }

    /// The tools version to use.
    public let toolsVersion: ToolsVersion

    /// If should link the Swift stdlib statically.
    public let shouldLinkStaticSwiftStdlib: Bool

    public init(
        dataPath: AbsolutePath,
        configuration: Configuration,
        toolchain: Toolchain,
        flags: BuildFlags,
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        shouldLinkStaticSwiftStdlib: Bool = false
    ) {
        self.dataPath = dataPath
        self.configuration = configuration
        self.toolchain = toolchain
        self.flags = flags
        self.toolsVersion = toolsVersion
        self.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
    }
}

/// A target description which can either be for a Swift or Clang target.
public enum TargetDescription {

    /// Swift target description.
    case swift(SwiftTargetDescription)

    /// Clang target description.
    case clang(ClangTargetDescription)

    /// The objects in this target.
    var objects: [AbsolutePath] {
        switch self {
        case .swift(let target):
            return target.objects
        case .clang(let target):
            return target.objects
        }
    }
}

/// Target description for a Clang target i.e. C language family target.
public final class ClangTargetDescription {

    /// The target described by this target.
    public let target: ResolvedTarget

    /// The underlying clang target.
    public var clangTarget: ClangTarget {
        return target.underlyingTarget as! ClangTarget
    }

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The modulemap file for this target, if any.
    private(set) var moduleMap: AbsolutePath?

    /// Path to the temporary directory for this target.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".build")
    }

    /// The objects in this target.
    var objects: [AbsolutePath] {
        return compilePaths().map({ $0.object })
    }

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The filesystem to operate on.
    let fileSystem: FileSystem

    /// If this target is a test target.
    public var isTestTarget: Bool {
        return target.type == .test
    }

    /// Create a new target description with target and build parameters.
    init(target: ResolvedTarget, buildParameters: BuildParameters, fileSystem: FileSystem = localFileSystem) throws {
        assert(target.underlyingTarget is ClangTarget, "underlying target type mismatch \(target)")
        self.fileSystem = fileSystem
        self.target = target
        self.buildParameters = buildParameters
        // Try computing modulemap path for a C library.
        if target.type == .library {
            self.moduleMap = try computeModulemapPath()
        }
    }

    /// An array of tuple containing filename, source, object and dependency path for each of the source in this target.
    public func compilePaths()
        -> [(filename: RelativePath, source: AbsolutePath, object: AbsolutePath, deps: AbsolutePath)]
    {
        return target.sources.relativePaths.map({ source in
            let path = target.sources.root.appending(source)
            let object = tempsPath.appending(RelativePath(source.asString + ".o"))
            let deps = tempsPath.appending(RelativePath(source.asString + ".d"))
            return (source, path, object, deps)
        })
    }

    /// Builds up basic compilation arguments for this target.
    public func basicArguments() -> [String] {
        var args = [String]()
        args += buildParameters.toolchain.extraCCFlags
        args += buildParameters.flags.cCompilerFlags
        args += optimizationArguments

        // Add extra C++ flags if this target contains C++ files.
        if clangTarget.isCXX {
            args += self.buildParameters.flags.cxxCompilerFlags
        }

        // Only enable ARC on macOS.
      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-fmodules", "-fmodule-name=" + target.c99name]
        if let languageStandard = clangTarget.languageStandard {
            args += ["-std=\(languageStandard)"]
        }
        args += ["-I", clangTarget.includeDir.asString]
        args += additionalFlags
        args += moduleCacheArgs
        return args
    }

    /// Optimization arguments according to the build configuration.
    private var optimizationArguments: [String] {
        switch buildParameters.configuration {
        case .debug:
            return ["-g", "-O0"]
        case .release:
            return ["-O2"]
        }
    }

    /// Helper function to compute the modulemap path.
    ///
    /// This function either returns path to user provided modulemap or tries to automatically generates it.
    private func computeModulemapPath() throws -> AbsolutePath {
        // If user provided the modulemap, we're done.
        if localFileSystem.isFile(clangTarget.moduleMapPath) {
            return clangTarget.moduleMapPath
        } else {
            // Otherwise try to generate one.
            var moduleMapGenerator = ModuleMapGenerator(for: clangTarget, fileSystem: fileSystem)
            // FIXME: We should probably only warn if we're unable to generate the modulemap
            // because the clang target is still a valid, it just can't be imported from Swift targets.
            try moduleMapGenerator.generateModuleMap(inDir: tempsPath)
            return tempsPath.appending(component: moduleMapFilename)
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        return ["-fmodules-cache-path=" + buildParameters.moduleCache.asString]
    }
}

/// Target description for a Swift target.
public final class SwiftTargetDescription {

    /// The target described by this target.
    public let target: ResolvedTarget

    /// The build parameters.
    let buildParameters: BuildParameters

    /// Path to the temporary directory for this target.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".build")
    }

    /// The objects in this target.
    var objects: [AbsolutePath] {
        return target.sources.relativePaths.map({ tempsPath.appending(RelativePath($0.asString + ".o")) })
    }

    /// The path to the swiftmodule file after compilation.
    var moduleOutputPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".swiftmodule")
    }

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The swift version for this target.
    var swiftVersion: Int {
        return (target.underlyingTarget as! SwiftTarget).swiftVersion
    }

    /// If this target is a test target.
    public let isTestTarget: Bool

    /// Create a new target description with target and build parameters.
    init(target: ResolvedTarget, buildParameters: BuildParameters, isTestTarget: Bool? = nil) {
        assert(target.underlyingTarget is SwiftTarget, "underlying target type mismatch \(target)")
        self.target = target
        self.buildParameters = buildParameters
        // Unless mentioned explicitly, use the target type to determine if this is a test target.
        self.isTestTarget = isTestTarget ?? (target.type == .test)
    }

    /// The arguments needed to compile this target.
    public func compileArguments() -> [String] {
        var args = [String]()
        args += ["-swift-version", String(swiftVersion)]
        args += buildParameters.toolchain.extraSwiftCFlags
        args += buildParameters.swiftCompilerFlags
        args += optimizationArguments
        args += ["-j\(SwiftCompilerTool.numThreads)", "-DSWIFT_PACKAGE"]
        args += additionalFlags
        args += moduleCacheArgs
        return args
    }

    /// Optimization arguments according to the build configuration.
    private var optimizationArguments: [String] {
        switch buildParameters.configuration {
        case .debug:
            return ["-Onone", "-g", "-enable-testing"]
        case .release:
            return ["-O"]
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        return ["-module-cache-path", buildParameters.moduleCache.asString]
    }
}

/// The build description for a product.
public final class ProductBuildDescription {

    /// The reference to the product.
    public let product: ResolvedProduct

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The path to the product binary produced.
    public var binary: AbsolutePath {
        return buildParameters.buildPath.appending(outname)
    }

    /// The output name of the product.
    public var outname: RelativePath {
        let name = product.name

        switch product.type {
        case .executable:
            return RelativePath(name)
        case .library(.static):
            return RelativePath("lib\(name).a")
        case .library(.dynamic):
            return RelativePath("lib\(name).\(self.buildParameters.toolchain.dynamicLibraryExtension)")
        case .library(.automatic):
            fatalError()
        case .test:
            let base = "\(name).xctest"
            #if os(macOS)
                return RelativePath("\(base)/Contents/MacOS/\(name)")
            #else
                return RelativePath(base)
            #endif
        }
    }

    /// The objects in this product.
    ///
    // Computed during build planning.
    fileprivate(set) var objects = SortedArray<AbsolutePath>()

    /// The dynamic libraries this product needs to link with.
    // Computed during build planning.
    fileprivate(set) var dylibs: [ProductBuildDescription] = []

    /// Any additional flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// Create a build description for a product.
    init(product: ResolvedProduct, buildParameters: BuildParameters) {
        assert(product.type != .library(.automatic), "Automatic type libraries should not be described.")
        self.product = product
        self.buildParameters = buildParameters
    }

    /// Strips the arguments which should *never* be passed to Swift compiler
    /// when we're linking the product.
    ///
    /// We might want to get rid of this method once Swift driver can strip the
    /// flags itself, <rdar://problem/31215562>.
    private func stripInvalidArguments(_ args: [String]) -> [String] {
        let invalidArguments: Set<String> = ["-wmo", "-whole-module-optimization"]
        return args.filter({ !invalidArguments.contains($0) })
    }

    /// The arguments to link and create this product.
    public func linkArguments() -> [String] {
        var args = [buildParameters.toolchain.swiftCompiler.asString]
        args += buildParameters.toolchain.extraSwiftCFlags
        args += buildParameters.linkerFlags
        args += stripInvalidArguments(buildParameters.swiftCompilerFlags)
        args += additionalFlags

        if buildParameters.configuration == .debug {
            args += ["-g"]
        }
        args += ["-L", buildParameters.buildPath.asString]
        args += ["-o", binary.asString]
        args += ["-module-name", product.name]
        args += dylibs.map({ "-l" + $0.product.name })

        switch product.type {
        case .library(.automatic):
            fatalError()
        case .library(.static):
            // No arguments for static libraries.
            return []
        case .test:
            // Test products are bundle on macOS, executable on linux.
          #if os(macOS)
            args += ["-Xlinker", "-bundle"]
          #else
            args += ["-emit-executable"]
          #endif
        case .library(.dynamic):
            args += ["-emit-library"]
        case .executable:
            // Link the Swift stdlib statically if requested.
            if buildParameters.shouldLinkStaticSwiftStdlib {
                // FIXME: This does not work for linux yet (SR-648).
              #if os(macOS)
                args += ["-static-stdlib"]
              #endif
            }
            args += ["-emit-executable"]
        }
      #if os(Linux)
        // On linux, set rpath such that dynamic libraries are looked up
        // adjacent to the product. This happens by default on macOS.
        args += ["-Xlinker", "-rpath=$ORIGIN"]
      #endif
        args += objects.map({ $0.asString })
        return args
    }
}

/// The delegate interface used by the build plan to report status information.
public protocol BuildPlanDelegate: class {

    /// The build plan emitted this warning.
    func warning(message: String)
}

/// A build plan for a package graph.
public class BuildPlan {

    public enum Error: Swift.Error {
        /// The linux main file is missing.
        case missingLinuxMain
    }

    /// The build parameters.
    public let buildParameters: BuildParameters

    /// The package graph.
    public let graph: PackageGraph

    /// The target build description map.
    public let targetMap: [ResolvedTarget: TargetDescription]

    /// The product build description map.
    public let productMap: [ResolvedProduct: ProductBuildDescription]

    /// The build targets.
    public var targets: AnySequence<TargetDescription> {
        return AnySequence(targetMap.values)
    }

    /// The products in this plan.
    public var buildProducts: AnySequence<ProductBuildDescription> {
        return AnySequence(productMap.values)
    }

    /// Build plan delegate.
    public let delegate: BuildPlanDelegate?

    /// The filesystem to operate on.
    let fileSystem: FileSystem

    /// Create a build plan with build parameters and a package graph.
    public init(
        buildParameters: BuildParameters,
        graph: PackageGraph,
        delegate: BuildPlanDelegate? = nil,
        fileSystem: FileSystem = localFileSystem
    ) throws {
        self.fileSystem = fileSystem
        self.buildParameters = buildParameters
        self.graph = graph
        self.delegate = delegate

        // Create build target description for each target which we need to plan.
        var targetMap = [ResolvedTarget: TargetDescription]()
        for target in graph.targets {
             switch target.underlyingTarget {
             case is SwiftTarget:
                 targetMap[target] = .swift(SwiftTargetDescription(target: target, buildParameters: buildParameters))
             case is ClangTarget:
                targetMap[target] = try .clang(ClangTargetDescription(
                    target: target,
                    buildParameters: buildParameters,
                    fileSystem: fileSystem))
             case is CTarget:
                 break
             default:
                 fatalError("unhandled \(target.underlyingTarget)")
             }
        }

      #if os(Linux)
        // FIXME: Create a target for LinuxMain file on linux.
        // This will go away once it is possible to auto detect tests.
        let testProducts = graph.products.filter({ $0.type == .test })
        if testProducts.count > 1 {
            fatalError("It is not possible to have multiple test products on linux \(testProducts)")
        }

        for product in testProducts {
            guard let linuxMainTarget = product.linuxMainTarget else {
                throw Error.missingLinuxMain
            }
            let target = SwiftTargetDescription(
                target: linuxMainTarget, buildParameters: buildParameters, isTestTarget: true)
            targetMap[linuxMainTarget] = .swift(target)
        }
      #endif

        var productMap: [ResolvedProduct: ProductBuildDescription] = [:]
        // Create product description for each product we have in the package graph except
        // for automatic libraries because they don't produce any output.
        for product in graph.products where product.type != .library(.automatic) {
            productMap[product] = ProductBuildDescription(
                product: product, buildParameters: buildParameters)
        }

        self.productMap = productMap
        self.targetMap = targetMap
        // Finally plan these targets.
        try plan()
    }

    /// Plan the targets and products.
    private func plan() throws {
        // Plan targets.
        for buildTarget in targets {
            switch buildTarget {
            case .swift(let target):
                try plan(swiftTarget: target)
            case .clang(let target):
                plan(clangTarget: target)
            }
        }

        // Plan products.
        for buildProduct in buildProducts {
            plan(buildProduct)
        }
        // FIXME: We need to find out if any product has a target on which it depends 
        // both static and dynamically and then issue a suitable diagnostic or auto
        // handle that situation.
    }

    /// Plan a product.
    private func plan(_ buildProduct: ProductBuildDescription) {
        // Compute the product's dependency.
        let dependencies = computeDependencies(of: buildProduct.product)
        // Add flags for system targets.
        for systemModule in dependencies.systemModules {
            guard case let target as CTarget = systemModule.underlyingTarget else {
                fatalError("This should not be possible.")
            }
            // Add pkgConfig libs arguments.
            buildProduct.additionalFlags += pkgConfig(for: target).libs
        }

        // Link C++ if needed.
        // Note: This will come from build settings in future.
        for target in dependencies.staticTargets {
            if case let target as ClangTarget = target.underlyingTarget, target.isCXX {
                buildProduct.additionalFlags += self.buildParameters.toolchain.extraCPPFlags
                break
            }
        }

        buildProduct.dylibs = dependencies.dylibs.map({ productMap[$0]! })
        buildProduct.objects += dependencies.staticTargets.flatMap({ targetMap[$0]!.objects })
    }

    /// Computes the dependencies of a product.
    private func computeDependencies(
        of product: ResolvedProduct
    ) -> (
        dylibs: [ResolvedProduct],
        staticTargets: [ResolvedTarget],
        systemModules: [ResolvedTarget]
    ) {

        // Sort the product targets in topological order.
        let nodes = product.targets.map(ResolvedTarget.Dependency.target)
        let allTargets = try! topologicalSort(nodes, successors: { dependency in
            switch dependency {
            // Include all the depenencies of a target.
            case .target(let target):
                return target.dependencies

            // For a product dependency, we only include its content only if we
            // need to statically link it.
            case .product(let product):
                switch product.type {
                case .library(.automatic), .library(.static):
                    return product.targets.map(ResolvedTarget.Dependency.target)
                case .library(.dynamic), .test, .executable:
                    return []
                }
            }
        })

        // Create empty arrays to collect our results.
        var linkLibraries = [ResolvedProduct]()
        var staticTargets = [ResolvedTarget]()
        var systemModules = [ResolvedTarget]()

        for dependency in allTargets {
            switch dependency {
            case .target(let target):
                switch target.type {
                // Include executable and tests only if they're top level contents 
                // of the product. Otherwise they are just build time dependency.
                case .executable, .test:
                    if product.targets.contains(target) {
                        staticTargets.append(target)
                    }
                // Library targets should always be included.
                case .library:
                    staticTargets.append(target)
                // Add system target targets to system targets array.
                case .systemModule:
                    systemModules.append(target)
                }

            case .product(let product):
                // Add the dynamic products to array of libraries to link.
                if product.type == .library(.dynamic) {
                    linkLibraries.append(product)
                }
            }
        }

      #if os(Linux)
        if product.type == .test {
            product.linuxMainTarget.map({ staticTargets.append($0) })
        }
      #endif

        return (linkLibraries, staticTargets, systemModules)
    }

    /// Plan a Clang target.
    private func plan(clangTarget: ClangTargetDescription) {
        for dependency in clangTarget.target.recursiveDependencies {
            switch dependency.underlyingTarget {
            case let target as ClangTarget where target.type == .library:
                // Setup search paths for C dependencies:
                // Add `-iquote` for dependencies in the package (#include "...").
                // Add `-I` for dependencies outside the package (#include <...>).
                let includeFlag = graph.isInRootPackages(dependency) ? "-iquote" : "-I"
                clangTarget.additionalFlags += [includeFlag, target.includeDir.asString]
            case let target as CTarget:
                clangTarget.additionalFlags += ["-fmodule-map-file=\(target.moduleMapPath.asString)"]
                clangTarget.additionalFlags += pkgConfig(for: target).cFlags
            default: continue
            }
        }
    }

    /// Plan a Swift target.
    private func plan(swiftTarget: SwiftTargetDescription) throws {
        // We need to iterate recursive dependencies because Swift compiler needs to see all the targets a target
        // depends on.
        for dependency in swiftTarget.target.recursiveDependencies {
            switch dependency.underlyingTarget {
            case let underlyingTarget as ClangTarget where underlyingTarget.type == .library:
                guard case let .clang(target)? = targetMap[dependency] else {
                    fatalError("unexpected clang target \(underlyingTarget)")
                }
                // Add the path to modulemap of the dependency. Currently we require that all Clang targets have a
                // modulemap but we may want to remove that requirement since it is valid for a target to exist without
                // one. However, in that case it will not be importable in Swift targets. We may want to emit a warning
                // in that case from here.
                guard let moduleMap = target.moduleMap else { break }
                swiftTarget.additionalFlags += [
                    "-Xcc", "-fmodule-map-file=\(moduleMap.asString)",
                    "-I", target.clangTarget.includeDir.asString,
                ]
            case let target as CTarget:
                swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(target.moduleMapPath.asString)"]
                swiftTarget.additionalFlags += pkgConfig(for: target).cFlags
            default: break
            }
        }
    }

    /// Get pkgConfig arguments for a CTarget.
    private func pkgConfig(for target: CTarget) -> (cFlags: [String], libs: [String]) {
        // If we already have these flags, we're done.
        if let flags = pkgConfigCache[target] {
            return flags
        }
        // Otherwise, get the result and cache it.
        guard let result = pkgConfigArgs(for: target) else {
            pkgConfigCache[target] = ([], [])
            return pkgConfigCache[target]!
        }
        // If there is no pc file on system and we have an available provider, emit a warning.
        if let provider = result.provider, result.couldNotFindConfigFile {
            delegate?.warning(message: "you may be able to install \(result.pkgConfigName) using your system-packager:")
            delegate?.warning(message: provider.installText)
        } else if let error = result.error {
            delegate?.warning(message: "error while trying to use pkgConfig flags for \(target.name): \(error)")
        }
        pkgConfigCache[target] = (result.cFlags, result.libs)
        return pkgConfigCache[target]!
    }

    /// Cache for pkgConfig flags.
    private var pkgConfigCache = [CTarget: (cFlags: [String], libs: [String])]()
}
