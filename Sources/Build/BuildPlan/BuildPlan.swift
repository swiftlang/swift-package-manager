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

import Basics
import Foundation
import LLBuildManifest
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore

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
    public var moduleCache: AbsolutePath {
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
        if self.triple.isApple() {
            args = ["-alias", "_\(target.c99name)_main", "_main"]
        } else if self.triple.isLinux() {
            args = ["--defsym", "main=\(target.c99name)_main"]
        } else {
            return nil
        }
        return args.asSwiftcLinkerFlags()
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
        case directoryStructure(AbsolutePath)
        /// The file at the given path affects the build plan
        case file(AbsolutePath)
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
    public let targetMap: [ResolvedModule.ID: ModuleBuildDescription]

    /// The product build description map.
    public let productMap: [ResolvedProduct.ID: ProductBuildDescription]

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

    /// The results of invoking any build tool plugins used by targets in this build.
    public let buildToolPluginInvocationResults: [ResolvedModule.ID: [BuildToolPluginInvocationResult]]

    /// The results of running any prebuild commands for the targets in this build.  This includes any derived
    /// source files as well as directories to which any changes should cause us to reevaluate the build plan.
    public let prebuildCommandResults: [ResolvedModule.ID: [PrebuildCommandResult]]

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
    ) throws {
        try self.init(
            destinationBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            graph: graph,
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
        additionalFileRules: [FileRuleDescription] = [],
        buildToolPluginInvocationResults: [ResolvedModule.ID: [BuildToolPluginInvocationResult]] = [:],
        prebuildCommandResults: [ResolvedModule.ID: [PrebuildCommandResult]] = [:],
        disableSandbox: Bool = false,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        self.destinationBuildParameters = destinationBuildParameters
        self.toolsBuildParameters = toolsBuildParameters
        self.graph = graph
        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults
        self.shouldDisableSandbox = disableSandbox
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "Build Plan")

        var productMap: [ResolvedProduct.ID: (product: ResolvedProduct, buildDescription: ProductBuildDescription)] =
            [:]
        // Create product description for each product we have in the package graph that is eligible.
        for product in graph.allProducts where product.shouldCreateProductDescription {
            let buildParameters: BuildParameters
            switch product.buildTriple {
            case .tools:
                buildParameters = toolsBuildParameters
            case .destination:
                buildParameters = destinationBuildParameters
            }

            guard let package = graph.package(for: product) else {
                throw InternalError("unknown package for \(product)")
            }
            // Determine the appropriate tools version to use for the product.
            // This can affect what flags to pass and other semantics.
            let toolsVersion = package.manifest.toolsVersion
            productMap[product.id] = try (product, ProductBuildDescription(
                package: package,
                product: product,
                toolsVersion: toolsVersion,
                buildParameters: buildParameters,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            ))
        }
        let macroProductsByTarget = productMap.values.filter { $0.product.type == .macro }
            .reduce(into: [ResolvedModule.ID: ResolvedProduct]()) {
                if let target = $1.product.modules.first {
                    $0[target.id] = $1.product
                }
            }

        // Create build target description for each target which we need to plan.
        // Plugin targets are noted, since they need to be compiled, but they do
        // not get directly incorporated into the build description that will be
        // given to LLBuild.
        var targetMap = [ResolvedModule.ID: ModuleBuildDescription]()
        var pluginDescriptions = [PluginBuildDescription]()
        var shouldGenerateTestObservation = true
        for target in graph.allModules.sorted(by: { $0.name < $1.name }) {
            let buildParameters: BuildParameters
            switch target.buildTriple {
            case .tools:
                buildParameters = toolsBuildParameters
            case .destination:
                buildParameters = destinationBuildParameters
            }

            // Validate the product dependencies of this target.
            for dependency in target.dependencies {
                guard dependency.satisfies(buildParameters.buildEnvironment) else {
                    continue
                }

                switch dependency {
                case .module: break
                case .product(let product, _):
                    if buildParameters.triple.isDarwin() {
                        try BuildPlan.validateDeploymentVersionOfProductDependency(
                            product: product,
                            forTarget: target,
                            buildEnvironment: buildParameters.buildEnvironment,
                            observabilityScope: self.observabilityScope
                        )
                    }
                }
            }

            // Determine the appropriate tools version to use for the target.
            // This can affect what flags to pass and other semantics.
            let toolsVersion = graph.package(for: target)?.manifest.toolsVersion ?? .v5_5

            switch target.underlying {
            case is SwiftModule:
                guard let package = graph.package(for: target) else {
                    throw InternalError("package not found for \(target)")
                }

                let requiredMacroProducts = try target.recursiveModuleDependencies()
                    .filter { $0.underlying.type == .macro }
                    .compactMap {
                        guard let product = macroProductsByTarget[$0.id],
                              let description = productMap[product.id] else
                        {
                            throw InternalError("macro product not found for \($0)")
                        }

                        return description.buildDescription
                    }

                var generateTestObservation = false
                if target.type == .test && shouldGenerateTestObservation {
                    generateTestObservation = true
                    shouldGenerateTestObservation = false // Only generate the code once.
                }

                targetMap[target.id] = try .swift(
                    SwiftModuleBuildDescription(
                        package: package,
                        target: target,
                        toolsVersion: toolsVersion,
                        additionalFileRules: additionalFileRules,
                        buildParameters: buildParameters,
                        buildToolPluginInvocationResults: buildToolPluginInvocationResults[target.id] ?? [],
                        prebuildCommandResults: prebuildCommandResults[target.id] ?? [],
                        requiredMacroProducts: requiredMacroProducts,
                        shouldGenerateTestObservation: generateTestObservation,
                        shouldDisableSandbox: self.shouldDisableSandbox,
                        fileSystem: fileSystem,
                        observabilityScope: observabilityScope
                    )
                )
            case is ClangModule:
                guard let package = graph.package(for: target) else {
                    throw InternalError("package not found for \(target)")
                }

                targetMap[target.id] = try .clang(
                    ClangModuleBuildDescription(
                        package: package,
                        target: target,
                        toolsVersion: toolsVersion,
                        additionalFileRules: additionalFileRules,
                        buildParameters: buildParameters,
                        buildToolPluginInvocationResults: buildToolPluginInvocationResults[target.id] ?? [],
                        prebuildCommandResults: prebuildCommandResults[target.id] ?? [],
                        fileSystem: fileSystem,
                        observabilityScope: observabilityScope
                    )
                )
            case is PluginModule:
                guard let package = graph.package(for: target) else {
                    throw InternalError("package not found for \(target)")
                }
                try pluginDescriptions.append(PluginBuildDescription(
                    module: target,
                    products: package.products.filter { $0.modules.contains(id: target.id) },
                    package: package,
                    toolsVersion: toolsVersion,
                    fileSystem: fileSystem
                ))
            case is SystemLibraryModule, is BinaryModule, is ProvidedLibraryModule:
                break
            default:
                throw InternalError("unhandled \(target.underlying)")
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
        let derivedTestTargets = try Self.makeDerivedTestTargets(
            testProducts: productMap.values.filter {
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

            targetMap[item.entryPointTargetBuildDescription.target.id] = .swift(
                item.entryPointTargetBuildDescription
            )

            if let discoveryTargetBuildDescription = item.discoveryTargetBuildDescription {
                targetMap[discoveryTargetBuildDescription.target.id] = .swift(discoveryTargetBuildDescription)
                derivedTestTargets.append(discoveryTargetBuildDescription.target)
            }

            self.derivedTestTargetsMap[item.product.id] = derivedTestTargets
        }

        self.productMap = productMap.mapValues(\.buildDescription)
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
        assert(self.graph.product(for: replProductName, destination: .destination) != nil)

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

    /// Determines the arguments needed to run `swift-symbolgraph-extract` for
    /// a particular module.
    public func symbolGraphExtractArguments(for module: ResolvedModule) throws -> [String] {
        guard let description = self.targetMap[module.id] else {
            throw InternalError("Expected description for module \(module)")
        }
        return try description.symbolGraphExtractArguments()
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
            var derivedSourceDirPaths: [AbsolutePath] = []
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
    func bundlePath(named name: String) -> AbsolutePath {
        self.buildPath.appending(component: name + self.triple.nsbundleExtension)
    }
}

/// Generate the resource bundle Info.plist.
func generateResourceInfoPlist(
    fileSystem: FileSystem,
    target: ResolvedModule,
    path: AbsolutePath
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
