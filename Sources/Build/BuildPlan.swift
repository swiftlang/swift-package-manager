//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import LLBuildManifest
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
@_implementationOnly import SwiftDriver
import TSCBasic

import enum TSCUtility.Diagnostics
import var TSCUtility.verbosity

extension String {
    var asSwiftStringLiteralConstant: String {
        return unicodeScalars.reduce("", { $0 + $1.escaped(asASCII: false) })
    }
}

extension AbsolutePath {
    internal func nativePathString(escaped: Bool) -> String {
        return URL(fileURLWithPath: self.pathString).withUnsafeFileSystemRepresentation {
            let repr = String(cString: $0!)
            if escaped {
                return repr.replacingOccurrences(of: "\\", with: "\\\\")
            }
            return repr
        }
    }
}

extension BuildParameters {
    /// Returns the directory to be used for module cache.
    public var moduleCache: AbsolutePath {
        get throws {
            // FIXME: We use this hack to let swiftpm's functional test use shared
            // cache so it doesn't become painfully slow.
            if let path = ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] {
                return try AbsolutePath(validating: path)
            }
            return buildPath.appending("ModuleCache")
        }
    }

    /// Extra flags to pass to Swift compiler.
    public var swiftCompilerFlags: [String] {
        var flags = self.flags.cCompilerFlags.flatMap({ ["-Xcc", $0] })
        flags += self.flags.swiftCompilerFlags
        if self.verboseOutput {
            flags.append("-v")
        }
        return flags
    }

    /// Extra flags to pass to linker.
    public var linkerFlags: [String] {
        // Arguments that can be passed directly to the Swift compiler and
        // doesn't require -Xlinker prefix.
        //
        // We do this to avoid sending flags like linker search path at the end
        // of the search list.
        let directSwiftLinkerArgs = ["-L"]

        var flags: [String] = []
        var it = self.flags.linkerFlags.makeIterator()
        while let flag = it.next() {
            if directSwiftLinkerArgs.contains(flag) {
                // `-L <value>` variant.
                flags.append(flag)
                guard let nextFlag = it.next() else {
                    // We expected a flag but don't have one.
                    continue
                }
                flags.append(nextFlag)
            } else if directSwiftLinkerArgs.contains(where: { flag.hasPrefix($0) }) {
                // `-L<value>` variant.
                flags.append(flag)
            } else {
                flags += ["-Xlinker", flag]
            }
        }
        return flags
    }

    /// Returns the compiler arguments for the index store, if enabled.
    func indexStoreArguments(for target: ResolvedTarget) -> [String] {
        let addIndexStoreArguments: Bool
        switch indexStoreMode {
        case .on:
            addIndexStoreArguments = true
        case .off:
            addIndexStoreArguments = false
        case .auto:
            if configuration == .debug {
                addIndexStoreArguments = true
            } else if target.type == .test {
                // Test discovery requires an index store for the test target to discover the tests
                addIndexStoreArguments = true
            } else {
                addIndexStoreArguments = false
            }
        }

        if addIndexStoreArguments {
            return ["-index-store-path", indexStore.pathString]
        }
        return []
    }

    /// Computes the target triple arguments for a given resolved target.
    public func targetTripleArgs(for target: ResolvedTarget) throws -> [String] {
        var args = ["-target"]
        // Compute the triple string for Darwin platform using the platform version.
        if triple.isDarwin() {
            guard let macOSSupportedPlatform = target.platforms.getDerived(for: .macOS) else {
                throw StringError("the target \(target) doesn't support building for macOS")
            }
            args += [triple.tripleString(forPlatformVersion: macOSSupportedPlatform.version.versionString)]
        } else {
            args += [triple.tripleString]
        }
        return args
    }

    /// Computes the linker flags to use in order to rename a module-named main function to 'main' for the target platform, or nil if the linker doesn't support it for the platform.
    func linkerFlagsForRenamingMainFunction(of target: ResolvedTarget) -> [String]? {
        let args: [String]
        if self.triple.isDarwin() {
            args = ["-alias", "_\(target.c99name)_main", "_main"]
        }
        else if self.triple.isLinux() {
            args = ["--defsym", "main=\(target.c99name)_main"]
        }
        else {
            return nil
        }
        return args.flatMap { ["-Xlinker", $0] }
    }

    /// Returns the scoped view of build settings for a given target.
    func createScope(for target: ResolvedTarget) -> BuildSettings.Scope {
        return BuildSettings.Scope(target.underlyingTarget.buildSettings, environment: buildEnvironment)
    }
}

/// A build plan for a package graph.
public class BuildPlan: SPMBuildCore.BuildPlan {

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        /// There is no buildable target in the graph.
        case noBuildableTarget

        public var description: String {
            switch self {
            case .noBuildableTarget:
                return """
                The package does not contain a buildable target. 
                Add at least one `.target` or `.executableTarget` to your `Package.swift`.
                """
            }
        }
    }

    /// The build parameters.
    public let buildParameters: BuildParameters

    /// The build environment.
    private var buildEnvironment: BuildEnvironment {
        buildParameters.buildEnvironment
    }

    /// The package graph.
    public let graph: PackageGraph

    /// The target build description map.
    public let targetMap: [ResolvedTarget: TargetBuildDescription]

    /// The product build description map.
    public let productMap: [ResolvedProduct: ProductBuildDescription]

    /// The plugin descriptions. Plugins are represented in the package graph
    /// as targets, but they are not directly included in the build graph.
    public let pluginDescriptions: [PluginDescription]

    /// The build targets.
    public var targets: AnySequence<TargetBuildDescription> {
        return AnySequence(targetMap.values)
    }

    /// The products in this plan.
    public var buildProducts: AnySequence<SPMBuildCore.ProductBuildDescription> {
        return AnySequence(productMap.values.map { $0 as SPMBuildCore.ProductBuildDescription })
    }

    /// The results of invoking any build tool plugins used by targets in this build.
    public let buildToolPluginInvocationResults: [ResolvedTarget: [BuildToolPluginInvocationResult]]

    /// The results of running any prebuild commands for the targets in this build.  This includes any derived
    /// source files as well as directories to which any changes should cause us to reevaluate the build plan.
    public let prebuildCommandResults: [ResolvedTarget: [PrebuildCommandResult]]

    private var derivedTestTargetsMap: [ResolvedProduct: [ResolvedTarget]] = [:]

    /// Cache for pkgConfig flags.
    private var pkgConfigCache = [SystemLibraryTarget: (cFlags: [String], libs: [String])]()

    /// Cache for  library information.
    private var externalLibrariesCache = [BinaryTarget: [LibraryInfo]]()

    /// Cache for  tools information.
    private var externalExecutablesCache = [BinaryTarget: [ExecutableInfo]]()

    /// The filesystem to operate on.
    private let fileSystem: FileSystem

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    private static func makeDerivedTestTargets(
        _ buildParameters: BuildParameters,
        _ graph: PackageGraph,
        _ fileSystem: FileSystem,
        _ observabilityScope: ObservabilityScope
    ) throws -> [(product: ResolvedProduct, discoveryTargetBuildDescription: SwiftTargetBuildDescription?, entryPointTargetBuildDescription: SwiftTargetBuildDescription)] {
        guard buildParameters.testProductStyle.requiresAdditionalDerivedTestTargets,
              case .entryPointExecutable(let explicitlyEnabledDiscovery, let explicitlySpecifiedPath) = buildParameters.testProductStyle
        else {
            throw InternalError("makeTestManifestTargets should not be used for build plan which does not require additional derived test targets")
        }

        let isEntryPointPathSpecifiedExplicitly = explicitlySpecifiedPath != nil

        var isDiscoveryEnabledRedundantly = explicitlyEnabledDiscovery && !isEntryPointPathSpecifiedExplicitly
        var result: [(ResolvedProduct, SwiftTargetBuildDescription?, SwiftTargetBuildDescription)] = []
        for testProduct in graph.allProducts where testProduct.type == .test {
            guard let package = graph.package(for: testProduct) else {
                throw InternalError("package not found for \(testProduct)")
            }
            isDiscoveryEnabledRedundantly = isDiscoveryEnabledRedundantly && nil == testProduct.testEntryPointTarget
            // If a non-explicitly specified test entry point file exists, prefer that over test discovery.
            // This is designed as an escape hatch when test discovery is not appropriate and for backwards
            // compatibility for projects that have existing test entry point files (e.g. XCTMain.swift, LinuxMain.swift).
            let toolsVersion = graph.package(for: testProduct)?.manifest.toolsVersion ?? .v5_5

            // If `testProduct.testEntryPointTarget` is non-nil, it may either represent an `XCTMain.swift` (formerly `LinuxMain.swift`) file
            // if such a file is located in the package, or it may represent a test entry point file at a path specified by the option
            // `--experimental-test-entry-point-path <file>`. The latter is useful because it still performs test discovery and places the discovered
            // tests into a separate target/module named "<PackageName>PackageDiscoveredTests". Then, that entry point file may import that module and
            // obtain that list to pass it to the `XCTMain(...)` function and avoid needing to maintain a list of tests itself.
            if testProduct.testEntryPointTarget != nil && explicitlyEnabledDiscovery && !isEntryPointPathSpecifiedExplicitly {
                let testEntryPointName = testProduct.underlyingProduct.testEntryPointPath?.basename ?? SwiftTarget.defaultTestEntryPointName
                observabilityScope.emit(warning: "'--enable-test-discovery' was specified so the '\(testEntryPointName)' entry point file for '\(testProduct.name)' will be ignored and an entry point will be generated automatically. To use test discovery with a custom entry point file, pass '--experimental-test-entry-point-path <file>'.")
            } else if testProduct.testEntryPointTarget == nil, let testEntryPointPath = explicitlySpecifiedPath, !fileSystem.exists(testEntryPointPath) {
                observabilityScope.emit(error: "'--experimental-test-entry-point-path' was specified but the file '\(testEntryPointPath)' could not be found.")
            }

            /// Generates test discovery targets, which contain derived sources listing the discovered tests.
            func generateDiscoveryTargets() throws -> (target: SwiftTarget, resolved: ResolvedTarget, buildDescription: SwiftTargetBuildDescription) {
                let discoveryTargetName = "\(package.manifest.displayName)PackageDiscoveredTests"
                let discoveryDerivedDir = buildParameters.buildPath.appending(components: "\(discoveryTargetName).derived")
                let discoveryMainFile = discoveryDerivedDir.appending(component: LLBuildManifest.TestDiscoveryTool.mainFileName)

                var discoveryPaths: [AbsolutePath] = []
                discoveryPaths.append(discoveryMainFile)
                for testTarget in testProduct.targets {
                    let path = discoveryDerivedDir.appending(components: testTarget.name + ".swift")
                    discoveryPaths.append(path)
                }

                let discoveryTarget = SwiftTarget(
                    name: discoveryTargetName,
                    group: .package, // test target is allowed access to package decls by default
                    dependencies: testProduct.underlyingProduct.targets.map { .target($0, conditions: []) },
                    testDiscoverySrc: Sources(paths: discoveryPaths, root: discoveryDerivedDir)
                )
                let discoveryResolvedTarget = ResolvedTarget(
                    target: discoveryTarget,
                    dependencies: testProduct.targets.map { .target($0, conditions: []) },
                    defaultLocalization: .none, // safe since this is a derived target
                    platforms: .init(declared: [], derived: []) // safe since this is a derived target
                )
                let discoveryTargetBuildDescription = try SwiftTargetBuildDescription(
                    package: package,
                    target: discoveryResolvedTarget,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    testTargetRole: .discovery,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )

                return (discoveryTarget, discoveryResolvedTarget, discoveryTargetBuildDescription)
            }

            /// Generates a synthesized test entry point target, consisting of a single "main" file which calls the test entry
            /// point API and leverages the test discovery target to reference which tests to run.
            func generateSynthesizedEntryPointTarget(discoveryTarget: SwiftTarget, discoveryResolvedTarget: ResolvedTarget) throws -> SwiftTargetBuildDescription {
                let entryPointDerivedDir = buildParameters.buildPath.appending(components: "\(testProduct.name).derived")
                let entryPointMainFile = entryPointDerivedDir.appending(component: LLBuildManifest.TestEntryPointTool.mainFileName)
                let entryPointSources = Sources(paths: [entryPointMainFile], root: entryPointDerivedDir)

                let entryPointTarget = SwiftTarget(
                    name: testProduct.name,
                    group: .package, // test target is allowed access to package decls by default
                    type: .library,
                    dependencies: testProduct.underlyingProduct.targets.map { .target($0, conditions: []) } + [.target(discoveryTarget, conditions: [])],
                    testEntryPointSources: entryPointSources
                )
                let entryPointResolvedTarget = ResolvedTarget(
                    target: entryPointTarget,
                    dependencies: testProduct.targets.map { .target($0, conditions: []) } + [.target(discoveryResolvedTarget, conditions: [])],
                    defaultLocalization: .none, // safe since this is a derived target
                    platforms: .init(declared: [], derived: []) // safe since this is a derived target
                )
                return try SwiftTargetBuildDescription(
                    package: package,
                    target: entryPointResolvedTarget,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    testTargetRole: .entryPoint(isSynthesized: true),
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )
            }

            if let entryPointResolvedTarget = testProduct.testEntryPointTarget {
                if isEntryPointPathSpecifiedExplicitly || explicitlyEnabledDiscovery {
                    let discoveryTargets = try generateDiscoveryTargets()

                    if isEntryPointPathSpecifiedExplicitly {
                        // Allow using the explicitly-specified test entry point target, but still perform test discovery and thus declare a dependency on the discovery targets.
                        let entryPointTarget = SwiftTarget(
                            name: entryPointResolvedTarget.underlyingTarget.name,
                            group: entryPointResolvedTarget.group,
                            dependencies: entryPointResolvedTarget.underlyingTarget.dependencies + [.target(discoveryTargets.target, conditions: [])],
                            testEntryPointSources: entryPointResolvedTarget.underlyingTarget.sources
                        )
                        let entryPointResolvedTarget = ResolvedTarget(
                            target: entryPointTarget,
                            dependencies: entryPointResolvedTarget.dependencies + [.target(discoveryTargets.resolved, conditions: [])],
                            defaultLocalization: .none, // safe since this is a derived target
                            platforms: .init(declared: [], derived: []) // safe since this is a derived target
                        )
                        let entryPointTargetBuildDescription = try SwiftTargetBuildDescription(
                            package: package,
                            target: entryPointResolvedTarget,
                            toolsVersion: toolsVersion,
                            buildParameters: buildParameters,
                            testTargetRole: .entryPoint(isSynthesized: false),
                            fileSystem: fileSystem,
                            observabilityScope: observabilityScope
                        )

                        result.append((testProduct, discoveryTargets.buildDescription, entryPointTargetBuildDescription))
                    } else {
                        // Ignore test entry point and synthesize one, declaring a dependency on the test discovery targets created above.
                        let entryPointTargetBuildDescription = try generateSynthesizedEntryPointTarget(discoveryTarget: discoveryTargets.target, discoveryResolvedTarget: discoveryTargets.resolved)
                        result.append((testProduct, discoveryTargets.buildDescription, entryPointTargetBuildDescription))
                    }
                } else {
                    // Use the test entry point as-is, without performing test discovery.
                    let entryPointTargetBuildDescription = try SwiftTargetBuildDescription(
                        package: package,
                        target: entryPointResolvedTarget,
                        toolsVersion: toolsVersion,
                        buildParameters: buildParameters,
                        testTargetRole: .entryPoint(isSynthesized: false),
                        fileSystem: fileSystem,
                        observabilityScope: observabilityScope
                    )
                    result.append((testProduct, nil, entryPointTargetBuildDescription))
                }
            } else {
                // Synthesize a test entry point target, declaring a dependency on the test discovery targets.
                let discoveryTargets = try generateDiscoveryTargets()
                let entryPointTargetBuildDescription = try generateSynthesizedEntryPointTarget(discoveryTarget: discoveryTargets.target, discoveryResolvedTarget: discoveryTargets.resolved)
                result.append((testProduct, discoveryTargets.buildDescription, entryPointTargetBuildDescription))
            }
        }

        if isDiscoveryEnabledRedundantly {
            observabilityScope.emit(warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms")
        }

        return result
    }

    /// Create a build plan with build parameters and a package graph.
    public init(
        buildParameters: BuildParameters,
        graph: PackageGraph,
        additionalFileRules: [FileRuleDescription] = [],
        buildToolPluginInvocationResults: [ResolvedTarget: [BuildToolPluginInvocationResult]] = [:],
        prebuildCommandResults: [ResolvedTarget: [PrebuildCommandResult]] = [:],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        self.buildParameters = buildParameters
        self.graph = graph
        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "Build Plan")

        var productMap: [ResolvedProduct: ProductBuildDescription] = [:]
        // Create product description for each product we have in the package graph that is eligible.
        for product in graph.allProducts where product.shouldCreateProductDescription {
            guard let package = graph.package(for: product) else {
                throw InternalError("unknown package for \(product)")
            }
            // Determine the appropriate tools version to use for the product.
            // This can affect what flags to pass and other semantics.
            let toolsVersion = package.manifest.toolsVersion
            productMap[product] = try ProductBuildDescription(
                package: package,
                product: product,
                toolsVersion: toolsVersion,
                buildParameters: buildParameters,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        }
        let macroProductsByTarget = productMap.keys.filter { $0.type == .macro }.reduce(into: [ResolvedTarget: ResolvedProduct]()) {
            if let target = $1.targets.first {
                $0[target] = $1
            }
        }

        // Create build target description for each target which we need to plan.
        // Plugin targets are noted, since they need to be compiled, but they do
        // not get directly incorporated into the build description that will be
        // given to LLBuild.
        var targetMap = [ResolvedTarget: TargetBuildDescription]()
        var pluginDescriptions = [PluginDescription]()
        for target in graph.allTargets.sorted(by: { $0.name < $1.name }) {
            // Validate the product dependencies of this target.
            for dependency in target.dependencies {
                guard dependency.satisfies(buildParameters.buildEnvironment) else {
                    continue
                }

                switch dependency {
                case .target: break
                case .product(let product, _):
                    if buildParameters.triple.isDarwin() {
                        try BuildPlan.validateDeploymentVersionOfProductDependency(
                            product: product,
                            forTarget: target,
                            observabilityScope: self.observabilityScope
                        )
                    }
                }
            }

            // Determine the appropriate tools version to use for the target.
            // This can affect what flags to pass and other semantics.
            let toolsVersion = graph.package(for: target)?.manifest.toolsVersion ?? .v5_5

            switch target.underlyingTarget {
            case is SwiftTarget:
                guard let package = graph.package(for: target) else {
                    throw InternalError("package not found for \(target)")
                }

                let requiredMacroProducts = try target.recursiveTargetDependencies().filter { $0.underlyingTarget.type == .macro }.compactMap { macroProductsByTarget[$0] }

                targetMap[target] = try .swift(SwiftTargetBuildDescription(
                    package: package,
                    target: target,
                    toolsVersion: toolsVersion,
                    additionalFileRules: additionalFileRules,
                    buildParameters: buildParameters,
                    buildToolPluginInvocationResults: buildToolPluginInvocationResults[target] ?? [],
                    prebuildCommandResults: prebuildCommandResults[target] ?? [],
                    requiredMacroProducts: requiredMacroProducts,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope)
                )
            case is ClangTarget:
                targetMap[target] = try .clang(ClangTargetBuildDescription(
                    target: target,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    fileSystem: fileSystem))
            case is PluginTarget:
                guard let package = graph.package(for: target) else {
                    throw InternalError("package not found for \(target)")
                }
                try pluginDescriptions.append(PluginDescription(
                    target: target,
                    products: package.products.filter{ $0.targets.contains(target) },
                    package: package,
                    toolsVersion: toolsVersion,
                    fileSystem: fileSystem))
            case is SystemLibraryTarget, is BinaryTarget:
                 break
            default:
                 throw InternalError("unhandled \(target.underlyingTarget)")
            }
        }

        /// Ensure we have at least one buildable target.
        guard !targetMap.isEmpty else {
            throw Error.noBuildableTarget
        }

        // Abort now if we have any diagnostics at this point.
        guard !self.observabilityScope.errorsReported else {
            throw Diagnostics.fatalError
        }

        // Plan the derived test targets, if necessary.
        if buildParameters.testProductStyle.requiresAdditionalDerivedTestTargets {
            let derivedTestTargets = try Self.makeDerivedTestTargets(buildParameters, graph, self.fileSystem, self.observabilityScope)
            for item in derivedTestTargets {
                var derivedTestTargets = [item.entryPointTargetBuildDescription.target]

                targetMap[item.entryPointTargetBuildDescription.target] = .swift(item.entryPointTargetBuildDescription)

                if let discoveryTargetBuildDescription = item.discoveryTargetBuildDescription {
                    targetMap[discoveryTargetBuildDescription.target] = .swift(discoveryTargetBuildDescription)
                    derivedTestTargets.append(discoveryTargetBuildDescription.target)
                }

                derivedTestTargetsMap[item.product] = derivedTestTargets
            }
        }

        self.productMap = productMap
        self.targetMap = targetMap
        self.pluginDescriptions = pluginDescriptions

        // Finally plan these targets.
        try plan()
    }

    static func validateDeploymentVersionOfProductDependency(
        product: ResolvedProduct,
        forTarget target: ResolvedTarget,
        observabilityScope: ObservabilityScope
    ) throws {
        // Supported platforms are defined at the package level.
        // This will need to become a bit complicated once we have target-level or product-level platform support.
        guard let productPlatform = product.platforms.getDerived(for: .macOS) else {
            throw StringError("Expected supported platform macOS in product \(product)")
        }
        guard let targetPlatform = target.platforms.getDerived(for: .macOS) else {
            throw StringError("Expected supported platform macOS in target \(target)")
        }

        // Check if the version requirement is satisfied.
        //
        // If the product's platform version is greater than ours, then it is incompatible.
        if productPlatform.version > targetPlatform.version {
            observabilityScope.emit(.productRequiresHigherPlatformVersion(
                target: target,
                targetPlatform: targetPlatform,
                product: product.name,
                productPlatform: productPlatform
            ))
        }
    }

    /// Plan the targets and products.
    private func plan() throws {
        // Plan targets.
        for buildTarget in targets {
            switch buildTarget {
            case .swift(let target):
                try self.plan(swiftTarget: target)
            case .clang(let target):
                try self.plan(clangTarget: target)
            }
        }

        // Plan products.
        for buildProduct in buildProducts {
            try plan(buildProduct as! ProductBuildDescription)
        }
        // FIXME: We need to find out if any product has a target on which it depends
        // both static and dynamically and then issue a suitable diagnostic or auto
        // handle that situation.
    }

    /// Plan a product.
    private func plan(_ buildProduct: ProductBuildDescription) throws {
        // Compute the product's dependency.
        let dependencies = try computeDependencies(of: buildProduct.product)

        // Add flags for system targets.
        for systemModule in dependencies.systemModules {
            guard case let target as SystemLibraryTarget = systemModule.underlyingTarget else {
                throw InternalError("This should not be possible.")
            }
            // Add pkgConfig libs arguments.
            buildProduct.additionalFlags += try pkgConfig(for: target).libs
        }

        // Add flags for binary dependencies.
        for binaryPath in dependencies.libraryBinaryPaths {
            if binaryPath.extension == "framework" {
                buildProduct.additionalFlags += ["-framework", binaryPath.basenameWithoutExt]
            } else if binaryPath.basename.starts(with: "lib") {
                buildProduct.additionalFlags += ["-l\(binaryPath.basenameWithoutExt.dropFirst(3))"]
            } else {
                self.observabilityScope.emit(error: "unexpected binary framework")
            }
        }

        // Link C++ if needed.
        // Note: This will come from build settings in future.
        for target in dependencies.staticTargets {
            if case let target as ClangTarget = target.underlyingTarget, target.isCXX {
                if buildParameters.hostTriple.isDarwin() {
                    buildProduct.additionalFlags += ["-lc++"]
                } else if buildParameters.hostTriple.isWindows() {
                    // Don't link any C++ library.
                } else {
                    buildProduct.additionalFlags += ["-lstdc++"]
                }
                break
            }
        }

        for target in dependencies.staticTargets {
            switch target.underlyingTarget {
            case is SwiftTarget:
                // Swift targets are guaranteed to have a corresponding Swift description.
                guard case .swift(let description) = targetMap[target] else {
                    throw InternalError("unknown target \(target)")
                }

                // Based on the debugging strategy, we either need to pass swiftmodule paths to the
                // product or link in the wrapped module object. This is required for properly debugging
                // Swift products. Debugging strategy is computed based on the current platform we're
                // building for and is nil for the release configuration.
                switch buildParameters.debuggingStrategy {
                case .swiftAST:
                    buildProduct.swiftASTs.insert(description.moduleOutputPath)
                case .modulewrap:
                    buildProduct.objects += [description.wrappedModuleOutputPath]
                case nil:
                    break
                }
            default: break
            }
        }

        buildProduct.staticTargets = dependencies.staticTargets
        buildProduct.dylibs = try dependencies.dylibs.map{
            guard let product = productMap[$0] else {
                throw InternalError("unknown product \($0)")
            }
            return product
        }
        buildProduct.objects += try dependencies.staticTargets.flatMap{ targetName -> [AbsolutePath] in
            guard let target = targetMap[targetName] else {
                throw InternalError("unknown target \(targetName)")
            }
            return try target.objects
        }
        buildProduct.libraryBinaryPaths = dependencies.libraryBinaryPaths

        // Write the link filelist file.
        //
        // FIXME: We should write this as a custom llbuild task once we adopt it
        // as a library.
        try buildProduct.writeLinkFilelist(fileSystem)

        buildProduct.availableTools = dependencies.availableTools
    }

    /// Computes the dependencies of a product.
    private func computeDependencies(
        of product: ResolvedProduct
    ) throws -> (
        dylibs: [ResolvedProduct],
        staticTargets: [ResolvedTarget],
        systemModules: [ResolvedTarget],
        libraryBinaryPaths: Set<AbsolutePath>,
        availableTools: [String: AbsolutePath]
    ) {

        // Sort the product targets in topological order.
        let nodes: [ResolvedTarget.Dependency] = product.targets.map { .target($0, conditions: []) }
        let allTargets = try topologicalSort(nodes, successors: { dependency in
            switch dependency {
            // Include all the dependencies of a target.
            case .target(let target, _):
                return target.dependencies.filter { $0.satisfies(self.buildEnvironment) }

            // For a product dependency, we only include its content only if we
            // need to statically link it or if it's a plugin.
            case .product(let product, _):
                guard dependency.satisfies(self.buildEnvironment) else {
                    return []
                }

                switch product.type {
                case .library(.automatic), .library(.static), .plugin:
                    return product.targets.map { .target($0, conditions: []) }
                case .library(.dynamic), .test, .executable, .snippet, .macro:
                    return []
                }
            }
        })

        // Create empty arrays to collect our results.
        var linkLibraries = [ResolvedProduct]()
        var staticTargets = [ResolvedTarget]()
        var systemModules = [ResolvedTarget]()
        var libraryBinaryPaths: Set<AbsolutePath> = []
        var availableTools = [String: AbsolutePath]()

        for dependency in allTargets {
            switch dependency {
            case .target(let target, _):
                switch target.type {
                // Executable target have historically only been included if they are directly in the product's
                // target list.  Otherwise they have always been just build-time dependencies.
                // In tool version .v5_5 or greater, we also include executable modules implemented in Swift in
                // any test products... this is to allow testing of executables.  Note that they are also still
                // built as separate products that the test can invoke as subprocesses.
                case .executable, .snippet, .macro:
                    if product.targets.contains(target) {
                        staticTargets.append(target)
                    } else if product.type == .test && (target.underlyingTarget as? SwiftTarget)?.supportsTestableExecutablesFeature == true {
                        if let toolsVersion = graph.package(for: product)?.manifest.toolsVersion, toolsVersion >= .v5_5 {
                            staticTargets.append(target)
                        }
                    }
                // Test targets should be included only if they are directly in the product's target list.
                case .test:
                    if product.targets.contains(target) {
                        staticTargets.append(target)
                    }
                // Library targets should always be included.
                case .library:
                    staticTargets.append(target)
                // Add system target to system targets array.
                case .systemModule:
                    systemModules.append(target)
                // Add binary to binary paths set.
                case .binary:
                    guard let binaryTarget = target.underlyingTarget as? BinaryTarget else {
                        throw InternalError("invalid binary target '\(target.name)'")
                    }
                    switch binaryTarget.kind {
                    case .xcframework:
                        let libraries = try self.parseXCFramework(for: binaryTarget)
                        for library in libraries {
                            libraryBinaryPaths.insert(library.libraryPath)
                        }
                    case .artifactsArchive:
                        let tools = try self.parseArtifactsArchive(for: binaryTarget)
                        tools.forEach { availableTools[$0.name] = $0.executablePath  }
                    case.unknown:
                        throw InternalError("unknown binary target '\(target.name)' type")
                    }
                case .macro:
                    if product.type == .macro {
                        staticTargets.append(target)
                    }
                case .plugin:
                    continue
                }

            case .product(let product, _):
                // Add the dynamic products to array of libraries to link.
                if product.type == .library(.dynamic) {
                    linkLibraries.append(product)
                }
            }
        }

        // Add derived test targets, if necessary
        if buildParameters.testProductStyle.requiresAdditionalDerivedTestTargets {
            if product.type == .test, let derivedTestTargets = derivedTestTargetsMap[product] {
                staticTargets.append(contentsOf: derivedTestTargets)
            }
        }

        return (linkLibraries, staticTargets, systemModules, libraryBinaryPaths, availableTools)
    }

    /// Plan a Clang target.
    private func plan(clangTarget: ClangTargetBuildDescription) throws {
        for case .target(let dependency, _) in try clangTarget.target.recursiveDependencies(satisfying: buildEnvironment) {
            switch dependency.underlyingTarget {
            case is SwiftTarget:
                if case let .swift(dependencyTargetDescription)? = targetMap[dependency] {
                    if let moduleMap = dependencyTargetDescription.moduleMap {
                        clangTarget.additionalFlags += ["-fmodule-map-file=\(moduleMap.pathString)"]
                    }
                }

            case let target as ClangTarget where target.type == .library:
                // Setup search paths for C dependencies:
                clangTarget.additionalFlags += ["-I", target.includeDir.pathString]

                // Add the modulemap of the dependency if it has one.
                if case let .clang(dependencyTargetDescription)? = targetMap[dependency] {
                    if let moduleMap = dependencyTargetDescription.moduleMap {
                        clangTarget.additionalFlags += ["-fmodule-map-file=\(moduleMap.pathString)"]
                    }
                }
            case let target as SystemLibraryTarget:
                clangTarget.additionalFlags += ["-fmodule-map-file=\(target.moduleMapPath.pathString)"]
                clangTarget.additionalFlags += try pkgConfig(for: target).cFlags
            case let target as BinaryTarget:
                if case .xcframework = target.kind {
                    let libraries = try self.parseXCFramework(for: target)
                    for library in libraries {
                        library.headersPaths.forEach {
                            clangTarget.additionalFlags += ["-I", $0.pathString]
                        }
                        clangTarget.libraryBinaryPaths.insert(library.libraryPath)
                    }
                }
            default: continue
            }
        }
    }

    /// Plan a Swift target.
    private func plan(swiftTarget: SwiftTargetBuildDescription) throws {
        // We need to iterate recursive dependencies because Swift compiler needs to see all the targets a target
        // depends on.
        for case .target(let dependency, _) in try swiftTarget.target.recursiveDependencies(satisfying: buildEnvironment) {
            switch dependency.underlyingTarget {
            case let underlyingTarget as ClangTarget where underlyingTarget.type == .library:
                guard case let .clang(target)? = targetMap[dependency] else {
                    throw InternalError("unexpected clang target \(underlyingTarget)")
                }
                // Add the path to modulemap of the dependency. Currently we require that all Clang targets have a
                // modulemap but we may want to remove that requirement since it is valid for a target to exist without
                // one. However, in that case it will not be importable in Swift targets. We may want to emit a warning
                // in that case from here.
                guard let moduleMap = target.moduleMap else { break }
                swiftTarget.additionalFlags += [
                    "-Xcc", "-fmodule-map-file=\(moduleMap.pathString)",
                    "-Xcc", "-I", "-Xcc", target.clangTarget.includeDir.pathString,
                ]
            case let target as SystemLibraryTarget:
                swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(target.moduleMapPath.pathString)"]
                swiftTarget.additionalFlags += try pkgConfig(for: target).cFlags
            case let target as BinaryTarget:
                if case .xcframework = target.kind {
                    let libraries = try self.parseXCFramework(for: target)
                    for library in libraries {
                        library.headersPaths.forEach {
                            swiftTarget.additionalFlags += ["-I", $0.pathString, "-Xcc", "-I", "-Xcc", $0.pathString]
                        }
                        swiftTarget.libraryBinaryPaths.insert(library.libraryPath)
                    }
                }
            default:
                break
            }
        }
    }

    public func createAPIToolCommonArgs(includeLibrarySearchPaths: Bool) throws -> [String] {
        let buildPath = buildParameters.buildPath.pathString
        var arguments = ["-I", buildPath]

        var extraSwiftCFlags = buildParameters.toolchain.extraFlags.swiftCompilerFlags
        if !includeLibrarySearchPaths {
            for index in extraSwiftCFlags.indices.dropLast().reversed() {
                if extraSwiftCFlags[index] == "-L" {
                    // Remove the flag
                    extraSwiftCFlags.remove(at: index)
                    // Remove the argument
                    extraSwiftCFlags.remove(at: index)
                }
            }
        }
        arguments += extraSwiftCFlags

        // Add the search path to the directory containing the modulemap file.
        for target in targets {
            switch target {
            case .swift: break
            case .clang(let targetDescription):
                if let includeDir = targetDescription.moduleMap?.parentDirectory {
                    arguments += ["-I", includeDir.pathString]
                }
            }
        }

        // Add search paths from the system library targets.
        for target in graph.reachableTargets {
            if let systemLib = target.underlyingTarget as? SystemLibraryTarget {
                arguments.append(contentsOf: try self.pkgConfig(for: systemLib).cFlags)
                // Add the path to the module map.
                arguments += ["-I", systemLib.moduleMapPath.parentDirectory.pathString]
            }
        }

        return arguments
    }

    /// Creates arguments required to launch the Swift REPL that will allow
    /// importing the modules in the package graph.
    public func createREPLArguments() throws -> [String] {
        let buildPath = buildParameters.buildPath.pathString
        var arguments = ["repl", "-I" + buildPath, "-L" + buildPath]

        // Link the special REPL product that contains all of the library targets.
        let replProductName = graph.rootPackages[0].identity.description + Product.replProductSuffix
        arguments.append("-l" + replProductName)

        // The graph should have the REPL product.
        assert(graph.allProducts.first(where: { $0.name == replProductName }) != nil)

        // Add the search path to the directory containing the modulemap file.
        for target in targets {
            switch target {
                case .swift: break
            case .clang(let targetDescription):
                if let includeDir = targetDescription.moduleMap?.parentDirectory {
                    arguments += ["-I\(includeDir.pathString)"]
                }
            }
        }

        // Add search paths from the system library targets.
        for target in graph.reachableTargets {
            if let systemLib = target.underlyingTarget as? SystemLibraryTarget {
                arguments += try self.pkgConfig(for: systemLib).cFlags
            }
        }

        return arguments
    }

    /// Get pkgConfig arguments for a system library target.
    private func pkgConfig(for target: SystemLibraryTarget) throws -> (cFlags: [String], libs: [String]) {
        // If we already have these flags, we're done.
        if let flags = pkgConfigCache[target] {
            return flags
        }
        else {
            pkgConfigCache[target] = ([], [])
        }
        let results = try pkgConfigArgs(
            for: target,
            pkgConfigDirectories: buildParameters.pkgConfigDirectories,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        var ret: [(cFlags: [String], libs: [String])] = []
        for result in results {
            ret.append((result.cFlags, result.libs))
        }

        // Build cache
        var cflagsCache: OrderedCollections.OrderedSet<String> = []
        var libsCache: [String] = []
        for tuple in ret {
            for cFlag in tuple.cFlags {
                cflagsCache.append(cFlag)
            }

            libsCache.append(contentsOf: tuple.libs)
        }

        let result = ([String](cflagsCache), libsCache)
        pkgConfigCache[target] = result
        return result
    }

    /// Extracts the library information from an XCFramework.
    private func parseXCFramework(for target: BinaryTarget) throws -> [LibraryInfo] {
        try self.externalLibrariesCache.memoize(key: target) {
            return try target.parseXCFrameworks(for: self.buildParameters.triple, fileSystem: self.fileSystem)
        }
    }

    /// Extracts the artifacts  from an artifactsArchive
    private func parseArtifactsArchive(for target: BinaryTarget) throws -> [ExecutableInfo] {
        try self.externalExecutablesCache.memoize(key: target) {
            let execInfos = try target.parseArtifactArchives(for: self.buildParameters.triple, fileSystem: self.fileSystem)
            return execInfos.filter{!$0.supportedTriples.isEmpty}
        }
    }
}

private extension PackageModel.SwiftTarget {
    /// Initialize a SwiftTarget representing a test entry point.
    convenience init(
        name: String,
        group: Group,
        type: PackageModel.Target.Kind? = nil,
        dependencies: [PackageModel.Target.Dependency],
        testEntryPointSources sources: Sources
    ) {
        self.init(
            name: name,
            group: group,
            type: type ?? .executable,
            path: .root,
            sources: sources,
            dependencies: dependencies,
            swiftVersion: .v5,
            usesUnsafeFlags: false
        )
    }
}

extension Basics.Diagnostic {
    static var swiftBackDeployError: Self {
        .warning("Swift compiler no longer supports statically linking the Swift libraries. They're included in the OS by default starting with macOS Mojave 10.14.4 beta 3. For macOS Mojave 10.14.3 and earlier, there's an optional Swift library package that can be downloaded from \"More Downloads\" for Apple Developers at https://developer.apple.com/download/more/")
    }

    static func productRequiresHigherPlatformVersion(
        target: ResolvedTarget,
        targetPlatform: SupportedPlatform,
        product: String,
        productPlatform: SupportedPlatform
    ) -> Self {
        .error("""
            the \(target.type.rawValue) '\(target.name)' requires \
            \(targetPlatform.platform.name) \(targetPlatform.version.versionString), \
            but depends on the product '\(product)' which requires \
            \(productPlatform.platform.name) \(productPlatform.version.versionString); \
            consider changing the \(target.type.rawValue) '\(target.name)' to require \
            \(productPlatform.platform.name) \(productPlatform.version.versionString) or later, \
            or the product '\(product)' to require \
            \(targetPlatform.platform.name) \(targetPlatform.version.versionString) or earlier.
            """)
    }

    static func binaryTargetsNotSupported() -> Diagnostic.Message {
        .error("binary targets are not supported on this platform")
    }
}

extension BuildParameters {
    /// Returns a named bundle's path inside the build directory.
    func bundlePath(named name: String) -> AbsolutePath {
        return buildPath.appending(component: name + triple.nsbundleExtension)
    }
}

extension FileSystem {
    /// Write bytes to the path if the given contents are different.
    func writeIfChanged(path: AbsolutePath, bytes: ByteString) throws {
        try createDirectory(path.parentDirectory, recursive: true)

        // Return if the contents are same.
        if isFile(path), try readFileContents(path) == bytes {
            return
        }

        try writeFileContents(path, bytes: bytes)
    }
}

/// Generate the resource bundle Info.plist.
func generateResourceInfoPlist(
    fileSystem: FileSystem,
    target: ResolvedTarget,
    path: AbsolutePath
) throws -> Bool {
    guard let defaultLocalization = target.defaultLocalization else {
        return false
    }

    let stream = BufferedOutputByteStream()
    stream <<< """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>\(defaultLocalization)</string>
        </dict>
        </plist>
        """

    try fileSystem.writeIfChanged(path: path, bytes: stream.bytes)
    return true
}

extension Basics.Triple {
    var isSupportingStaticStdlib: Bool {
        isLinux() || arch == .wasm32
    }
}

extension ResolvedPackage {
    var isRemote: Bool {
        switch self.underlyingPackage.manifest.packageKind {
        case .registry, .remoteSourceControl, .localSourceControl:
            return true
        case .root, .fileSystem:
            return false
        }
    }
}

extension ResolvedProduct {
    private var isAutomaticLibrary: Bool {
        return self.type == .library(.automatic)
    }

    private var isBinaryOnly: Bool {
        return self.targets.filter({ !($0.underlyingTarget is BinaryTarget) }).isEmpty
    }

    private var isPlugin: Bool {
        return self.type == .plugin
    }

    // We shouldn't create product descriptions for automatic libraries, plugins or products which consist solely of binary targets, because they don't produce any output.
    fileprivate var shouldCreateProductDescription: Bool {
        return !isAutomaticLibrary && !isBinaryOnly && !isPlugin
    }
}
