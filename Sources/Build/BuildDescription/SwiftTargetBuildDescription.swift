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
import SPMBuildCore
import TSCBasic
@_implementationOnly import DriverSupport

/// Target description for a Swift target.
public final class SwiftTargetBuildDescription {
    /// The package this target belongs to.
    public let package: ResolvedPackage

    /// The target described by this target.
    public let target: ResolvedTarget

    /// The tools version of the package that declared the target.  This can
    /// can be used to conditionalize semantically significant changes in how
    /// a target is built.
    public let toolsVersion: ToolsVersion

    /// The build parameters.
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

    private let driverSupport = DriverSupport()

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        if let bundleName = target.underlyingTarget.potentialBundleName, needsResourceBundle {
            return self.buildParameters.bundlePath(named: bundleName)
        } else {
            return .none
        }
    }

    private var needsResourceBundle: Bool {
        return resources.filter { $0.rule != .embedInCode }.isEmpty == false
    }

    private var needsResourceEmbedding: Bool {
        return resources.filter { $0.rule == .embedInCode }.isEmpty == false
    }

    /// The list of all source files in the target, including the derived ones.
    public var sources: [AbsolutePath] {
        self.target.sources.paths + self.derivedSources.paths + self.pluginDerivedSources.paths
    }

    /// The list of all resource files in the target, including the derived ones.
    public var resources: [Resource] {
        self.target.underlyingTarget.resources + self.pluginDerivedResources
    }

    /// The objects in this target.
    public var objects: [AbsolutePath] {
        get throws {
            let relativePaths = self.target.sources.relativePaths + self.derivedSources.relativePaths + self
                .pluginDerivedSources.relativePaths
            return try relativePaths.map {
                try AbsolutePath(validating: "\($0.pathString).o", relativeTo: tempsPath)
            }
        }
    }

    /// The path to the swiftmodule file after compilation.
    var moduleOutputPath: AbsolutePath {
        // If we're an executable and we're not allowing test targets to link against us, we hide the module.
        let allowLinkingAgainstExecutables = (buildParameters.triple.isDarwin() || self.buildParameters.triple
            .isLinux() || self.buildParameters.triple.isWindows()) && self.toolsVersion >= .v5_5
        let dirPath = (target.type == .executable && !allowLinkingAgainstExecutables) ? self.tempsPath : self
            .buildParameters.buildPath
        return dirPath.appending(component: self.target.c99name + ".swiftmodule")
    }

    /// The path to the wrapped swift module which is created using the modulewrap tool. This is required
    /// for supporting debugging on non-Darwin platforms (On Darwin, we just pass the swiftmodule to the linker
    /// using the `-add_ast_path` flag).
    var wrappedModuleOutputPath: AbsolutePath {
        self.tempsPath.appending(component: self.target.c99name + ".swiftmodule.o")
    }

    /// The path to the swifinterface file after compilation.
    var parseableModuleInterfaceOutputPath: AbsolutePath {
        self.buildParameters.buildPath.appending(component: self.target.c99name + ".swiftinterface")
    }

    /// Path to the resource Info.plist file, if generated.
    public private(set) var resourceBundleInfoPlistPath: AbsolutePath?

    /// Paths to the binary libraries the target depends on.
    var libraryBinaryPaths: Set<AbsolutePath> = []

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    var additionalFlags: [String] = []

    /// The swift version for this target.
    var swiftVersion: SwiftLanguageVersion {
        (self.target.underlyingTarget as! SwiftTarget).swiftVersion
    }

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
        let lines = content.split(separator: "\n").compactMap { String($0).spm_chuzzle() }

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
    public let requiredMacroProducts: [ResolvedProduct]

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// Create a new target description with target and build parameters.
    init(
        package: ResolvedPackage,
        target: ResolvedTarget,
        toolsVersion: ToolsVersion,
        additionalFileRules: [FileRuleDescription] = [],
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [BuildToolPluginInvocationResult] = [],
        prebuildCommandResults: [PrebuildCommandResult] = [],
        requiredMacroProducts: [ResolvedProduct] = [],
        testTargetRole: TestTargetRole? = nil,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        guard target.underlyingTarget is SwiftTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }
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
        self.fileSystem = fileSystem
        self.tempsPath = buildParameters.buildPath.appending(component: target.c99name + ".build")
        self.derivedSources = Sources(paths: [], root: self.tempsPath.appending("DerivedSources"))
        self.pluginDerivedSources = Sources(paths: [], root: buildParameters.dataPath)
        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults
        self.requiredMacroProducts = requiredMacroProducts
        self.observabilityScope = observabilityScope

        // Add any derived files that were declared for any commands from plugin invocations.
        var pluginDerivedFiles = [AbsolutePath]()
        for command in buildToolPluginInvocationResults.reduce([], { $0 + $1.buildCommands }) {
            for absPath in command.outputFiles {
                pluginDerivedFiles.append(absPath)
            }
        }

        // Add any derived files that were discovered from output directories of prebuild commands.
        for result in self.prebuildCommandResults {
            for path in result.derivedFiles {
                pluginDerivedFiles.append(path)
            }
        }

        // Let `TargetSourcesBuilder` compute the treatment of plugin generated files.
        let (derivedSources, derivedResources) = TargetSourcesBuilder.computeContents(
            for: pluginDerivedFiles,
            toolsVersion: toolsVersion,
            additionalFileRules: additionalFileRules,
            defaultLocalization: target.defaultLocalization,
            targetName: target.name,
            targetPath: target.underlyingTarget.path,
            observabilityScope: observabilityScope
        )
        self.pluginDerivedResources = derivedResources
        derivedSources.forEach { absPath in
            let relPath = absPath.relative(to: self.pluginDerivedSources.root)
            self.pluginDerivedSources.relativePaths.append(relPath)
        }

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

        try self.generateResourceEmbeddingCode()
    }

    // FIXME: This will not work well for large files, as we will store the entire contents, plus its byte array representation in memory and also `writeIfChanged()` will read the entire generated file again.
    private func generateResourceEmbeddingCode() throws {
        guard needsResourceEmbedding else { return }

        let stream = BufferedOutputByteStream()
        stream <<< """
        struct PackageResources {

        """

        try resources.forEach {
            guard $0.rule == .embedInCode else { return }

            let variableName = $0.path.basename.spm_mangledToC99ExtendedIdentifier()
            let fileContent = try Data(contentsOf: URL(fileURLWithPath: $0.path.pathString)).map { String($0) }.joined(separator: ",")

            stream <<< "static let \(variableName): [UInt8] = [\(fileContent)]\n"
        }

        stream <<< """
        }
        """

        let subpath = RelativePath("embedded_resources.swift")
        self.derivedSources.relativePaths.append(subpath)
        let path = self.derivedSources.root.appending(subpath)
        try self.fileSystem.writeIfChanged(path: path, bytes: stream.bytes)
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

        let stream = BufferedOutputByteStream()
        stream <<< """
        \(self.toolsVersion < .vNext ? "import" : "@_implementationOnly import") class Foundation.Bundle

        extension Foundation.Bundle {
            static let module: Bundle = {
                let mainPath = \(mainPathSubstitution)
                let buildPath = "\(bundlePath.pathString.asSwiftStringLiteralConstant)"

                let preferredBundle = Bundle(path: mainPath)

                guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
                    fatalError("could not load resource bundle: from \\(mainPath) or \\(buildPath)")
                }

                return bundle
            }()
        }
        """

        let subpath = RelativePath("resource_bundle_accessor.swift")

        // Add the file to the derived sources.
        self.derivedSources.relativePaths.append(subpath)

        // Write this file out.
        // FIXME: We should generate this file during the actual build.
        let path = self.derivedSources.root.appending(subpath)
        try self.fileSystem.writeIfChanged(path: path, bytes: stream.bytes)
    }

    private func packageNameArgumentIfSupported(with pkg: ResolvedPackage, group: Target.Group) -> [String] {
        let flag = "-package-name"
        if pkg.manifest.usePackageNameFlag,
           driverSupport.checkToolchainDriverFlags(flags: [flag], toolchain:  self.buildParameters.toolchain, fileSystem: self.fileSystem) {
            switch group {
            case .package:
                let pkgID = pkg.identity.description.spm_mangledToC99ExtendedIdentifier()
                return [flag, pkgID]
            case .excluded:
                return []
            }
        }
        return []
    }

    private func macroArguments() throws -> [String] {
        var args = [String]()

        #if BUILD_MACROS_AS_DYLIBS
        self.requiredMacroProducts.forEach { macro in
            args += ["-Xfrontend", "-load-plugin-library", "-Xfrontend", self.buildParameters.binaryPath(for: macro).pathString]
        }
        #else
        try self.requiredMacroProducts.forEach { macro in
            if let macroTarget = macro.targets.first {
                let executablePath = self.buildParameters.binaryPath(for: macro).pathString
                args += ["-Xfrontend", "-load-plugin-executable", "-Xfrontend", "\(executablePath)#\(macroTarget.c99name)"]
            } else {
                throw InternalError("macro product \(macro.name) has no targets") // earlier validation should normally catch this
            }
        }
        #endif

        return args
    }

    /// The arguments needed to compile this target.
    public func compileArguments() throws -> [String] {
        var args = [String]()
        args += try self.buildParameters.targetTripleArgs(for: self.target)
        args += ["-swift-version", self.swiftVersion.rawValue]

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
        args += ["-g"]
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
        if (self.target.underlyingTarget as? SwiftTarget)?.supportsTestableExecutablesFeature == true
            && !self.isTestTarget && self.toolsVersion >= .v5_5
        {
            // We only do this if the linker supports it, as indicated by whether we
            // can construct the linker flags. In the future we will use a generated
            // code stub for the cases in which the linker doesn't support it, so that
            // we can rename the symbol unconditionally.
            // No `-` for these flags because the set of Strings in driver.supportedFrontendFlags do
            // not have a leading `-`
            if self.buildParameters.canRenameEntrypointFunctionName,
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
        if self.buildParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        // Add arguments to colorize output if stdout is tty
        if self.buildParameters.colorizedOutput {
            args += ["-color-diagnostics"]
        }

        // Add arguments from declared build settings.
        args += try self.buildSettingsFlags()

        // Add the output for the `.swiftinterface`, if requested or if library evolution has been enabled some other
        // way.
        if self.buildParameters.enableParseableModuleInterfaces || args.contains("-enable-library-evolution") {
            args += ["-emit-module-interface-path", self.parseableModuleInterfaceOutputPath.pathString]
        }

        args += self.buildParameters.toolchain.extraFlags.swiftCompilerFlags
        // User arguments (from -Xswiftc) should follow generated arguments to allow user overrides
        args += self.buildParameters.swiftCompilerFlags

        // suppress warnings if the package is remote
        if self.package.isRemote {
            args += ["-suppress-warnings"]
            // suppress-warnings and warnings-as-errors are mutually exclusive
            if let index = args.firstIndex(of: "-warnings-as-errors") {
                args.remove(at: index)
            }
        }

        args += self.packageNameArgumentIfSupported(with: self.package, group: self.target.group)
        args += try self.macroArguments()

        return args
    }

    /// When `scanInvocation` argument is set to `true`, omit the side-effect producing arguments
    /// such as emitting a module or supplementary outputs.
    public func emitCommandLine(scanInvocation: Bool = false) throws -> [String] {
        var result: [String] = []
        result.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)

        result.append("-module-name")
        result.append(self.target.c99name)
        result.append(contentsOf: packageNameArgumentIfSupported(with: self.package, group: self.target.group))
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
        result.append(self.buildParameters.buildPath.pathString)

        result += try self.compileArguments()
        return result
    }

    /// Command-line for emitting just the Swift module.
    public func emitModuleCommandLine() throws -> [String] {
        guard self.buildParameters.emitSwiftModuleSeparately else {
            throw InternalError("expecting emitSwiftModuleSeparately in build parameters")
        }

        var result: [String] = []
        result.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)

        result.append("-module-name")
        result.append(self.target.c99name)
        result.append("-emit-module")
        result.append("-emit-module-path")
        result.append(self.moduleOutputPath.pathString)
        result.append(contentsOf: packageNameArgumentIfSupported(with: self.package, group: self.target.group))
        result += self.buildParameters.toolchain.extraFlags.swiftCompilerFlags

        result.append("-Xfrontend")
        result.append("-experimental-skip-non-inlinable-function-bodies")
        result.append("-force-single-frontend-invocation")

        // FIXME: Handle WMO

        for source in self.target.sources.paths {
            result.append(source.pathString)
        }

        result.append("-I")
        result.append(self.buildParameters.buildPath.pathString)

        // FIXME: Maybe refactor these into "common args".
        result += try self.buildParameters.targetTripleArgs(for: self.target)
        result += ["-swift-version", self.swiftVersion.rawValue]
        result += self.optimizationArguments
        result += self.testingArguments
        result += ["-g"]
        result += ["-j\(self.buildParameters.workers)"]
        result += self.activeCompilationConditions
        result += self.additionalFlags
        result += try self.moduleCacheArgs
        result += self.stdlibArguments
        result += try self.buildSettingsFlags()
        result += try self.macroArguments()

        return result
    }

    /// Command-line for emitting the object files.
    ///
    /// Note: This doesn't emit the module.
    public func emitObjectsCommandLine() throws -> [String] {
        guard self.buildParameters.emitSwiftModuleSeparately else {
            throw InternalError("expecting emitSwiftModuleSeparately in build parameters")
        }

        var result: [String] = []
        result.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)

        result.append("-module-name")
        result.append(self.target.c99name)
        result.append(contentsOf: packageNameArgumentIfSupported(with: self.package, group: self.target.group))
        result.append("-incremental")
        result.append("-emit-dependencies")

        result.append("-output-file-map")
        // FIXME: Eliminate side effect.
        result.append(try self.writeOutputFileMap().pathString)

        // FIXME: Handle WMO

        result.append("-c")
        for source in self.target.sources.paths {
            result.append(source.pathString)
        }

        result.append("-I")
        result.append(self.buildParameters.buildPath.pathString)

        result += try self.buildParameters.targetTripleArgs(for: self.target)
        result += ["-swift-version", self.swiftVersion.rawValue]

        result += self.buildParameters.indexStoreArguments(for: self.target)
        result += self.optimizationArguments
        result += self.testingArguments
        result += ["-g"]
        result += ["-j\(self.buildParameters.workers)"]
        result += self.activeCompilationConditions
        result += self.additionalFlags
        result += try self.moduleCacheArgs
        result += self.stdlibArguments
        result += self.buildParameters.sanitizers.compileSwiftFlags()
        result += ["-parseable-output"]
        result += try self.buildSettingsFlags()
        result += self.buildParameters.toolchain.extraFlags.swiftCompilerFlags
        result += self.buildParameters.swiftCompilerFlags
        result += try self.macroArguments()
        return result
    }

    /// Returns true if ObjC compatibility header should be emitted.
    private var shouldEmitObjCCompatibilityHeader: Bool {
        self.buildParameters.triple.isDarwin() && self.target.type == .library
    }

    private func writeOutputFileMap() throws -> AbsolutePath {
        let path = self.tempsPath.appending("output-file-map.json")
        let stream = BufferedOutputByteStream()

        stream <<< "{\n"

        let masterDepsPath = self.tempsPath.appending("master.swiftdeps")
        stream <<< "  \"\": {\n"
        if self.buildParameters.useWholeModuleOptimization {
            let moduleName = self.target.c99name
            stream <<< "    \"dependencies\": \"" <<< self.tempsPath.appending(component: moduleName + ".d")
                .nativePathString(escaped: true) <<< "\",\n"
            // FIXME: Need to record this deps file for processing it later.
            stream <<< "    \"object\": \"" <<< self.tempsPath.appending(component: moduleName + ".o")
                .nativePathString(escaped: true) <<< "\",\n"
        }
        stream <<< "    \"swift-dependencies\": \"" <<< masterDepsPath.nativePathString(escaped: true) <<< "\"\n"

        stream <<< "  },\n"

        // Write out the entries for each source file.
        let sources = self.target.sources.paths + self.derivedSources.paths + self.pluginDerivedSources.paths
        for (idx, source) in sources.enumerated() {
            let object = try objects[idx]
            let objectDir = object.parentDirectory

            let sourceFileName = source.basenameWithoutExt

            let swiftDepsPath = objectDir.appending(component: sourceFileName + ".swiftdeps")

            stream <<< "  \"" <<< source.nativePathString(escaped: true) <<< "\": {\n"

            if !self.buildParameters.useWholeModuleOptimization {
                let depsPath = objectDir.appending(component: sourceFileName + ".d")
                stream <<< "    \"dependencies\": \"" <<< depsPath.nativePathString(escaped: true) <<< "\",\n"
                // FIXME: Need to record this deps file for processing it later.
            }

            stream <<< "    \"object\": \"" <<< object.nativePathString(escaped: true) <<< "\",\n"

            let partialModulePath = objectDir.appending(component: sourceFileName + "~partial.swiftmodule")
            stream <<< "    \"swiftmodule\": \"" <<< partialModulePath.nativePathString(escaped: true) <<< "\",\n"
            stream <<< "    \"swift-dependencies\": \"" <<< swiftDepsPath.nativePathString(escaped: true) <<< "\"\n"
            stream <<< "  }" <<< ((idx + 1) < sources.count ? "," : "") <<< "\n"
        }

        stream <<< "}\n"

        try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
        try self.fileSystem.writeFileContents(path, bytes: stream.bytes)
        return path
    }

    /// Generates the module map for the Swift target and returns its path.
    private func generateModuleMap() throws -> AbsolutePath {
        let path = self.tempsPath.appending(component: moduleMapFilename)

        let stream = BufferedOutputByteStream()
        stream <<< "module \(self.target.c99name) {\n"
        stream <<< "    header \"" <<< self.objCompatibilityHeaderPath.pathString <<< "\"\n"
        stream <<< "    requires objc\n"
        stream <<< "}\n"

        // Return early if the contents are identical.
        if self.fileSystem.isFile(path), try self.fileSystem.readFileContents(path) == stream.bytes {
            return path
        }

        try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
        try self.fileSystem.writeFileContents(path, bytes: stream.bytes)

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
        if target.type == .macro {
            flags += try ["-I", self.buildParameters.toolchain.hostLibDir.pathString]
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
        } else if self.buildParameters.enableTestability {
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
        if self.buildParameters.shouldLinkStaticSwiftStdlib,
           self.buildParameters.triple.isSupportingStaticStdlib
        {
            return ["-static-stdlib"]
        } else {
            return []
        }
    }
}
