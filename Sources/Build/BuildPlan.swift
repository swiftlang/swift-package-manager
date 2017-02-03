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
        var flags = self.flags.cCompilerFlags.flatMap{ ["-Xcc", $0] }
        flags += self.flags.swiftCompilerFlags
        flags += verbosity.ccArgs
        return flags
    }

    /// Extra flags to pass to linker.
    public var linkerFlags: [String] {
        return self.flags.linkerFlags.flatMap{ ["-Xlinker", $0] }
    }
    
    public init(dataPath: AbsolutePath, configuration: Configuration, toolchain: Toolchain, flags: BuildFlags) {
        self.dataPath = dataPath
        self.configuration = configuration
        self.toolchain = toolchain
        self.flags = flags
    }
}

/// A target description which can either be for a Swift or Clang module.
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

/// Target description for a Clang module i.e. C language family module.
public final class ClangTargetDescription {

    /// The module described by this target.
    public let module: ResolvedModule

    /// The underlying clang module.
    public var clangModule: ClangModule {
        return module.underlyingModule as! ClangModule
    }

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The modulemap file for this target, if any.
    private(set) var moduleMap: AbsolutePath?

    /// Path to the temporary directory for this target.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: module.c99name + ".build")
    }

    /// The objects in this target.
    var objects: [AbsolutePath] { 
        return compilePaths().map{$0.object} 
    }

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The filesystem to operate on.
    let fileSystem: FileSystem
    
    /// Create a new target description with module and build parameters.
    init(module: ResolvedModule, buildParameters: BuildParameters, fileSystem: FileSystem = localFileSystem) throws {
        assert(module.underlyingModule is ClangModule, "underlying module type mismatch \(module)")
        self.fileSystem = fileSystem
        self.module = module
        self.buildParameters = buildParameters 
        // Try computing modulemap path for a C library.
        if module.type == .library {
            self.moduleMap = try computeModulemapPath()
        }
    }

    /// An array of tuple containing filename, source, object and dependency path for each of the source in this target.
    public func compilePaths() -> [(filename: RelativePath, source: AbsolutePath, object: AbsolutePath, deps: AbsolutePath)] {
        return module.sources.relativePaths.map { source in
            let path = module.sources.root.appending(source)
            let object = tempsPath.appending(RelativePath(source.asString + ".o"))
            let deps = tempsPath.appending(RelativePath(source.asString + ".d"))
            return (source, path, object, deps)
        }
    }

    /// Builds up basic compilation arguments for this target.
    public func basicArguments() -> [String] {
        var args = [String]()
        args += buildParameters.toolchain.clangPlatformArgs
        args += buildParameters.flags.cCompilerFlags
        args += optimizationArguments
        args += ["-fobjc-arc", "-fmodules", "-fmodule-name=" + module.c99name]
        args += ["-I", clangModule.includeDir.asString]
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
        if localFileSystem.isFile(clangModule.moduleMapPath) {
            return clangModule.moduleMapPath
        } else {
            // Otherwise try to generate one.
            var moduleMapGenerator = ModuleMapGenerator(for: clangModule, fileSystem: fileSystem)
            // FIXME: We should probably only warn if we're unable to generate the modulemap
            // because the clang target is still a valid, it just can't be imported from Swift modules.
            try moduleMapGenerator.generateModuleMap(inDir: tempsPath)
            return tempsPath.appending(component: moduleMapFilename)
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        // FIXME: We use this hack to let swiftpm's functional test use shared cache so it doesn't become painfully slow.
        if getenv("IS_SWIFTPM_TEST") != nil { return [] }
        let moduleCachePath = buildParameters.buildPath.appending(component: "ModuleCache")
        return ["-fmodules-cache-path=" + moduleCachePath.asString]
    }
}

/// Target description for a Swift module.
public final class SwiftTargetDescription {

    /// The module described by this target.
    public let module: ResolvedModule

    /// The build parameters.
    let buildParameters: BuildParameters

    /// Path to the temporary directory for this target.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: module.c99name + ".build")
    }

    /// The objects in this target.
    var objects: [AbsolutePath] {
        return module.sources.relativePaths.map{ tempsPath.appending(RelativePath($0.asString + ".o")) }
    }

    /// The path to the swiftmodule file after compilation.
    var moduleOutputPath: AbsolutePath { 
        return buildParameters.buildPath.appending(component: module.c99name + ".swiftmodule") 
    }

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// Create a new target description with module and build parameters.
    init(module: ResolvedModule, buildParameters: BuildParameters) {
        assert(module.underlyingModule is SwiftModule, "underlying module type mismatch \(module)")
        self.module = module
        self.buildParameters = buildParameters
    }

    /// The arguments needed to compile this target.
    public func compileArguments() -> [String] {
        var args = [String]()
        args += buildParameters.toolchain.swiftPlatformArgs
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
        // FIXME: We use this hack to let swiftpm's functional test use shared cache so it doesn't become painfully slow.
        if getenv("IS_SWIFTPM_TEST") != nil { return [] }
        let moduleCachePath = buildParameters.buildPath.appending(component: "ModuleCache")
        return ["-module-cache-path", moduleCachePath.asString]
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
        return buildParameters.buildPath.appending(product.outname)
    }

    /// The objects in this product.
    let objects: [AbsolutePath]

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// Create a build description for a product.
    init(product: ResolvedProduct, objects: [AbsolutePath], buildParameters: BuildParameters) {
        self.product = product
        self.buildParameters = buildParameters
        self.objects = objects
    }

    /// The arguments to link and create this product.
    public func linkArguments() -> [String] {
        var args = [buildParameters.toolchain.swiftCompiler.asString]
        args += buildParameters.toolchain.swiftPlatformArgs
        args += buildParameters.linkerFlags
        args += buildParameters.swiftCompilerFlags
        args += additionalFlags

        if buildParameters.configuration == .debug {
            args += ["-g"]
        }
        args += ["-L", buildParameters.buildPath.asString]
        args += ["-o", binary.asString]
        args += ["-module-name", product.name]

        switch product.type {
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
            args += ["-emit-executable"]
        }
        args += objects.map{$0.asString}
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

    /// The build parameters.
    public let buildParameters: BuildParameters

    /// The package graph.
    public let graph: PackageGraph

    /// The target build description map.
    public let targetMap: [ResolvedModule: TargetDescription]

    /// The build targets.
    public var targets: AnySequence<TargetDescription> {
        return AnySequence(targetMap.values)
    }

    /// The products in this plan.
    public let buildProducts: [ProductBuildDescription]

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

        // Create build target description for each module which we need to plan.
        var targetMap = [ResolvedModule: TargetDescription]()
        for module in graph.modules {
             switch module.underlyingModule {
             case is SwiftModule:
                 targetMap[module] = .swift(SwiftTargetDescription(module: module, buildParameters: buildParameters))
             case is ClangModule:
                 let target = try ClangTargetDescription(module: module, buildParameters: buildParameters, fileSystem: fileSystem)
                 targetMap[module] = .clang(target)
             case is CModule:
                 break
             default:
                 fatalError("unhandled \(module.underlyingModule)")
             }
        }

        // Create product description for each product we have in the package graph.
        self.buildProducts = graph.products.map { product in
            // Collect all library objects.
            var objects = product.allModules.filter{ $0.type == .library }.flatMap{ targetMap[$0]!.objects }

            // Add objects from main module, if product is an executable.
            if product.type == .executable {
                // FIXME: This should come from product type enum instead of manual search.
                let mainModule = product.modules.first{$0.type == .executable}!
                objects += targetMap[mainModule]!.objects
            }

          #if os(Linux)
            // FIXME: Create a module and target for LinuxMain file on linux.
            // This module just contains one source file (LinuxMain.swift) which acts as manifest to the tests on linux.
            // This will go away once it is possible to auto detect tests.
            if product.type == .test {
                let resolvedModule = ResolvedModule(
                    module: SwiftModule(
                        linuxMain: product.linuxMainTest,
                        name: product.name,
                        dependencies: product.underlyingProduct.modules),
                    dependencies: product.modules)
                let target = SwiftTargetDescription(module: resolvedModule, buildParameters: buildParameters)
                targetMap[resolvedModule] = .swift(target)
                objects += target.objects
            }
          #endif
            return ProductBuildDescription(product: product, objects: objects, buildParameters: buildParameters)
        }

        self.targetMap = targetMap
        // Finally plan these targets.
        plan()
    }

    /// Plan the targets and products.
    private func plan() {
        // Plan targets.
        for buildTarget in targets {
            switch buildTarget {
            case .swift(let target):
                plan(swiftTarget: target)
            case .clang(let target):
                plan(clangTarget: target)
            }
        }

        // Plan products.
        for buildProduct in buildProducts {
            var linkCpp = false

            for module in buildProduct.product.allModules {
                switch module.underlyingModule {
                case let module as CModule:
                    // Add pkgConfig libs arguments.
                    buildProduct.additionalFlags += pkgConfig(for: module).libs
                case let module as ClangModule:
                    if module.containsCppFiles {
                        linkCpp = true
                    }
                default: break
                }
            }
            // Link C++ if needed.
            // Note: This will come from build settings in future.
            if linkCpp {
              #if os(macOS)
                buildProduct.additionalFlags += ["-lc++"]
              #else
                buildProduct.additionalFlags += ["-lstdc++"]
              #endif
            }
        }
    }

    /// Plan a Clang target.
    private func plan(clangTarget: ClangTargetDescription) {
        for dependency in clangTarget.module.dependencies {
            switch dependency.underlyingModule {
            case let module as ClangModule where module.type == .library:
                // Setup search paths for C dependencies:
                // Add `-iquote` for dependencies in the package (#include "...").
                // Add `-I` for dependencies outside the package (#include <...>).
                let includeFlag = graph.isInRootPackages(dependency) ? "-iquote" : "-I"
                clangTarget.additionalFlags += [includeFlag, module.includeDir.asString]
            case let module as CModule:
                clangTarget.additionalFlags += ["-fmodule-map-file=\(module.moduleMapPath.asString)"]
                clangTarget.additionalFlags += pkgConfig(for: module).cFlags
            default: continue
            }
        }
    }

    /// Plan a Swift target.
    private func plan(swiftTarget: SwiftTargetDescription) {
        // We need to iterate recursive dependencies because Swift compiler needs to see all the modules a target depends on.
        for dependency in swiftTarget.module.recursiveDependencies {
            switch dependency.underlyingModule {
            case let module as ClangModule where module.type == .library:
                guard case let .clang(target)? = targetMap[dependency] else { fatalError("unexpected clang module \(module)") }
                // Add the path to modulemap of the dependency. Currently we require that all Clang modules have a modulemap
                // but we may want to remove that requirement since it is valid for a module to exist without one. However,
                // in that case it will not be importable in Swift modules. We may want to emit a warning in that case from here.
                guard let moduleMap = target.moduleMap else { break }
                swiftTarget.additionalFlags += [
                    "-Xcc", "-fmodule-map-file=\(moduleMap.asString)",
                    "-I", target.clangModule.includeDir.asString
                ]
            case let module as CModule:
                swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(module.moduleMapPath.asString)"]
                swiftTarget.additionalFlags += pkgConfig(for: module).cFlags
            default: break
            }
        }
    }

    /// Get pkgConfig arguments for a CModule.
    private func pkgConfig(for module: CModule) -> (cFlags: [String], libs: [String]) {
        // If we already have these flags, we're done.
        if let flags = pkgConfigCache[module] {
            return flags
        }
        // Otherwise, get the result and cache it.
        guard let result = pkgConfigArgs(for: module) else {
            pkgConfigCache[module] = ([], [])
            return pkgConfigCache[module]!
        }
        // If there is no pc file on system and we have an available provider, emit a warning.
        if let provider = result.provider, result.noPcFile {
            delegate?.warning(message: "you may be able to install \(result.pkgConfigName) using your system-packager:")
            delegate?.warning(message: provider.installText)
        } else if let error = result.error {
            delegate?.warning(message: "error while trying to use pkgConfig flags for \(module.name): \(error)")
        }
        pkgConfigCache[module] = (result.cFlags, result.libs)
        return pkgConfigCache[module]!
    }
    
    /// Cache for pkgConfig flags.
    private var pkgConfigCache = [CModule: (cFlags: [String], libs: [String])]()
}
