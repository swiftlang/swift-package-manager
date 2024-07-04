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
import PackageGraph
import PackageLoading
import PackageModel

@_spi(SwiftPMInternal)
import SPMBuildCore

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import DriverSupport
#else
import DriverSupport
#endif

import struct TSCBasic.ByteString

@available(*, deprecated, renamed: "SwiftModuleBuildDescription")
public typealias SwiftTargetBuildDescription = SwiftModuleBuildDescription

/// Build description for a Swift module.
public final class SwiftModuleBuildDescription {
    /// The package this target belongs to.
    public let package: ResolvedPackage

    /// The target described by this target.
    public let target: ResolvedModule

    private let swiftTarget: SwiftModule

    /// The tools version of the package that declared the target.  This can
    /// can be used to conditionalize semantically significant changes in how
    /// a target is built.
    public let toolsVersion: ToolsVersion

    /// The build parameters for this target.
    let buildParameters: BuildParameters

    /// Path to the temporary directory for this target.
    let tempsPath: AbsolutePath

    /// The directory containing derived sources of this target.
    ///
    /// These are the source files generated during the build.
    private var derivedSources: Sources

    /// These are the source files derived from plugins.
    private var pluginDerivedSources: Sources

    /// These are the resource files derived from plugins.
    private var pluginDerivedResources: [Resource]

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        if let bundleName = target.underlying.potentialBundleName, needsResourceBundle {
            let suffix = self.buildParameters.suffix
            return self.buildParameters.bundlePath(named: bundleName + suffix)
        } else {
            return nil
        }
    }

    private var needsResourceBundle: Bool {
        return resources.filter { $0.rule != .embedInCode }.isEmpty == false
    }

    var resourceFilesToEmbed: [AbsolutePath] {
        return resources.filter { $0.rule == .embedInCode }.map { $0.path }
    }

    /// The path to Swift source file embedding resource contents if needed.
    private(set) var resourcesEmbeddingSource: AbsolutePath?

    /// The list of all source files in the target, including the derived ones.
    public var sources: [AbsolutePath] {
        self.target.sources.paths + self.derivedSources.paths + self.pluginDerivedSources.paths
    }

    public var sourcesFileListPath: AbsolutePath {
        self.tempsPath.appending(component: "sources")
    }

    /// The list of all resource files in the target, including the derived ones.
    public var resources: [Resource] {
        self.target.underlying.resources + self.pluginDerivedResources
    }

    /// The objects in this target, containing either machine code or bitcode
    /// depending on the build parameters used.
    public var objects: [AbsolutePath] {
        get throws {
            let relativeSources = self.target.sources.relativePaths
                + self.derivedSources.relativePaths
                + self.pluginDerivedSources.relativePaths
            let ltoEnabled = self.buildParameters.linkingParameters.linkTimeOptimizationMode != nil
            let objectFileExtension = ltoEnabled ? "bc" : "o"
            return try relativeSources.map {
                try AbsolutePath(
                    validating: "\($0.basename).\(objectFileExtension)",
                    relativeTo: self.tempsPath)
            }
        }
    }

    var modulesPath: AbsolutePath {
        let suffix = self.buildParameters.suffix
        return self.buildParameters.buildPath.appending(component: "Modules\(suffix)")
    }

    /// The path to the swiftmodule file after compilation.
    public var moduleOutputPath: AbsolutePath { // note: needs to be public because of sourcekit-lsp
        // If we're an executable and we're not allowing test targets to link against us, we hide the module.
        let triple = buildParameters.triple
        let allowLinkingAgainstExecutables = (triple.isDarwin() || triple.isLinux() || triple.isWindows()) && self.toolsVersion >= .v5_5
        let dirPath = (target.type == .executable && !allowLinkingAgainstExecutables) ? self.tempsPath : self.modulesPath
        return dirPath.appending(component: "\(self.target.c99name).swiftmodule")
    }

    /// The path to the wrapped swift module which is created using the modulewrap tool. This is required
    /// for supporting debugging on non-Darwin platforms (On Darwin, we just pass the swiftmodule to the linker
    /// using the `-add_ast_path` flag).
    var wrappedModuleOutputPath: AbsolutePath {
        self.tempsPath.appending(component: self.target.c99name + ".swiftmodule.o")
    }

    /// The path to the swiftinterface file after compilation.
    var parseableModuleInterfaceOutputPath: AbsolutePath {
        self.modulesPath.appending(component: self.target.c99name + ".swiftinterface")
    }

    /// Path to the resource Info.plist file, if generated.
    public private(set) var resourceBundleInfoPlistPath: AbsolutePath?

    /// Paths to the binary libraries the target depends on.
    var libraryBinaryPaths: Set<AbsolutePath> = []

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    var additionalFlags: [String] = []

    /// Describes the purpose of a test target, including any special roles such as containing a list of discovered
    /// tests or serving as the manifest target which contains the main entry point.
    public enum TestTargetRole {
        /// An ordinary test target, defined explicitly in a package, containing test code.
        case `default`

        /// A test target which was synthesized automatically, containing a list of discovered tests
        /// from `plain` test targets.
        case discovery

        /// A test target which was either synthesized automatically and contains an entry point file configured to run
        /// all discovered tests, or contains a custom entry point file. In the latter case, the custom entry point file
        /// may have been discovered in the package automatically (e.g. `XCTMain.swift`) or may have been provided
        /// explicitly via a CLI flag.
        case entryPoint(isSynthesized: Bool)
    }

    public let testTargetRole: TestTargetRole?

    /// If this target is a test target.
    public var isTestTarget: Bool {
        self.testTargetRole != nil
    }

    /// True if this module needs to be parsed as a library based on the target type and the configuration
    /// of the source code
    var needsToBeParsedAsLibrary: Bool {
        switch self.target.type {
        case .library, .test:
            return true
        case .executable, .snippet, .macro:
            // This deactivates heuristics in the Swift compiler that treats single-file modules and source files
            // named "main.swift" specially w.r.t. whether they can have an entry point.
            //
            // See https://bugs.swift.org/browse/SR-14488 for discussion about improvements so that SwiftPM can
            // convey the intent to build an executable module to the compiler regardless of the number of files
            // in the module or their names.
            if self.toolsVersion < .v5_5 || self.sources.count != 1 {
                return false
            }
            // looking into the file content to see if it is using the @main annotation which requires parse-as-library
            return (try? self.containsAtMain(fileSystem: self.fileSystem, path: self.sources[0])) ?? false
        default:
            return false
        }
    }

    // looking into the file content to see if it is using the @main annotation
    // this is not bullet-proof since theoretically the file can contain the @main string for other reasons
    // but it is the closest to accurate we can do at this point
    func containsAtMain(fileSystem: FileSystem, path: AbsolutePath) throws -> Bool {
        let content: String = try self.fileSystem.readFileContents(path)
        let lines = content.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }

        var multilineComment = false
        for line in lines {
            if line.hasPrefix("//") {
                continue
            }
            if line.hasPrefix("/*") {
                multilineComment = true
            }
            if line.hasSuffix("*/") {
                multilineComment = false
            }
            if multilineComment {
                continue
            }
            if line.hasPrefix("@main") {
                return true
            }
        }
        return false
    }

    /// The filesystem to operate on.
    let fileSystem: FileSystem

    /// The modulemap file for this target, if any.
    private(set) var moduleMap: AbsolutePath?

    /// The results of applying any build tool plugins to this target.
    public let buildToolPluginInvocationResults: [BuildToolPluginInvocationResult]

    /// The results of running any prebuild commands for this target.
    public let prebuildCommandResults: [PrebuildCommandResult]

    /// Any macro products that this target requires to build.
    public let requiredMacroProducts: [ProductBuildDescription]

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// Whether or not to generate code for test observation.
    private let shouldGenerateTestObservation: Bool

    /// Whether to disable sandboxing (e.g. for macros).
    private let shouldDisableSandbox: Bool

    /// Create a new target description with target and build parameters.
    init(
        package: ResolvedPackage,
        target: ResolvedModule,
        toolsVersion: ToolsVersion,
        additionalFileRules: [FileRuleDescription] = [],
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [BuildToolPluginInvocationResult] = [],
        prebuildCommandResults: [PrebuildCommandResult] = [],
        requiredMacroProducts: [ProductBuildDescription] = [],
        testTargetRole: TestTargetRole? = nil,
        shouldGenerateTestObservation: Bool = false,
        shouldDisableSandbox: Bool,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        guard let swiftTarget = target.underlying as? SwiftModule else {
            throw InternalError("underlying target type mismatch \(target)")
        }

        self.swiftTarget = swiftTarget
        self.package = package
        self.target = target
        self.toolsVersion = toolsVersion
        self.buildParameters = buildParameters

        // Unless mentioned explicitly, use the target type to determine if this is a test target.
        if let testTargetRole {
            self.testTargetRole = testTargetRole
        } else if target.type == .test {
            self.testTargetRole = .default
        } else {
            self.testTargetRole = nil
        }

        self.tempsPath = target.tempsPath(self.buildParameters)
        self.derivedSources = Sources(paths: [], root: self.tempsPath.appending("DerivedSources"))
        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults
        self.requiredMacroProducts = requiredMacroProducts
        self.shouldGenerateTestObservation = shouldGenerateTestObservation
        self.shouldDisableSandbox = shouldDisableSandbox
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope

        (self.pluginDerivedSources, self.pluginDerivedResources) = ModulesGraph.computePluginGeneratedFiles(
            target: target,
            toolsVersion: toolsVersion,
            additionalFileRules: additionalFileRules,
            buildParameters: self.buildParameters,
            buildToolPluginInvocationResults: buildToolPluginInvocationResults,
            prebuildCommandResults: prebuildCommandResults,
            observabilityScope: observabilityScope
        )

        if self.shouldEmitObjCCompatibilityHeader {
            self.moduleMap = try self.generateModuleMap()
        }

        // Do nothing if we're not generating a bundle.
        if self.bundlePath != nil {
            try self.generateResourceAccessor()

            let infoPlistPath = self.tempsPath.appending("Info.plist")
            if try generateResourceInfoPlist(fileSystem: self.fileSystem, target: target, path: infoPlistPath) {
                self.resourceBundleInfoPlistPath = infoPlistPath
            }
        }

        if !resourceFilesToEmbed.isEmpty {
            resourcesEmbeddingSource = try addResourceEmbeddingSource()
        }

        try self.generateTestObservation()
    }

    private func generateTestObservation() throws {
        guard target.type == .test else {
            return
        }

        let subpath = try RelativePath(validating: "test_observation.swift")
        let path = self.derivedSources.root.appending(subpath)

        guard shouldGenerateTestObservation else {
            _ = try? fileSystem.removeFileTree(path)
            return
        }

        guard
            self.buildParameters.triple.isDarwin() &&
            self.buildParameters.testingParameters.experimentalTestOutput
        else {
            return
        }

        let content = generateTestObservationCode(buildParameters: self.buildParameters)

        // FIXME: We should generate this file during the actual build.
        self.derivedSources.relativePaths.append(subpath)
        try self.fileSystem.writeIfChanged(path: path, string: content)
    }

    private func addResourceEmbeddingSource() throws -> AbsolutePath {
        let subpath = try RelativePath(validating: "embedded_resources.swift")
        self.derivedSources.relativePaths.append(subpath)
        return self.derivedSources.root.appending(subpath)
    }

    /// Generate the resource bundle accessor, if appropriate.
    private func generateResourceAccessor() throws {
        // Do nothing if we're not generating a bundle.
        guard let bundlePath else { return }

        let mainPathSubstitution: String
        if self.buildParameters.triple.isWASI() {
            // We prefer compile-time evaluation of the bundle path here for WASI. There's no benefit in evaluating this
            // at runtime, especially as `Bundle` support in WASI Foundation is partial. We expect all resource paths to
            // evaluate to `/\(resourceBundleName)/\(resourcePath)`, which allows us to pass this path to JS APIs like
            // `fetch` directly, or to `<img src=` HTML attributes. The resources are loaded from the server, and we
            // can't hardcode the host part in the URL. Making URLs relative by starting them with
            // `/\(resourceBundleName)` makes it work in the browser.
            let mainPath = try AbsolutePath(validating: Bundle.main.bundlePath)
                .appending(component: bundlePath.basename).pathString
            mainPathSubstitution = #""\#(mainPath.asSwiftStringLiteralConstant)""#
        } else {
            mainPathSubstitution =
                #"Bundle.main.bundleURL.appendingPathComponent("\#(bundlePath.basename.asSwiftStringLiteralConstant)").path"#
        }

        let content =
            """
            import Foundation

            extension Foundation.Bundle {
                static let module: Bundle = {
                    let mainPath = \(mainPathSubstitution)
                    let buildPath = "\(bundlePath.pathString.asSwiftStringLiteralConstant)"

                    let preferredBundle = Bundle(path: mainPath)

                    guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
                        // Users can write a function called fatalError themselves, we should be resilient against that.
                        Swift.fatalError("could not load resource bundle: from \\(mainPath) or \\(buildPath)")
                    }

                    return bundle
                }()
            }
            """

        let subpath = try RelativePath(validating: "resource_bundle_accessor.swift")

        // Add the file to the derived sources.
        self.derivedSources.relativePaths.append(subpath)

        // Write this file out.
        // FIXME: We should generate this file during the actual build.
        let path = self.derivedSources.root.appending(subpath)
        try self.fileSystem.writeIfChanged(path: path, string: content)
    }

    private func macroArguments() throws -> [String] {
        var args = [String]()

        #if BUILD_MACROS_AS_DYLIBS
        self.requiredMacroProducts.forEach { macro in
            args += ["-Xfrontend", "-load-plugin-library", "-Xfrontend", macro.binaryPath.pathString]
        }
        #else
        try self.requiredMacroProducts.forEach { macro in
            if let macroTarget = macro.product.modules.first {
                let executablePath = try macro.binaryPath.pathString
                args += ["-Xfrontend", "-load-plugin-executable", "-Xfrontend", "\(executablePath)#\(macroTarget.c99name)"]
            } else {
                throw InternalError("macro product \(macro.product.name) has no targets") // earlier validation should normally catch this
            }
        }
        #endif

        if self.shouldDisableSandbox {
            let toolchainSupportsDisablingSandbox = DriverSupport.checkSupportedFrontendFlags(
                flags: ["-disable-sandbox"],
                toolchain: self.buildParameters.toolchain,
                fileSystem: fileSystem
            )
            if toolchainSupportsDisablingSandbox {
                args += ["-disable-sandbox"]
            } else {
                // If there's at least one macro being used, we warn about our inability to disable sandboxing.
                if !self.requiredMacroProducts.isEmpty {
                    observabilityScope.emit(warning: "cannot disable sandboxing for Swift compilation because the selected toolchain does not support it")
                }
            }
        }

        return args
    }

    /// The arguments needed to compile this target.
    public func compileArguments() throws -> [String] {
        var args = [String]()
        args += try self.buildParameters.tripleArgs(for: self.target)

        // pass `-v` during verbose builds.
        if self.buildParameters.outputParameters.isVerbose {
            args += ["-v"]
        }

        // Enable batch mode in debug mode.
        //
        // Technically, it should be enabled whenever WMO is off but we
        // don't currently make that distinction in SwiftPM
        switch self.buildParameters.configuration {
        case .debug:
            args += ["-enable-batch-mode"]
        case .release: break
        }

        args += self.buildParameters.indexStoreArguments(for: self.target)
        args += self.optimizationArguments
        args += self.testingArguments

        args += ["-j\(self.buildParameters.workers)"]
        args += self.activeCompilationConditions
        args += self.additionalFlags
        args += try self.moduleCacheArgs
        args += self.stdlibArguments
        args += self.buildParameters.sanitizers.compileSwiftFlags()
        args += ["-parseable-output"]

        // If we're compiling the main module of an executable other than the one that
        // implements a test suite, and if the package tools version indicates that we
        // should, we rename the `_main` entry point to `_<modulename>_main`.
        //
        // This will allow tests to link against the module without any conflicts. And
        // when we link the executable, we will ask the linker to rename the entry point
        // symbol to just `_main` again (or if the linker doesn't support it, we'll
        // generate a source containing a redirect).
        if (self.target.underlying as? SwiftModule)?.supportsTestableExecutablesFeature == true
            && !self.isTestTarget && self.toolsVersion >= .v5_5
        {
            // We only do this if the linker supports it, as indicated by whether we
            // can construct the linker flags. In the future we will use a generated
            // code stub for the cases in which the linker doesn't support it, so that
            // we can rename the symbol unconditionally.
            // No `-` for these flags because the set of Strings in driver.supportedFrontendFlags do
            // not have a leading `-`
            if self.buildParameters.driverParameters.canRenameEntrypointFunctionName,
               self.buildParameters.linkerFlagsForRenamingMainFunction(of: self.target) != nil
            {
                args += ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "\(self.target.c99name)_main"]
            }
        }

        // If the target needs to be parsed without any special semantics involving "main.swift", do so now.
        if self.needsToBeParsedAsLibrary {
            args += ["-parse-as-library"]
        }

        // Only add the build path to the framework search path if there are binary frameworks to link against.
        if !self.libraryBinaryPaths.isEmpty {
            args += ["-F", self.buildParameters.buildPath.pathString]
        }

        // Emit the ObjC compatibility header if enabled.
        if self.shouldEmitObjCCompatibilityHeader {
            args += ["-emit-objc-header", "-emit-objc-header-path", self.objCompatibilityHeaderPath.pathString]
        }

        // Add arguments needed for code coverage if it is enabled.
        if self.buildParameters.testingParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        // Add arguments to colorize output if stdout is tty
        if self.buildParameters.outputParameters.isColorized {
            args += ["-color-diagnostics"]
        }

        args += try self.cxxInteroperabilityModeArguments(
            propagateFromCurrentModuleOtherSwiftFlags: false)

        // Add arguments from declared build settings.
        args += try self.buildSettingsFlags()

        // Add the output for the `.swiftinterface`, if requested or if library evolution has been enabled some other
        // way.
        if self.buildParameters.driverParameters.enableParseableModuleInterfaces || args.contains("-enable-library-evolution") {
            args += ["-emit-module-interface-path", self.parseableModuleInterfaceOutputPath.pathString]
        }

        switch self.buildParameters.prepareForIndexing {
        case .off:
            break
        case .on:
            args += ["-Xfrontend", "-experimental-lazy-typecheck",]
            if !args.contains("-enable-testing") {
                // enable-testing needs the non-exportable-decls
                args += ["-Xfrontend", "-experimental-skip-non-exportable-decls"]
            }
            fallthrough
        case .noLazy:
            args += [
                "-Xfrontend", "-experimental-skip-all-function-bodies",
                "-Xfrontend", "-experimental-allow-module-with-compiler-errors",
                "-Xfrontend", "-empty-abi-descriptor"
            ]
        }

        args += self.buildParameters.toolchain.extraFlags.swiftCompilerFlags
        // User arguments (from -Xswiftc) should follow generated arguments to allow user overrides
        args += self.buildParameters.flags.swiftCompilerFlags

        args += self.buildParameters.toolchain.extraFlags.cCompilerFlags.asSwiftcCCompilerFlags()
        // User arguments (from -Xcc) should follow generated arguments to allow user overrides
        args += self.buildParameters.flags.cCompilerFlags.asSwiftcCCompilerFlags()

        // TODO: Pass -Xcxx flags to swiftc (#6491)
        // Uncomment when downstream support arrives.
        // args += self.buildParameters.toolchain.extraFlags.cxxCompilerFlags.asSwiftcCXXCompilerFlags()
        // // User arguments (from -Xcxx) should follow generated arguments to allow user overrides
        // args += self.buildParameters.flags.cxxCompilerFlags.asSwiftcCXXCompilerFlags()

        // Enable the correct LTO mode if requested.
        switch self.buildParameters.linkingParameters.linkTimeOptimizationMode {
        case nil:
            break
        case .full:
            args += ["-lto=llvm-full"]
        case .thin:
            args += ["-lto=llvm-thin"]
        }

        // Pass default include paths from the toolchain.
        for includeSearchPath in self.buildParameters.toolchain.includeSearchPaths {
            args += ["-I", includeSearchPath.pathString]
        }

        // suppress warnings if the package is remote
        if self.package.isRemote {
            args += ["-suppress-warnings"]
            // suppress-warnings and warnings-as-errors are mutually exclusive
            if let index = args.firstIndex(of: "-warnings-as-errors") {
                args.remove(at: index)
            }
        }

        // Pass `-user-module-version` for versioned packages that aren't pre-releases.
        if
          let version = package.manifest.version,
          version.prereleaseIdentifiers.isEmpty &&
          version.buildMetadataIdentifiers.isEmpty &&
          toolsVersion >= .v6_0
        {
            args += ["-user-module-version", version.description]
        }

        args += self.package.packageNameArgument(
            target: self.target,
            isPackageNameSupported: self.buildParameters.driverParameters.isPackageAccessModifierSupported
        )
        args += try self.macroArguments()

        // rdar://117578677
        // Pass -fno-omit-frame-pointer to support backtraces
        // this can be removed once the backtracer uses DWARF instead of frame pointers
        if let omitFramePointers = self.buildParameters.debuggingParameters.omitFramePointers {
            if omitFramePointers {
                args += ["-Xcc", "-fomit-frame-pointer"]
            } else {
                args += ["-Xcc", "-fno-omit-frame-pointer"]
            }
        }

        return args
    }

    /// Determines the arguments needed to run `swift-symbolgraph-extract` for
    /// this module.
    package func symbolGraphExtractArguments() throws -> [String] {
        var args = [String]()
        args += try self.cxxInteroperabilityModeArguments(
            propagateFromCurrentModuleOtherSwiftFlags: true)

        args += self.buildParameters.toolchain.extraFlags.swiftCompilerFlags

        // Include search paths determined during planning
        args += self.additionalFlags
        // FIXME: only pass paths to the actual dependencies of the module
        // Include search paths for swift module dependencies.
        args += ["-I", self.modulesPath.pathString]

        // FIXME: Only include valid args
        // This condition should instead only include args which are known to be
        // compatible instead of filtering out specific unknown args.
        //
        // swift-symbolgraph-extract does not support parsing `-use-ld=lld` and
        // will silently error failing the operation.
        args = args.filter { !$0.starts(with: "-use-ld=") }
        return args
    }

    // FIXME: this function should operation on a strongly typed buildSetting
    // Move logic from PackageBuilder here.
    /// Determines the arguments needed for cxx interop for this module.
    func cxxInteroperabilityModeArguments(
        // FIXME: Remove argument
        // This argument is added as a stop gap to support generating arguments
        // for tools which currently don't leverage "OTHER_SWIFT_FLAGS". In the
        // fullness of time this function should operate on a strongly typed
        // "interopMode" property of SwiftTargetBuildDescription instead of
        // digging through "OTHER_SWIFT_FLAGS" manually.
        propagateFromCurrentModuleOtherSwiftFlags: Bool
    ) throws -> [String] {
        func cxxInteroperabilityModeAndStandard(
            for module: ResolvedModule
        ) -> [String]? {
            let scope = self.buildParameters.createScope(for: module)
            let flags = scope.evaluate(.OTHER_SWIFT_FLAGS)
            let mode = flags.first { $0.hasPrefix("-cxx-interoperability-mode=") }
            guard let mode else { return nil }
            // FIXME: Use a stored self.cxxLanguageStandard property
            // It definitely should _never_ reach back into the manifest
            if let cxxStandard = self.package.manifest.cxxLanguageStandard {
                return [mode, "-Xcc", "-std=\(cxxStandard)"]
            } else {
                return [mode]
            }
        }

        if propagateFromCurrentModuleOtherSwiftFlags {
            // Look for cxx interop mode in the current module, if set exit early,
            // the flag is already present.
            if let args = cxxInteroperabilityModeAndStandard(for: self.target) {
                return args
            }
        }

        // Implicitly propagate cxx interop flags for generated test targets.
        // If the current module doesn't have cxx interop mode set, search
        // through the module's dependencies looking for the a module that
        // enables cxx interop and copy it's flag.
        switch self.testTargetRole {
        case .discovery, .entryPoint:
            for module in try self.target.recursiveModuleDependencies() {
                if let args = cxxInteroperabilityModeAndStandard(for: module) {
                    return args
                }
            }
        default: break
        }
        return []
    }

    /// When `scanInvocation` argument is set to `true`, omit the side-effect producing arguments
    /// such as emitting a module or supplementary outputs.
    public func emitCommandLine(scanInvocation: Bool = false) throws -> [String] {
        var result: [String] = []
        result.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)

        result.append("-module-name")
        result.append(self.target.c99name)
        result.append(
            contentsOf: self.package.packageNameArgument(
                target: self.target,
                isPackageNameSupported: self.buildParameters.driverParameters.isPackageAccessModifierSupported
            )
        )
        if !scanInvocation {
            result.append("-emit-dependencies")

            // FIXME: Do we always have a module?
            result.append("-emit-module")
            result.append("-emit-module-path")
            result.append(self.moduleOutputPath.pathString)

            result.append("-output-file-map")
            // FIXME: Eliminate side effect.
            result.append(try self.writeOutputFileMap().pathString)
        }

        if self.buildParameters.useWholeModuleOptimization {
            result.append("-whole-module-optimization")
            result.append("-num-threads")
            result.append(String(ProcessInfo.processInfo.activeProcessorCount))
        } else {
            result.append("-incremental")
        }

        result.append("-c")
        result.append(contentsOf: self.sources.map(\.pathString))

        result.append("-I")
        result.append(self.modulesPath.pathString)

        result += try self.compileArguments()
        return result
    }

    /// Returns true if ObjC compatibility header should be emitted.
    private var shouldEmitObjCCompatibilityHeader: Bool {
        self.buildParameters.triple.isDarwin() && self.target.type == .library
    }

    func writeOutputFileMap() throws -> AbsolutePath {
        let path = self.tempsPath.appending("output-file-map.json")
        let masterDepsPath = self.tempsPath.appending("master.swiftdeps")

        var content =
            #"""
            {
              "": {

            """#

        if self.buildParameters.useWholeModuleOptimization {
            let moduleName = self.target.c99name
            content +=
                #"""
                    "dependencies": "\#(
                    self.tempsPath.appending(component: moduleName + ".d")._nativePathString(escaped: true)
                )",

                """#

            // FIXME: Need to record this deps file for processing it later.
            content +=
                #"""
                    "object": "\#(
                    self.tempsPath.appending(component: moduleName + ".o")._nativePathString(escaped: true)
                )",

                """#

        }
        content +=
            #"""
                "swift-dependencies": "\#(masterDepsPath._nativePathString(escaped: true))"
              },

            """#


        // Write out the entries for each source file.
        let sources = self.sources
        let objects = try self.objects
        let ltoEnabled = self.buildParameters.linkingParameters.linkTimeOptimizationMode != nil
        let objectKey = ltoEnabled ? "llvm-bc" : "object"

        for idx in 0..<sources.count {
            let source = sources[idx]
            let object = objects[idx]

            let sourceFileName = source.basenameWithoutExt
            let partialModulePath = self.tempsPath.appending(component: sourceFileName + "~partial.swiftmodule")
            let swiftDepsPath = self.tempsPath.appending(component: sourceFileName + ".swiftdeps")

            content +=
                #"""
                  "\#(source._nativePathString(escaped: true))": {

                """#

            if !self.buildParameters.useWholeModuleOptimization {
                let depsPath = self.tempsPath.appending(component: sourceFileName + ".d")
                content +=
                    #"""
                        "dependencies": "\#(depsPath._nativePathString(escaped: true))",

                    """#
                // FIXME: Need to record this deps file for processing it later.
            }

            content +=
                #"""
                    "\#(objectKey)": "\#(object._nativePathString(escaped: true))",
                    "swiftmodule": "\#(partialModulePath._nativePathString(escaped: true))",
                    "swift-dependencies": "\#(swiftDepsPath._nativePathString(escaped: true))"
                  }\#((idx + 1) < sources.count ? "," : "")

                """#
        }

        content += "}\n"

        try fileSystem.createDirectory(path.parentDirectory, recursive: true)
        try self.fileSystem.writeFileContents(path, bytes: .init(encodingAsUTF8: content), atomically: true)
        return path
    }

    /// Generates the module map for the Swift target and returns its path.
    private func generateModuleMap() throws -> AbsolutePath {
        let path = self.tempsPath.appending(component: moduleMapFilename)

        let bytes = ByteString(
            #"""
            module \#(self.target.c99name) {
                header "\#(self.objCompatibilityHeaderPath.pathString)"
                requires objc
            }

            """#.utf8
        )

        // Return early if the contents are identical.
        if self.fileSystem.isFile(path), try self.fileSystem.readFileContents(path) == bytes {
            return path
        }

        try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
        try self.fileSystem.writeFileContents(path, bytes: bytes)

        return path
    }

    /// Returns the path to the ObjC compatibility header for this Swift target.
    var objCompatibilityHeaderPath: AbsolutePath {
        self.tempsPath.appending("\(self.target.name)-Swift.h")
    }

    /// Returns the build flags from the declared build settings.
    private func buildSettingsFlags() throws -> [String] {
        let scope = self.buildParameters.createScope(for: self.target)
        var flags: [String] = []

        // A custom swift version.
        flags += scope.evaluate(.SWIFT_VERSION).flatMap { ["-swift-version", $0] }

        // Swift defines.
        let swiftDefines = scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS)
        flags += swiftDefines.map { "-D" + $0 }

        // Other Swift flags.
        flags += scope.evaluate(.OTHER_SWIFT_FLAGS)

        // Add C flags by prefixing them with -Xcc.
        //
        // C defines.
        let cDefines = scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS)
        flags += cDefines.flatMap { ["-Xcc", "-D" + $0] }

        // Header search paths.
        let headerSearchPaths = scope.evaluate(.HEADER_SEARCH_PATHS)
        flags += try headerSearchPaths.flatMap { path -> [String] in
            ["-Xcc", "-I\(try AbsolutePath(validating: path, relativeTo: target.sources.root).pathString)"]
        }

        // Other C flags.
        flags += scope.evaluate(.OTHER_CFLAGS).flatMap { ["-Xcc", $0] }

        // Include path for the toolchain's copy of SwiftSyntax.
        #if BUILD_MACROS_AS_DYLIBS
        if module.type == .macro {
            flags += try ["-I", self.defaultBuildParameters.toolchain.hostLibDir.pathString]
        }
        #endif

        return flags
    }

    /// A list of compilation conditions to enable for conditional compilation expressions.
    private var activeCompilationConditions: [String] {
        var compilationConditions = ["-DSWIFT_PACKAGE"]

        switch self.buildParameters.configuration {
        case .debug:
            compilationConditions += ["-DDEBUG"]
        case .release:
            break
        }

        return compilationConditions
    }

    /// Optimization arguments according to the build configuration.
    private var optimizationArguments: [String] {
        switch self.buildParameters.configuration {
        case .debug:
            return ["-Onone"]
        case .release:
            return ["-O"]
        }
    }

    /// Testing arguments according to the build configuration.
    private var testingArguments: [String] {
        if self.isTestTarget {
            // test targets must be built with -enable-testing
            // since its required for test discovery (the non objective-c reflection kind)
            return ["-enable-testing"]
        } else if self.buildParameters.testingParameters.enableTestability {
            return ["-enable-testing"]
        } else {
            return []
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        get throws {
            ["-module-cache-path", try self.buildParameters.moduleCache.pathString]
        }
    }

    private var stdlibArguments: [String] {
        var arguments: [String] = []

        let isLinkingStaticStdlib = self.buildParameters.linkingParameters.shouldLinkStaticSwiftStdlib
            && self.buildParameters.triple.isSupportingStaticStdlib
        if isLinkingStaticStdlib {
            arguments += ["-static-stdlib"]
        }

        if let resourcesPath = self.buildParameters.toolchain.swiftResourcesPath(isStatic: isLinkingStaticStdlib) {
            arguments += ["-resource-dir", "\(resourcesPath)"]
        }

        return arguments
    }
}
