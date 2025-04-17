//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import Basics
import Foundation
import LLBuildManifest
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import TSCBasic

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SwiftDriver
#else
import SwiftDriver
#endif

import enum TSCUtility.Diagnostics
import var TSCUtility.verbosity

extension String {
    var asSwiftStringLiteralConstant: String {
        unicodeScalars.reduce("") { $0 + $1.escaped(asASCII: false) }
    }
}

extension [String] {
    /// Converts a set of C compiler flags into an equivalent set to be
    /// indirected through the Swift compiler instead.
    func asSwiftcCCompilerFlags() -> Self {
        self.flatMap { ["-Xcc", $0] }
    }

    /// Converts a set of C++ compiler flags into an equivalent set to be
    /// indirected through the Swift compiler instead.
    func asSwiftcCXXCompilerFlags() -> Self {
        _ = self.flatMap { ["-Xcxx", $0] }
        // TODO: Pass -Xcxx flags to swiftc (#6491)
        // Remove fatal error when downstream support arrives.
        fatalError("swiftc does support -Xcxx flags yet.")
    }

    /// Converts a set of linker flags into an equivalent set to be indirected
    /// through the Swift compiler instead.
    ///
    /// Some arguments can be passed directly to the Swift compiler. We omit
    /// prefixing these arguments (in both the "-option value" and
    /// "-option[=]value" forms) with "-Xlinker". All other arguments are
    /// prefixed with "-Xlinker".
    func asSwiftcLinkerFlags() -> Self {
        // Arguments that can be passed directly to the Swift compiler and
        // doesn't require -Xlinker prefix.
        //
        // We do this to avoid sending flags like linker search path at the end
        // of the search list.
        let directSwiftLinkerArgs = ["-L"]

        var flags: [String] = []
        var it = self.makeIterator()
        while let flag = it.next() {
            if directSwiftLinkerArgs.contains(flag) {
                // `<option> <value>` variant.
                flags.append(flag)
                guard let nextFlag = it.next() else {
                    // We expected a flag but don't have one.
                    continue
                }
                flags.append(nextFlag)
            } else if directSwiftLinkerArgs.contains(where: { flag.hasPrefix($0) }) {
                // `<option>[=]<value>` variant.
                flags.append(flag)
            } else {
                flags += ["-Xlinker", flag]
            }
        }
        return flags
    }
}

extension BuildParameters {
    /// Returns the directory to be used for module cache.
    public var moduleCache: Basics.AbsolutePath {
        get throws {
            // FIXME: We use this hack to let swiftpm's functional test use shared
            // cache so it doesn't become painfully slow.
            if let path = Environment.current["SWIFTPM_TESTS_MODULECACHE"] {
                return try AbsolutePath(validating: path)
            }
            return buildPath.appending("ModuleCache")
        }
    }

    /// Returns the compiler arguments for the index store, if enabled.
    func indexStoreArguments(for target: ResolvedModule) -> [String] {
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
    public func tripleArgs(for target: ResolvedModule) throws -> [String] {
        // confusingly enough this is the triple argument, not the target argument
        var args = ["-target"]

        // Compute the triple string for Darwin platform using the platform version.
        if self.triple.isDarwin() {
            let platform = self.buildEnvironment.platform
            let supportedPlatform = target.getSupportedPlatform(for: platform, usingXCTest: target.type == .test)
            args += [self.triple.tripleString(forPlatformVersion: supportedPlatform.version.versionString)]
        } else {
            args += [self.triple.tripleString]
        }
        return args
    }

    /// Computes the linker flags to use in order to rename a module-named main function to 'main' for the target
    /// platform, or nil if the linker doesn't support it for the platform.
    func linkerFlagsForRenamingMainFunction(of target: ResolvedModule) -> [String]? {
        let args: [String]
        switch self.triple.objectFormat {
        case .macho:
            args = ["-alias", "_\(target.c99name)_main", "_main"]
        case .elf:
            args = ["--defsym", "main=\(target.c99name)_main"]
        case .coff:
            // If the user is specifying a custom entry point name that isn't "main", assume they may be setting WinMain or wWinMain
            // and don't do any modifications ourselves. In that case the linker will infer the WINDOWS subsystem and call WinMainCRTStartup,
            // which will then call the custom entry point. And WinMain/wWinMain != main, so this still won't run into duplicate symbol
            // issues when called from a test target, which always uses main.
            if let customEntryPointFunctionName = findCustomEntryPointFunctionName(of: target), customEntryPointFunctionName != "main" {
                return nil
            }
            args = ["/ALTERNATENAME:main=\(target.c99name)_main", "/SUBSYSTEM:CONSOLE"]
        default:
            return nil
        }
        return args.asSwiftcLinkerFlags()
    }

    private func findCustomEntryPointFunctionName(of target: ResolvedModule) -> String? {
        let flags = createScope(for: target).evaluate(.OTHER_SWIFT_FLAGS)
        var it = flags.makeIterator()
        while let value = it.next() {
            if value == "-Xfrontend" && it.next() == "-entry-point-function-name" && it.next() == "-Xfrontend" {
                return it.next()
            }
        }
        return nil
    }

    /// Returns the scoped view of build settings for a given target.
    func createScope(for target: ResolvedModule) -> BuildSettings.Scope {
        BuildSettings.Scope(target.underlying.buildSettings, environment: buildEnvironment)
    }
}

/// A build plan for a package graph.
public class BuildPlan: SPMBuildCore.BuildPlan {
    /// Return value of `inputs()`
    package enum Input {
        /// Any file in this directory affects the build plan
        case directoryStructure(Basics.AbsolutePath)
        /// The file at the given path affects the build plan
        case file(Basics.AbsolutePath)
    }

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

    /// Build parameters used for products.
    public let destinationBuildParameters: BuildParameters

    /// Build parameters used for tools.
    public let toolsBuildParameters: BuildParameters

    /// The package graph.
    public let graph: ModulesGraph

    /// The target build description map.
    public let targetMap: IdentifiableSet<ModuleBuildDescription>

    /// The product build description map.
    public let productMap: IdentifiableSet<ProductBuildDescription>

    /// The plugin descriptions. Plugins are represented in the package graph
    /// as targets, but they are not directly included in the build graph.
    public let pluginDescriptions: [PluginBuildDescription]

    /// The build targets.
    public var targets: AnySequence<ModuleBuildDescription> {
        AnySequence(self.targetMap.values)
    }

    /// The products in this plan.
    public var buildProducts: AnySequence<SPMBuildCore.ProductBuildDescription> {
        AnySequence(self.productMap.values.map { $0 as SPMBuildCore.ProductBuildDescription })
    }

    public var buildModules: AnySequence<SPMBuildCore.ModuleBuildDescription> {
        AnySequence(self.targetMap.values.map { $0 as SPMBuildCore.ModuleBuildDescription })
    }

    /// The results of invoking any build tool plugins used by targets in this build.
    public let buildToolPluginInvocationResults: [ResolvedModule.ID: [BuildToolPluginInvocationResult]]

    /// The results of running any prebuild commands for the targets in this build.  This includes any derived
    /// source files as well as directories to which any changes should cause us to reevaluate the build plan.
    public let prebuildCommandResults: [ResolvedModule.ID: [CommandPluginResult]]

    @_spi(SwiftPMInternal)
    public private(set) var derivedTestTargetsMap: [ResolvedProduct.ID: [ResolvedModule]] = [:]

    /// Cache for pkgConfig flags.
    private var pkgConfigCache = [SystemLibraryModule: (cFlags: [String], libs: [String])]()

    /// Cache for library information.
    private var externalLibrariesCache = [BinaryModule: [LibraryInfo]]()

    /// Cache for tools information.
    var externalExecutablesCache = [BinaryModule: [ExecutableInfo]]()

    /// Whether to disable sandboxing (e.g. for macros).
    private let shouldDisableSandbox: Bool

    /// The filesystem to operate on.
    let fileSystem: any FileSystem

    /// ObservabilityScope with which to emit diagnostics
    let observabilityScope: ObservabilityScope

    @available(*, deprecated, renamed: "init(destinationBuildParameters:toolsBuildParameters:graph:fileSystem:observabilityScope:)")
    public convenience init(
        productsBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        graph: ModulesGraph,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws {
        try await self.init(
            destinationBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            graph: graph,
            pluginConfiguration: nil,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }

    /// Create a build plan with a package graph and explicitly distinct build parameters for destination platform and
    /// tools platform.
    public init(
        destinationBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        graph: ModulesGraph,
        pluginConfiguration: PluginConfiguration? = nil,
        pluginTools: [ResolvedModule.ID: [String: PluginTool]] = [:],
        additionalFileRules: [FileRuleDescription] = [],
        pkgConfigDirectories: [Basics.AbsolutePath] = [],
        disableSandbox: Bool = false,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws {
        self.destinationBuildParameters = destinationBuildParameters
        self.toolsBuildParameters = toolsBuildParameters
        self.graph = graph
        self.shouldDisableSandbox = disableSandbox
        self.fileSystem = fileSystem

        var buildToolPluginInvocationResults: [ResolvedModule.ID: [BuildToolPluginInvocationResult]] = [:]
        var prebuildCommandResults: [ResolvedModule.ID: [CommandPluginResult]] = [:]

        // Create product description for each product we have in the package graph that is eligible.
        var productMap = IdentifiableSet<ProductBuildDescription>()
        // Create build target description for each target which we need to plan.
        // Plugin targets are noted, since they need to be compiled, but they do
        // not get directly incorporated into the build description that will be
        // given to LLBuild.
        var targetMap = IdentifiableSet<ModuleBuildDescription>()
        var pluginDescriptions = [PluginBuildDescription]()
        var shouldGenerateTestObservation = true

        let planningObservabilityScope = observabilityScope.makeChildScope(description: "Planning")
        try await Self.computeDestinations(
            graph: graph,
            onProduct: { product, destination in
                if !product.shouldCreateProductDescription {
                    return
                }

                guard let package = graph.package(for: product) else {
                    throw InternalError("Package not found for product: \(product.name)")
                }

                try productMap.insert(ProductBuildDescription(
                    package: package,
                    product: product,
                    toolsVersion: package.manifest.toolsVersion,
                    buildParameters: destination == .host ? toolsBuildParameters : destinationBuildParameters,
                    fileSystem: fileSystem,
                    observabilityScope: planningObservabilityScope
                ))
            },
            onModule: { module, destination in
                guard let package = graph.package(for: module) else {
                    throw InternalError("Package not found for module: \(module.name)")
                }

                let buildParameters = destination == .host ? toolsBuildParameters : destinationBuildParameters

                // Validate the product dependencies of this target.
                for dependency in module.dependencies {
                    guard dependency.satisfies(buildParameters.buildEnvironment) else {
                        continue
                    }

                    switch dependency {
                    case .module: break
                    case .product(let product, _):
                        if buildParameters.triple.isDarwin() {
                            try BuildPlan.validateDeploymentVersionOfProductDependency(
                                product: product,
                                forTarget: module,
                                buildEnvironment: buildParameters.buildEnvironment,
                                observabilityScope: planningObservabilityScope
                                                        .makeChildScope(description: "Validate Deployment of Dependency")
                            )
                        }
                    }
                }

                if let pluginConfiguration, !buildParameters.shouldSkipBuilding {
                    let pluginInvocationResults = try await Self.invokeBuildToolPlugins(
                        for: module,
                        destination: destination,
                        configuration: pluginConfiguration,
                        buildParameters: toolsBuildParameters,
                        modulesGraph: graph,
                        tools: pluginTools,
                        additionalFileRules: additionalFileRules,
                        pkgConfigDirectories: pkgConfigDirectories,
                        fileSystem: fileSystem,
                        observabilityScope: planningObservabilityScope,
                        surfaceDiagnostics: true
                    )

                    if pluginInvocationResults.contains(where: { !$0.succeeded }) {
                        throw StringError("build planning stopped due to build-tool plugin failures")
                    }

                    buildToolPluginInvocationResults[module.id] = pluginInvocationResults
                    prebuildCommandResults[module.id] = try Self.runCommandPlugins(
                        using: pluginConfiguration,
                        for: pluginInvocationResults,
                        fileSystem: fileSystem,
                        observabilityScope: planningObservabilityScope
                    )
                }

                switch module.underlying {
                case is SwiftModule:
                    var generateTestObservation = false
                    if module.type == .test && shouldGenerateTestObservation {
                        generateTestObservation = true
                        shouldGenerateTestObservation = false // Only generate the code once.
                    }

                    try targetMap.insert(.swift(
                        SwiftModuleBuildDescription(
                            package: package,
                            target: module,
                            toolsVersion: package.manifest.toolsVersion,
                            additionalFileRules: additionalFileRules,
                            buildParameters: buildParameters,
                            macroBuildParameters: toolsBuildParameters,
                            buildToolPluginInvocationResults: buildToolPluginInvocationResults[module.id] ?? [],
                            prebuildCommandResults: prebuildCommandResults[module.id] ?? [],
                            shouldGenerateTestObservation: generateTestObservation,
                            shouldDisableSandbox: disableSandbox,
                            fileSystem: fileSystem,
                            observabilityScope: planningObservabilityScope
                        )
                    ))
                case is ClangModule:
                    try targetMap.insert(.clang(
                        ClangModuleBuildDescription(
                            package: package,
                            target: module,
                            toolsVersion: package.manifest.toolsVersion,
                            additionalFileRules: additionalFileRules,
                            buildParameters: buildParameters,
                            buildToolPluginInvocationResults: buildToolPluginInvocationResults[module.id] ?? [],
                            prebuildCommandResults: prebuildCommandResults[module.id] ?? [],
                            fileSystem: fileSystem,
                            observabilityScope: planningObservabilityScope
                        )
                    ))
                case is PluginModule:
                    try module.dependencies.compactMap {
                        switch $0 {
                        case .module(let moduleDependency, _):
                            if moduleDependency.type == .executable {
                                return graph.product(for: moduleDependency.name)
                            }
                            return nil
                        default:
                            return nil
                        }
                    }.forEach {
                        try productMap.insert(ProductBuildDescription(
                            package: package,
                            product: $0,
                            toolsVersion: package.manifest.toolsVersion,
                            buildParameters: toolsBuildParameters,
                            fileSystem: fileSystem,
                            observabilityScope: planningObservabilityScope
                        ))
                    }

                    try pluginDescriptions.append(PluginBuildDescription(
                        module: module,
                        products: package.products.filter { $0.modules.contains(id: module.id) },
                        package: package,
                        toolsVersion: package.manifest.toolsVersion,
                        fileSystem: fileSystem
                    ))
                case is SystemLibraryModule, is BinaryModule:
                    break
                default:
                    throw InternalError("unhandled \(module.underlying)")
                }
            }
        )

        /// Ensure we have at least one buildable target.
        guard !targetMap.isEmpty else {
            throw Error.noBuildableTarget
        }

        // Abort now if we have any diagnostics at this point.
        guard !planningObservabilityScope.errorsReported else {
            throw Diagnostics.fatalError
        }

        self.observabilityScope = observabilityScope.makeChildScope(description: "Build Plan")

        // Plan the derived test targets, if necessary.
        let derivedTestTargets = try Self.makeDerivedTestTargets(
            testProducts: productMap.filter {
                $0.product.type == .test
            },
            destinationBuildParameters: destinationBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            shouldDisableSandbox: self.shouldDisableSandbox,
            self.fileSystem,
            self.observabilityScope
        )
        for item in derivedTestTargets {
            var derivedTestTargets = [item.entryPointTargetBuildDescription.target]

            targetMap.insert(.swift(
                item.entryPointTargetBuildDescription
            ))

            if let discoveryTargetBuildDescription = item.discoveryTargetBuildDescription {
                targetMap.insert(.swift(discoveryTargetBuildDescription))
                derivedTestTargets.append(discoveryTargetBuildDescription.target)
            }

            self.derivedTestTargetsMap[item.product.id] = derivedTestTargets
        }

        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults

        self.productMap = productMap
        self.targetMap = targetMap
        self.pluginDescriptions = pluginDescriptions

        // Finally plan these targets.
        try self.plan()
    }

    static func validateDeploymentVersionOfProductDependency(
        product: ResolvedProduct,
        forTarget target: ResolvedModule,
        buildEnvironment: BuildEnvironment,
        observabilityScope: ObservabilityScope
    ) throws {
        // Supported platforms are defined at the package (e.g., build environment) level.
        // This will need to become a bit complicated once we have target-level or product-level platform support.
        let productPlatform = product.getSupportedPlatform(
            for: buildEnvironment.platform,
            usingXCTest: product.isLinkingXCTest
        )
        let targetPlatform = target.getSupportedPlatform(
            for: buildEnvironment.platform,
            usingXCTest: target.type == .test
        )

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
        for buildTarget in self.targets {
            switch buildTarget {
            case .swift(let target):
                try self.plan(swiftTarget: target)
            case .clang(let target):
                try self.plan(clangTarget: target)
            }
        }

        // Plan products.
        for buildProduct in self.buildProducts {
            try self.plan(buildProduct: buildProduct as! ProductBuildDescription)
        }
        // FIXME: We need to find out if any product has a target on which it depends
        // both static and dynamically and then issue a suitable diagnostic or auto
        // handle that situation.

        // Ensure modules in Windows DLLs export their symbols
        for product in productMap.values where product.product.type == .library(.dynamic) && product.buildParameters.triple.isWindows() {
            for target in product.product.modules {
                let targetId: ModuleBuildDescription.ID = .init(moduleID: target.id, destination: product.buildParameters.destination)
                if case let .swift(buildDescription) = targetMap[targetId] {
                    buildDescription.isWindowsStatic = false
                }
            }
        }
    }

    public func createAPIToolCommonArgs(includeLibrarySearchPaths: Bool) throws -> [String] {
        // API tool runs on products, hence using `self.productsBuildParameters`, not `self.toolsBuildParameters`
        let buildPath = self.destinationBuildParameters.buildPath.pathString
        var arguments = ["-I", buildPath]

        // swift-symbolgraph-extract does not support parsing `-use-ld=lld` and
        // will silently error failing the operation.  Filter out this flag
        // similar to how we filter out the library search path unless
        // explicitly requested.
        var extraSwiftCFlags = self.destinationBuildParameters.toolchain.extraFlags.swiftCompilerFlags
            .filter { !$0.starts(with: "-use-ld=") }
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

        // Add search paths to the directories containing module maps and Swift modules.
        for target in self.targets {
            switch target {
            case .swift(let targetDescription):
                arguments += ["-I", targetDescription.moduleOutputPath.parentDirectory.pathString]
            case .clang(let targetDescription):
                if let includeDir = targetDescription.moduleMap?.parentDirectory {
                    arguments += ["-I", includeDir.pathString]
                }
                arguments += ["-I", targetDescription.clangTarget.includeDir.pathString]
            }
        }

        // Add search paths from the system library targets.
        for target in self.graph.reachableModules {
            if let systemLib = target.underlying as? SystemLibraryModule {
                try arguments.append(contentsOf: self.pkgConfig(for: systemLib).cFlags)
                // Add the path to the module map.
                arguments += ["-I", systemLib.moduleMapPath.parentDirectory.pathString]
            }
        }

        return arguments
    }

    /// Creates arguments required to launch the Swift REPL that will allow
    /// importing the modules in the package graph.
    public func createREPLArguments() throws -> [String] {
        let buildPath = self.toolsBuildParameters.buildPath.pathString
        var arguments = ["repl", "-I" + buildPath, "-L" + buildPath]

        // Link the special REPL product that contains all of the library targets.
        let replProductName = self.graph.rootPackages[self.graph.rootPackages.startIndex].identity.description +
            Product.replProductSuffix
        arguments.append("-l" + replProductName)

        // The graph should have the REPL product.
        assert(self.graph.product(for: replProductName) != nil)

        // Add the search path to the directory containing the modulemap file.
        for target in self.targets {
            switch target {
            case .swift: break
            case .clang(let targetDescription):
                if let includeDir = targetDescription.moduleMap?.parentDirectory {
                    arguments += ["-I\(includeDir.pathString)"]
                }
            }
        }

        // Add search paths from the system library targets.
        for target in self.graph.reachableModules {
            if let systemLib = target.underlying as? SystemLibraryModule {
                arguments += try self.pkgConfig(for: systemLib).cFlags
            }
        }

        return arguments
    }

    /// Get pkgConfig arguments for a system library target.
    func pkgConfig(for target: SystemLibraryModule) throws -> (cFlags: [String], libs: [String]) {
        // If we already have these flags, we're done.
        if let flags = pkgConfigCache[target] {
            return flags
        } else {
            self.pkgConfigCache[target] = ([], [])
        }
        let results = try pkgConfigArgs(
            for: target,
            pkgConfigDirectories: self.destinationBuildParameters.pkgConfigDirectories,
            sdkRootPath: self.destinationBuildParameters.toolchain.sdkRootPath,
            fileSystem: self.fileSystem,
            observabilityScope: self.observabilityScope
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
        self.pkgConfigCache[target] = result
        return result
    }

    /// Extracts the library information from an XCFramework.
    func parseXCFramework(for binaryTarget: BinaryModule, triple: Basics.Triple) throws -> [LibraryInfo] {
        try self.externalLibrariesCache.memoize(key: binaryTarget) {
            try binaryTarget.parseXCFrameworks(for: triple, fileSystem: self.fileSystem)
        }
    }

    /// Returns the files and directories that affect the build process of this build plan.
    package var inputs: [Input] {
        var inputs: [Input] = []
        for package in self.graph.rootPackages {
            inputs += package.modules
                .map(\.sources.root)
                .sorted()
                .map { .directoryStructure($0) }

            // Add the output paths of any prebuilds that were run, so that we redo the plan if they change.
            var derivedSourceDirPaths: [Basics.AbsolutePath] = []
            for result in self.prebuildCommandResults.values.flatMap({ $0 }) {
                derivedSourceDirPaths.append(contentsOf: result.outputDirectories)
            }
            inputs.append(contentsOf: derivedSourceDirPaths.sorted().map { .directoryStructure($0) })

            // FIXME: Need to handle version-specific manifests.
            inputs.append(.file(package.manifest.path))

            // FIXME: This won't be the location of Package.resolved for multiroot packages.
            inputs.append(.file(package.path.appending("Package.resolved")))

            // FIXME: Add config file as an input

        }
        return inputs
    }

    public func description(
        for product: ResolvedProduct,
        context: BuildParameters.Destination
    ) -> ProductBuildDescription? {
        let destination: BuildParameters.Destination = switch product.type {
        case .macro, .plugin:
            .host
        default:
            context
        }

        return self.productMap[.init(productID: product.id, destination: destination)]
    }

    public func description(
        for module: ResolvedModule,
        context: BuildParameters.Destination
    ) -> ModuleBuildDescription? {
        let destination: BuildParameters.Destination = switch module.type {
        case .macro, .plugin:
            .host
        default:
            context
        }

        return self.targetMap[.init(moduleID: module.id, destination: destination)]
    }
}

extension BuildPlan {
    /// Applies plugins to the given module as needed. Each plugin is passed an input context that provides
    /// information about the module to which it is being applied (along with some information about that
    /// module's dependency closure). The plugin is expected to generate an output in the form of commands
    /// that will later be run before or during the build, and can also emit debug output and diagnostics.
    ///
    /// Each result returned by this function includes an ordered list of commands to run before the build
    /// of the module, and another list of the commands to incorporate into the build graph so they run
    /// at the appropriate times during the build.
    ///
    /// Any warnings and errors related to running the plugin will be emitted to `diagnostics` when
    /// `surfaceDiagnostics` parameter is set to `true`.
    ///
    /// Note that warnings emitted by the the plugin itself will be returned in the `BuildToolPluginInvocationResult`
    /// structures for later showing to the user, and not added directly to the diagnostics engine.
    static func invokeBuildToolPlugins(
        for module: ResolvedModule,
        destination: BuildParameters.Destination,
        configuration: PluginConfiguration,
        buildParameters: BuildParameters,
        modulesGraph: ModulesGraph,
        tools: [ResolvedModule.ID: [String: PluginTool]],
        additionalFileRules: [FileRuleDescription],
        pkgConfigDirectories: [Basics.AbsolutePath],
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
        surfaceDiagnostics: Bool = false
    ) async throws -> [BuildToolPluginInvocationResult] {
        let outputDir = configuration.workDirectory.appending("outputs")

        /// Determine the package that contains the target.
        guard let package = modulesGraph.package(for: module) else {
            throw InternalError("could not determine package for module \(self)")
        }

        // Apply each build tool plugin used by the target in order,
        // creating a list of results (one for each plugin usage).
        var buildToolPluginResults: [BuildToolPluginInvocationResult] = []
        for plugin in module.pluginDependencies(satisfying: buildParameters.buildEnvironment) {
            let pluginModule = plugin.underlying as! PluginModule

            // Determine the tools to which this plugin has access, and create a name-to-path mapping from tool
            // names to the corresponding paths. Built tools are assumed to be in the build tools directory.
            guard let accessibleTools = tools[plugin.id] else {
                throw InternalError("No tools found for plugin \(plugin.name)")
            }

            // Assign a plugin working directory based on the package, target, and plugin.
            let pluginOutputDir = outputDir.appending(
                components: [
                    package.identity.description,
                    module.name,
                    destination == .host ? "tools" : "destination",
                    plugin.name,
                ]
            )

            // Determine the set of directories under which plugins are allowed to write.
            // We always include just the output directory, and for now there is no possibility
            // of opting into others.
            let writableDirectories = [outputDir]

            // Determine a set of further directories under which plugins are never allowed
            // to write, even if they are covered by other rules (such as being able to write
            // to the temporary directory).
            let readOnlyDirectories = [package.path]

            // In tools version 6.0 and newer, we vend the list of files generated by previous plugins.
            let pluginDerivedSources: Sources
            let pluginDerivedResources: [Resource]
            if package.manifest.toolsVersion >= .v6_0 {
                // Set up dummy observability because we don't want to emit diagnostics for this before the actual
                // build.
                let observability = ObservabilitySystem { _, _ in }
                // Compute the generated files based on all results we have computed so far.
                (pluginDerivedSources, pluginDerivedResources) = ModulesGraph.computePluginGeneratedFiles(
                    target: module,
                    toolsVersion: package.manifest.toolsVersion,
                    additionalFileRules: additionalFileRules,
                    buildParameters: buildParameters,
                    buildToolPluginInvocationResults: buildToolPluginResults,
                    prebuildCommandResults: [],
                    observabilityScope: observability.topScope
                )
            } else {
                pluginDerivedSources = .init(paths: [], root: package.path)
                pluginDerivedResources = []
            }

            let result = try await pluginModule.invoke(
                module: plugin,
                action: .createBuildToolCommands(
                    package: package,
                    target: module,
                    pluginGeneratedSources: pluginDerivedSources.paths,
                    pluginGeneratedResources: pluginDerivedResources.map(\.path)
                ),
                buildEnvironment: buildParameters.buildEnvironment,
                scriptRunner: configuration.scriptRunner,
                workingDirectory: package.path,
                outputDirectory: pluginOutputDir,
                toolSearchDirectories: [buildParameters.toolchain.swiftCompilerPath.parentDirectory],
                accessibleTools: accessibleTools,
                writableDirectories: writableDirectories,
                readOnlyDirectories: readOnlyDirectories,
                allowNetworkConnections: [],
                pkgConfigDirectories: pkgConfigDirectories,
                sdkRootPath: buildParameters.toolchain.sdkRootPath,
                fileSystem: fileSystem,
                modulesGraph: modulesGraph,
                observabilityScope: observabilityScope
            )


            if surfaceDiagnostics {
                let diagnosticsEmitter = observabilityScope.makeDiagnosticsEmitter {
                    var metadata = ObservabilityMetadata()
                    metadata.moduleName = module.name
                    metadata.pluginName = result.plugin.name
                    return metadata
                }

                for line in result.textOutput.split(whereSeparator: { $0.isNewline }) {
                    diagnosticsEmitter.emit(info: line)
                }

                for diag in result.diagnostics {
                    diagnosticsEmitter.emit(diag)
                }
            }

            // Add a BuildToolPluginInvocationResult to the mapping.
            buildToolPluginResults.append(result)
        }

        return buildToolPluginResults
    }

    /// Runs any command plugins associated with the given list of plugin invocation results,
    /// in order, and returns the results of running those prebuild commands.
    fileprivate static func runCommandPlugins(
        using pluginConfiguration: PluginConfiguration,
        for pluginResults: [BuildToolPluginInvocationResult],
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> [CommandPluginResult] {
        // Run through all the commands from all the plugin usages in the target.
        try pluginResults.map { pluginResult in
            // As we go we will collect a list of prebuild output directories whose contents should be input to the
            // build, and a list of the files in those directories after running the commands.
            var derivedFiles: [Basics.AbsolutePath] = []
            var prebuildOutputDirs: [Basics.AbsolutePath] = []
            for command in pluginResult.prebuildCommands {
                observabilityScope
                    .emit(
                        info: "Running " +
                            (command.configuration.displayName ?? command.configuration.executable.basename)
                    )

                // Run the command configuration as a subshell. This doesn't return until it is done.
                // TODO: We need to also use any working directory, but that support isn't yet available on all platforms at a lower level.
                var commandLine = [command.configuration.executable.pathString] + command.configuration.arguments
                if !pluginConfiguration.disableSandbox {
                    commandLine = try Sandbox.apply(
                        command: commandLine,
                        fileSystem: fileSystem,
                        strictness: .writableTemporaryDirectory,
                        writableDirectories: [pluginResult.pluginOutputDirectory]
                    )
                }
                let processResult = try AsyncProcess.popen(
                    arguments: commandLine,
                    environment: command.configuration.environment
                )
                let output = try processResult.utf8Output() + processResult.utf8stderrOutput()
                if processResult.exitStatus != .terminated(code: 0) {
                    throw StringError("failed: \(command)\n\n\(output)")
                }

                // Add any files found in the output directory declared for the prebuild command after the command ends.
                let outputFilesDir = command.outputFilesDirectory
                if let swiftFiles = try? fileSystem.getDirectoryContents(outputFilesDir).sorted() {
                    derivedFiles.append(contentsOf: swiftFiles.map { outputFilesDir.appending(component: $0) })
                }

                // Add the output directory to the list of directories whose structure should affect the build plan.
                prebuildOutputDirs.append(outputFilesDir)
            }

            // Add the results of running any prebuild commands for this invocation.
            return CommandPluginResult(derivedFiles: derivedFiles, outputDirectories: prebuildOutputDirs)
        }
    }
}

extension BuildPlan {
    fileprivate typealias Destination = BuildParameters.Destination

    enum TraversalNode: Hashable {
        case package(ResolvedPackage)
        case product(ResolvedProduct, BuildParameters.Destination)
        case module(ResolvedModule, BuildParameters.Destination)

        var destination: BuildParameters.Destination {
            switch self {
            case .package:
                .target
            case .product(_, let destination):
                destination
            case .module(_, let destination):
                destination
            }
        }

        init(
            product: ResolvedProduct,
            context destination: BuildParameters.Destination
        ) {
            switch product.type {
            case .macro, .plugin:
                self = .product(product, .host)
            case .test:
                self = .product(product, product.hasDirectMacroDependencies ? .host : destination)
            default:
                self = .product(product, destination)
            }
        }

        init(
            module: ResolvedModule,
            context destination: BuildParameters.Destination
        ) {
            switch module.type {
            case .macro, .plugin:
                // Macros and plugins are ways built for host
                self = .module(module, .host)
            case .test:
                self = .module(module, module.hasDirectMacroDependencies ? .host : destination)
            default:
                // By default assume the destination of the context.
                // This means that i.e. test products that reference macros
                // would force all of their successors to be `host`
                self = .module(module, destination)
            }
        }
    }

    /// Traverse the modules graph and find a destination for every product and module.
    /// All non-macro/plugin products and modules have `target` destination with one
    /// notable exception - test products/modules with direct macro dependency.
    fileprivate static func computeDestinations(
        graph: ModulesGraph,
        onProduct: (ResolvedProduct, Destination) throws -> Void,
        onModule: (ResolvedModule, Destination) async throws -> Void
    ) async rethrows {
        func successors(for package: ResolvedPackage) -> [TraversalNode] {
            var successors: [TraversalNode] = []
            for product in package.products {
                if case .test = product.underlying.type,
                   !graph.rootPackages.contains(id: package.id)
                {
                    continue
                }

                successors.append(.init(product: product, context: .target))
            }

            for module in package.modules {
                // Tests are discovered through an aggregate product which also
                // informs their destination.
                if case .test = module.underlying.type {
                    continue
                }

                successors.append(.init(module: module, context: .target))
            }

            return successors
        }

        func successors(
            for product: ResolvedProduct,
            destination: Destination
        ) -> [TraversalNode] {
            guard destination == .host || product.underlying.type == .test else {
                return []
            }

            return product.modules.map { module in
                TraversalNode(module: module, context: destination)
            }
        }

        func successors(
            for module: ResolvedModule,
            destination: Destination
        ) -> [TraversalNode] {
            guard destination == .host else {
                return []
            }

            return module.dependencies.reduce(into: [TraversalNode]()) { partial, dependency in
                switch dependency {
                case .product(let product, conditions: _):
                    partial.append(.init(product: product, context: destination))
                case .module(let module, _):
                    partial.append(.init(module: module, context: destination))
                }
            }
        }

        try await depthFirstSearch(graph.packages.map { TraversalNode.package($0) }) { node in
            switch node {
            case .package(let package):
                successors(for: package)
            case .product(let product, let destination):
                successors(for: product, destination: destination)
            case .module(let module, let destination):
                successors(for: module, destination: destination)
            }
        } onUnique: {
            switch $0 {
            case .package:
                break
            case .product(let product, let destination):
                try onProduct(product, destination)

            case .module(let module, let destination):
                try await onModule(module, destination)
            }
        } onDuplicate: { _, _ in
            // No de-duplication is necessary we only want unique nodes.
        }
    }

    /// Traverses the modules graph, computes destination of every module reference and
    /// provides the data to the caller by means of `onModule` callback. The products
    /// are completely transparent to this method and are represented by their module dependencies.
    package func traverseModules(
        _ onModule: (
            (ResolvedModule, BuildParameters.Destination),
            _ parent: (ResolvedModule, BuildParameters.Destination)?
        ) -> Void
    ) {
        var visited = Set<TraversalNode>()

        func successors(for package: ResolvedPackage) -> [TraversalNode] {
            guard visited.insert(.package(package)).inserted else {
                return []
            }
            return package.modules.compactMap {
                if case .test = $0.underlying.type,
                   !self.graph.rootPackages.contains(id: package.id)
                {
                    return nil
                }
                return .init(module: $0, context: .target)
            }
        }

        func successors(
            for module: ResolvedModule,
            destination: Destination
        ) -> [TraversalNode] {
            guard visited.insert(.module(module, destination)).inserted else {
                return []
            }
            return module.dependencies.reduce(into: [TraversalNode]()) { partial, dependency in
                switch dependency {
                case .product(let product, conditions: _):
                    let parent = TraversalNode(product: product, context: destination)
                    for module in product.modules {
                        partial.append(.init(module: module, context: parent.destination))
                    }
                case .module(let module, _):
                    partial.append(.init(module: module, context: destination))
                }
            }
        }

        depthFirstSearch(self.graph.packages.map { TraversalNode.package($0) }) {
            switch $0 {
            case .package(let package):
                successors(for: package)
            case .module(let module, let destination):
                successors(for: module, destination: destination)
            case .product:
                []
            }
        } onNext: { current, parent in
            let parentModule: (ResolvedModule, BuildParameters.Destination)? = switch parent {
            case .package, .product, nil:
                nil
            case .module(let module, let destination):
                (module, destination)
            }

            switch current {
            case .package, .product:
                break

            case .module(let module, let destination):
                onModule((module, destination), parentModule)
            }
        }
    }

    package func traverseDependencies(
        of description: ModuleBuildDescription,
        onProduct: (ResolvedProduct, BuildParameters.Destination, ProductBuildDescription?) -> DepthFirstContinue,
        onModule: (ResolvedModule, BuildParameters.Destination, ModuleBuildDescription?) -> DepthFirstContinue
    ) {
        var visited = Set<TraversalNode>()
        func successors(
            for product: ResolvedProduct,
            destination: Destination
        ) -> [TraversalNode] {
            product.modules.map { module in
                TraversalNode(module: module, context: destination)
            }.filter {
                visited.insert($0).inserted
            }
        }

        func successors(
            for module: ResolvedModule,
            destination: Destination
        ) -> [TraversalNode] {
            module
                .dependencies(satisfying: description.buildParameters.buildEnvironment)
                .reduce(into: [TraversalNode]()) { partial, dependency in
                    switch dependency {
                    case .product(let product, _):
                        partial.append(.init(product: product, context: destination))
                    case .module(let module, _):
                        partial.append(.init(module: module, context: destination))
                    }
                }.filter {
                    visited.insert($0).inserted
                }
        }

        depthFirstSearch(successors(for: description.module, destination: description.destination)) {
            switch $0 {
            case .module(let module, let destination):
                successors(for: module, destination: destination)
            case .product(let product, let destination):
                successors(for: product, destination: destination)
            case .package:
                []
            }
        } visitNext: { module, _ in
            switch module {
            case .package:
                return .continue

            case .product(let product, let destination):
                return onProduct(product, destination, self.description(for: product, context: destination))

            case .module(let module, let destination):
                return onModule(module, destination, self.description(for: module, context: destination))
            }
        }
    }
}

extension Basics.Diagnostic {
    static var swiftBackDeployError: Self {
        .warning(
            """
            Swift compiler no longer supports statically linking the Swift libraries. They're included in the OS by \
            default starting with macOS Mojave 10.14.4 beta 3. For macOS Mojave 10.14.3 and earlier, there's an \
            optional Swift library package that can be downloaded from \"More Downloads\" for Apple Developers at \
            https://developer.apple.com/download/more/
            """
        )
    }

    static func productRequiresHigherPlatformVersion(
        target: ResolvedModule,
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

    static func binaryTargetsNotSupported() -> Self {
        .error("binary targets are not supported on this platform")
    }
}

extension BuildParameters {
    /// Returns a named bundle's path inside the build directory.
    func bundlePath(named name: String) -> Basics.AbsolutePath {
        self.buildPath.appending(component: name + self.triple.nsbundleExtension)
    }
}

/// Generate the resource bundle Info.plist.
func generateResourceInfoPlist(
    fileSystem: FileSystem,
    target: ResolvedModule,
    path: Basics.AbsolutePath
) throws -> Bool {
    guard let defaultLocalization = target.defaultLocalization else {
        return false
    }

    try fileSystem.writeIfChanged(
        path: path,
        string: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>\(defaultLocalization)</string>
        </dict>
        </plist>
        """
    )
    return true
}

extension Basics.Triple {
    var isSupportingStaticStdlib: Bool {
        isLinux() || arch == .wasm32
    }
}

extension ResolvedPackage {
    var isRemote: Bool {
        switch self.underlying.manifest.packageKind {
        case .registry, .remoteSourceControl, .localSourceControl:
            return true
        case .root, .fileSystem:
            return false
        }
    }
}

extension ResolvedProduct {
    private var isAutomaticLibrary: Bool {
        self.type == .library(.automatic)
    }

    private var isBinaryOnly: Bool {
        self.modules.filter { !($0.underlying is BinaryModule) }.isEmpty
    }

    private var isPlugin: Bool {
        self.type == .plugin
    }

    // We shouldn't create product descriptions for automatic libraries, plugins or products which consist solely of
    // binary targets, because they don't produce any output.
    fileprivate var shouldCreateProductDescription: Bool {
        !self.isAutomaticLibrary && !self.isBinaryOnly && !self.isPlugin
    }
}
