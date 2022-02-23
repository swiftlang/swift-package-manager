/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

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
import struct TSCUtility.Triple
import var TSCUtility.verbosity

extension String {
    fileprivate var asSwiftStringLiteralConstant: String {
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
        // FIXME: We use this hack to let swiftpm's functional test use shared
        // cache so it doesn't become painfully slow.
        if let path = ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] {
            return AbsolutePath(path)
        }
        return buildPath.appending(component: "ModuleCache")
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
    fileprivate func indexStoreArguments(for target: ResolvedTarget) -> [String] {
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
            guard let macOSSupportedPlatform = target.underlyingTarget.getSupportedPlatform(for: .macOS) else {
                throw StringError("the target \(target) doesn't support building for macOS")
            }
            args += [triple.tripleString(forPlatformVersion: macOSSupportedPlatform.version.versionString)]
        } else {
            args += [triple.tripleString]
        }
        return args
    }

    /// Computes the linker flags to use in order to rename a module-named main function to 'main' for the target platform, or nil if the linker doesn't support it for the platform.
    fileprivate func linkerFlagsForRenamingMainFunction(of target: ResolvedTarget) -> [String]? {
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
    fileprivate func createScope(for target: ResolvedTarget) -> BuildSettings.Scope {
        return BuildSettings.Scope(target.underlyingTarget.buildSettings, environment: buildEnvironment)
    }
}

/// A target description which can either be for a Swift or Clang target.
public enum TargetBuildDescription {

    /// Swift target description.
    case swift(SwiftTargetBuildDescription)

    /// Clang target description.
    case clang(ClangTargetBuildDescription)

    /// The objects in this target.
    var objects: [AbsolutePath] {
        switch self {
        case .swift(let target):
            return target.objects
        case .clang(let target):
            return target.objects
        }
    }

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        switch self {
        case .swift(let target):
            return target.bundlePath
        case .clang(let target):
            return target.bundlePath
        }
    }

    var target: ResolvedTarget {
        switch self {
        case .swift(let target):
            return target.target
        case .clang(let target):
            return target.target
        }
    }

    /// Paths to the binary libraries the target depends on.
    var libraryBinaryPaths: Set<AbsolutePath> {
        switch self {
        case .swift(let target):
            return target.libraryBinaryPaths
        case .clang(let target):
            return target.libraryBinaryPaths
        }
    }

    var resourceBundleInfoPlistPath: AbsolutePath? {
        switch self {
        case .swift(let target):
            return target.resourceBundleInfoPlistPath
        case .clang(let target):
            return target.resourceBundleInfoPlistPath
        }
    }
}

/// Target description for a Clang target i.e. C language family target.
public final class ClangTargetBuildDescription {

    /// The target described by this target.
    public let target: ResolvedTarget

    /// The underlying clang target.
    public var clangTarget: ClangTarget {
        return target.underlyingTarget as! ClangTarget
    }
    
    /// The tools version of the package that declared the target.  This can
    /// can be used to conditionalize semantically significant changes in how
    /// a target is built.
    public let toolsVersion: ToolsVersion

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The build environment.
    var buildEnvironment: BuildEnvironment {
        buildParameters.buildEnvironment
    }

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        buildParameters.bundlePath(for: target)
    }

    /// The modulemap file for this target, if any.
    public private(set) var moduleMap: AbsolutePath?

    /// Path to the temporary directory for this target.
    var tempsPath: AbsolutePath

    /// The directory containing derived sources of this target.
    ///
    /// These are the source files generated during the build.
    private var derivedSources: Sources

    /// Path to the resource accessor header file, if generated.
    public private(set) var resourceAccessorHeaderFile: AbsolutePath?

    /// Path to the resource Info.plist file, if generated.
    public private(set) var resourceBundleInfoPlistPath: AbsolutePath?

    /// The objects in this target.
    public var objects: [AbsolutePath] {
        return compilePaths().map({ $0.object })
    }

    /// Paths to the binary libraries the target depends on.
    fileprivate(set) var libraryBinaryPaths: Set<AbsolutePath> = []

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The filesystem to operate on.
    private let fileSystem: FileSystem

    /// If this target is a test target.
    public var isTestTarget: Bool {
        return target.type == .test
    }

    /// Create a new target description with target and build parameters.
    init(target: ResolvedTarget, toolsVersion: ToolsVersion, buildParameters: BuildParameters, fileSystem: FileSystem) throws {
        guard target.underlyingTarget is ClangTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }

        self.fileSystem = fileSystem
        self.target = target
        self.toolsVersion = toolsVersion
        self.buildParameters = buildParameters
        self.tempsPath = buildParameters.buildPath.appending(component: target.c99name + ".build")
        self.derivedSources = Sources(paths: [], root: tempsPath.appending(component: "DerivedSources"))

        // Try computing modulemap path for a C library.  This also creates the file in the file system, if needed.
        if target.type == .library {
            // If there's a custom module map, use it as given.
            if case .custom(let path) = clangTarget.moduleMapType {
                self.moduleMap = path
            }
            // If a generated module map is needed, generate one now in our temporary directory.
            else if let generatedModuleMapType = clangTarget.moduleMapType.generatedModuleMapType {
                let path = tempsPath.appending(component: moduleMapFilename)
                let moduleMapGenerator = ModuleMapGenerator(targetName: clangTarget.name, moduleName: clangTarget.c99name, publicHeadersDir: clangTarget.includeDir, fileSystem: fileSystem)
                try moduleMapGenerator.generateModuleMap(type: generatedModuleMapType, at: path)
                self.moduleMap = path
            }
            // Otherwise there is no module map, and we leave `moduleMap` unset.
        }

        // Do nothing if we're not generating a bundle.
        if bundlePath != nil {
            try self.generateResourceAccessor()

            let infoPlistPath = tempsPath.appending(component: "Info.plist")
            if try generateResourceInfoPlist(fileSystem: fileSystem, target: target, path: infoPlistPath) {
                resourceBundleInfoPlistPath = infoPlistPath
            }
        }
    }

    /// An array of tuple containing filename, source, object and dependency path for each of the source in this target.
    public func compilePaths()
        -> [(filename: RelativePath, source: AbsolutePath, object: AbsolutePath, deps: AbsolutePath)]
    {
        let sources = [
            target.sources.root: target.sources.relativePaths,
            derivedSources.root: derivedSources.relativePaths,
        ]

        return sources.flatMap { (root, relativePaths) in
            relativePaths.map { source in
                let path = root.appending(source)
                let object = tempsPath.appending(RelativePath("\(source.pathString).o"))
                let deps = tempsPath.appending(RelativePath("\(source.pathString).d"))
                return (source, path, object, deps)
            }
        }
    }

    /// Builds up basic compilation arguments for a source file in this target; these arguments may be different for C++ vs non-C++.
    /// NOTE: The parameter to specify whether to get C++ semantics is currently optional, but this is only for revlock avoidance with clients. Callers should always specify what they want based either the user's indication or on a default value (possibly based on the filename suffix).
    public func basicArguments(isCXX isCXXOverride: Bool? = .none) throws -> [String] {
        // For now fall back on the hold semantics if the C++ nature isn't specified. This is temporary until clients have been updated.
        let isCXX = isCXXOverride ?? clangTarget.isCXX
        
        var args = [String]()
        // Only enable ARC on macOS.
        if buildParameters.triple.isDarwin() {
            args += ["-fobjc-arc"]
        }
        args += try buildParameters.targetTripleArgs(for: target)
        args += ["-g"]
        if buildParameters.triple.isWindows() {
            args += ["-gcodeview"]
        }
        args += optimizationArguments
        args += activeCompilationConditions
        args += ["-fblocks"]

        // Enable index store, if appropriate.
        //
        // This feature is not widely available in OSS clang. So, we only enable
        // index store for Apple's clang or if explicitly asked to.
        if ProcessEnv.vars.keys.contains("SWIFTPM_ENABLE_CLANG_INDEX_STORE") {
            args += buildParameters.indexStoreArguments(for: target)
        } else if buildParameters.triple.isDarwin(), (try? buildParameters.toolchain._isClangCompilerVendorApple()) == true {
            args += buildParameters.indexStoreArguments(for: target)
        }
        
        // Enable Clang module flags, if appropriate. We enable them except in these cases:
        // 1. on Darwin when compiling for C++, because C++ modules are disabled on Apple-built Clang releases
        // 2. on Windows when compiling for any language, because of issues with the Windows SDK
        // 3. on Android when compiling for any language, because of issues with the Android SDK
        let enableModules = !(buildParameters.triple.isDarwin() && isCXX) && !buildParameters.triple.isWindows() && !buildParameters.triple.isAndroid()
        
        if enableModules {
            // Using modules currently conflicts with the Windows and Android SDKs.
            args += ["-fmodules", "-fmodule-name=" + target.c99name]
        }

        // Only add the build path to the framework search path if there are binary frameworks to link against.
        if !libraryBinaryPaths.isEmpty {
            args += ["-F", buildParameters.buildPath.pathString]
        }

        args += ["-I", clangTarget.includeDir.pathString]
        args += additionalFlags
        if enableModules {
            args += moduleCacheArgs
        }
        args += buildParameters.sanitizers.compileCFlags()

        // Add agruments from declared build settings.
        args += self.buildSettingsFlags()

        if let resourceAccessorHeaderFile = self.resourceAccessorHeaderFile {
            args += ["-include", resourceAccessorHeaderFile.pathString]
        }

        args += buildParameters.toolchain.extraCCFlags
        // User arguments (from -Xcc and -Xcxx below) should follow generated arguments to allow user overrides
        args += buildParameters.flags.cCompilerFlags

        // Add extra C++ flags if this target contains C++ files.
        if clangTarget.isCXX {
            args += self.buildParameters.flags.cxxCompilerFlags
        }
        return args
    }

    /// Returns the build flags from the declared build settings.
    private func buildSettingsFlags() -> [String] {
        let scope = buildParameters.createScope(for: target)
        var flags: [String] = []

        // C defines.
        let cDefines = scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS)
        flags += cDefines.map({ "-D" + $0 })

        // Header search paths.
        let headerSearchPaths = scope.evaluate(.HEADER_SEARCH_PATHS)
        flags += headerSearchPaths.map({
            "-I\(target.sources.root.appending(RelativePath($0)).pathString)"
        })

        // Other C flags.
        flags += scope.evaluate(.OTHER_CFLAGS)

        // Other CXX flags.
        flags += scope.evaluate(.OTHER_CPLUSPLUSFLAGS)

        return flags
    }

    /// Optimization arguments according to the build configuration.
    private var optimizationArguments: [String] {
        switch buildParameters.configuration {
        case .debug:
            return ["-O0"]
        case .release:
            return ["-O2"]
        }
    }

    /// A list of compilation conditions to enable for conditional compilation expressions.
    private var activeCompilationConditions: [String] {
        var compilationConditions = ["-DSWIFT_PACKAGE=1"]

        switch buildParameters.configuration {
        case .debug:
            compilationConditions += ["-DDEBUG=1"]
        case .release:
            break
        }

        return compilationConditions
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        return ["-fmodules-cache-path=\(buildParameters.moduleCache.pathString)"]
    }

    /// Generate the resource bundle accessor, if appropriate.
    private func generateResourceAccessor() throws {
        // Only generate access when we have a bundle and ObjC files.
        guard let bundlePath = self.bundlePath, clangTarget.sources.containsObjcFiles else { return }

        // Compute the basename of the bundle.
        let bundleBasename = bundlePath.basename

        let implFileStream = BufferedOutputByteStream()
        implFileStream <<< """
        #import <Foundation/Foundation.h>

        NSBundle* \(target.c99name)_SWIFTPM_MODULE_BUNDLE() {
            NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"\(bundleBasename)"];
            return [NSBundle bundleWithURL:bundleURL];
        }
        """

        let implFileSubpath = RelativePath("resource_bundle_accessor.m")

        // Add the file to the derived sources.
        derivedSources.relativePaths.append(implFileSubpath)

        // Write this file out.
        // FIXME: We should generate this file during the actual build.
        try fileSystem.writeIfChanged(
            path: derivedSources.root.appending(implFileSubpath),
            bytes: implFileStream.bytes
        )

        let headerFileStream = BufferedOutputByteStream()
        headerFileStream <<< """
        #import <Foundation/Foundation.h>

        #if __cplusplus
        extern "C" {
        #endif

        NSBundle* \(target.c99name)_SWIFTPM_MODULE_BUNDLE(void);

        #define SWIFTPM_MODULE_BUNDLE \(target.c99name)_SWIFTPM_MODULE_BUNDLE()

        #if __cplusplus
        }
        #endif
        """
        let headerFile = derivedSources.root.appending(component: "resource_bundle_accessor.h")
        self.resourceAccessorHeaderFile = headerFile

        try fileSystem.writeIfChanged(
            path: headerFile,
            bytes: headerFileStream.bytes
        )
    }
}

/// Target description for a Swift target.
public final class SwiftTargetBuildDescription {

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

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        buildParameters.bundlePath(for: target)
    }

    /// The list of all source files in the target, including the derived ones.
    public var sources: [AbsolutePath] {
        target.sources.paths + derivedSources.paths + pluginDerivedSources.paths
    }

    /// The objects in this target.
    public var objects: [AbsolutePath] {
        let relativePaths = target.sources.relativePaths + derivedSources.relativePaths + pluginDerivedSources.relativePaths
        return relativePaths.map{ tempsPath.appending(RelativePath("\($0.pathString).o")) }
    }

    /// The path to the swiftmodule file after compilation.
    var moduleOutputPath: AbsolutePath {
        // If we're an executable and we're not allowing test targets to link against us, we hide the module.
        let allowLinkingAgainstExecutables = (buildParameters.triple.isDarwin() || buildParameters.triple.isLinux()) && toolsVersion >= .v5_5
        let dirPath = (target.type == .executable && !allowLinkingAgainstExecutables) ? tempsPath : buildParameters.buildPath
        return dirPath.appending(component: target.c99name + ".swiftmodule")
    }

    /// The path to the wrapped swift module which is created using the modulewrap tool. This is required
    /// for supporting debugging on non-Darwin platforms (On Darwin, we just pass the swiftmodule to the linker
    /// using the `-add_ast_path` flag).
    var wrappedModuleOutputPath: AbsolutePath {
        return tempsPath.appending(component: target.c99name + ".swiftmodule.o")
    }

    /// The path to the swifinterface file after compilation.
    var parseableModuleInterfaceOutputPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".swiftinterface")
    }

    /// Path to the resource Info.plist file, if generated.
    public private(set) var resourceBundleInfoPlistPath: AbsolutePath?

    /// Paths to the binary libraries the target depends on.
    fileprivate(set) var libraryBinaryPaths: Set<AbsolutePath> = []

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The swift version for this target.
    var swiftVersion: SwiftLanguageVersion {
        return (target.underlyingTarget as! SwiftTarget).swiftVersion
    }

    /// If this target is a test target.
    public let isTestTarget: Bool

    /// True if this is the test discovery target.
    public let isTestDiscoveryTarget: Bool
    
    /// True if this module needs to be parsed as a library based on the target type and the configuration
    /// of the source code (for example because it has a single source file whose name isn't "main.swift").
    /// This deactivates heuristics in the Swift compiler that treats single-file modules and source files
    /// named "main.swift" specially w.r.t. whether they can have an entry point.
    ///
    /// See https://bugs.swift.org/browse/SR-14488 for discussion about improvements so that SwiftPM can
    /// convey the intent to build an executable module to the compiler regardless of the number of files
    /// in the module or their names.
    var needsToBeParsedAsLibrary: Bool {
        switch target.type {
        case .library, .test:
            return true
        case .executable:
            guard toolsVersion >= .v5_5 else { return false }
            let sources = self.sources
            return sources.count == 1 && sources.first?.basename != "main.swift"
        default:
            return false
        }
    }

    /// The filesystem to operate on.
    let fileSystem: FileSystem

    /// The modulemap file for this target, if any.
    private(set) var moduleMap: AbsolutePath?
    
    /// The results of applying any build tool plugins to this target.
    public let buildToolPluginInvocationResults: [BuildToolPluginInvocationResult]

    /// The results of running any prebuild commands for this target.
    public let prebuildCommandResults: [PrebuildCommandResult]

    /// Create a new target description with target and build parameters.
    init(
        target: ResolvedTarget,
        toolsVersion: ToolsVersion,
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [BuildToolPluginInvocationResult] = [],
        prebuildCommandResults: [PrebuildCommandResult] = [],
        isTestTarget: Bool? = nil,
        isTestDiscoveryTarget: Bool = false,
        fileSystem: FileSystem
    ) throws {
        guard target.underlyingTarget is SwiftTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }
        self.target = target
        self.toolsVersion = toolsVersion
        self.buildParameters = buildParameters
        // Unless mentioned explicitly, use the target type to determine if this is a test target.
        self.isTestTarget = isTestTarget ?? (target.type == .test)
        self.isTestDiscoveryTarget = isTestDiscoveryTarget
        self.fileSystem = fileSystem
        self.tempsPath = buildParameters.buildPath.appending(component: target.c99name + ".build")
        self.derivedSources = Sources(paths: [], root: tempsPath.appending(component: "DerivedSources"))
        self.pluginDerivedSources = Sources(paths: [], root: buildParameters.dataPath)
        self.buildToolPluginInvocationResults = buildToolPluginInvocationResults
        self.prebuildCommandResults = prebuildCommandResults

        // Add any derived source files that were declared for any commands from plugin invocations.
        for command in buildToolPluginInvocationResults.reduce([], { $0 + $1.buildCommands }) {
            // TODO: What should we do if we find non-Swift sources here?
            for absPath in command.outputFiles {
                let relPath = absPath.relative(to: self.pluginDerivedSources.root)
                self.pluginDerivedSources.relativePaths.append(relPath)
            }
        }

        // Add any derived source files that were discovered from output directories of prebuild commands.
        for result in self.prebuildCommandResults {
            // TODO: What should we do if we find non-Swift sources here?
            for path in result.derivedSourceFiles {
                let relPath = path.relative(to: self.pluginDerivedSources.root)
                self.pluginDerivedSources.relativePaths.append(relPath)
            }
        }
        
        if shouldEmitObjCCompatibilityHeader {
            self.moduleMap = try self.generateModuleMap()
        }

        // Do nothing if we're not generating a bundle.
        if bundlePath != nil {
            try self.generateResourceAccessor()

            let infoPlistPath = tempsPath.appending(component: "Info.plist")
            if try generateResourceInfoPlist(fileSystem: self.fileSystem, target: target, path: infoPlistPath) {
                resourceBundleInfoPlistPath = infoPlistPath
            }
        }
    }

    /// Generate the resource bundle accessor, if appropriate.
    private func generateResourceAccessor() throws {
        // Do nothing if we're not generating a bundle.
        guard let bundlePath = self.bundlePath else { return }

        let mainPathSubstitution: String
        if buildParameters.triple.isWASI() {
            // We prefer compile-time evaluation of the bundle path here for WASI. There's no benefit in evaluating this at runtime, 
            // especially as Bundle support in WASI Foundation is partial. We expect all resource paths to evaluate to 
            // `/\(resourceBundleName)/\(resourcePath)`, which allows us to pass this path to JS APIs like `fetch` directly, or to
            // `<img src=` HTML attributes. The resources are loaded from the server, and we can't hardcode the host part in the URL.
            // Making URLs relative by starting them with `/\(resourceBundleName)` makes it work in the browser.
            let mainPath = AbsolutePath(Bundle.main.bundlePath).appending(component: bundlePath.basename).pathString
            mainPathSubstitution = #""\#(mainPath.asSwiftStringLiteralConstant)""#
        } else {
            mainPathSubstitution = #"Bundle.main.bundleURL.appendingPathComponent("\#(bundlePath.basename.asSwiftStringLiteralConstant)").path"#
        }

        let stream = BufferedOutputByteStream()
        stream <<< """
        import class Foundation.Bundle

        extension Foundation.Bundle {
            static var module: Bundle = {
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
        derivedSources.relativePaths.append(subpath)

        // Write this file out.
        // FIXME: We should generate this file during the actual build.
        let path = derivedSources.root.appending(subpath)
        try self.fileSystem.writeIfChanged(path: path, bytes: stream.bytes)
    }
    
    public static func checkSupportedFrontendFlags(flags: Set<String>, fileSystem: FileSystem) -> Bool {
        do {
            let executor = try SPMSwiftDriverExecutor(resolver: ArgsResolver(fileSystem: fileSystem), fileSystem: fileSystem, env: [:])
            let driver = try Driver(args: ["swiftc"], executor: executor)
            return driver.supportedFrontendFlags.intersection(flags) == flags
        } catch {
            return false
        }
    }
    
    /// The arguments needed to compile this target.
    public func compileArguments() throws -> [String] {
        var args = [String]()
        args += try buildParameters.targetTripleArgs(for: target)
        args += ["-swift-version", swiftVersion.rawValue]

        // Enable batch mode in debug mode.
        //
        // Technically, it should be enabled whenever WMO is off but we
        // don't currently make that distinction in SwiftPM
        switch buildParameters.configuration {
        case .debug:
            args += ["-enable-batch-mode"]
        case .release: break
        }

        args += buildParameters.indexStoreArguments(for: target)
        args += optimizationArguments
        args += testingArguments
        args += ["-g"]
        args += ["-j\(buildParameters.jobs)"]
        args += activeCompilationConditions
        args += additionalFlags
        args += moduleCacheArgs
        args += stdlibArguments
        args += buildParameters.sanitizers.compileSwiftFlags()
        args += ["-parseable-output"]

        // If we're compiling the main module of an executable other than the one that
        // implements a test suite, and if the package tools version indicates that we
        // should, we rename the `_main` entry point to `_<modulename>_main`.
        //
        // This will allow tests to link against the module without any conflicts. And
        // when we link the executable, we will ask the linker to rename the entry point
        // symbol to just `_main` again (or if the linker doesn't support it, we'll
        // generate a source containing a redirect).
        if (target.type == .executable || target.type == .snippet)
           && !isTestTarget && toolsVersion >= .v5_5 {
            // We only do this if the linker supports it, as indicated by whether we
            // can construct the linker flags. In the future we will use a generated
            // code stub for the cases in which the linker doesn't support it, so that
            // we can rename the symbol unconditionally.
            // No `-` for these flags because the set of Strings in driver.supportedFrontendFlags do
            // not have a leading `-`
            if buildParameters.canRenameEntrypointFunctionName,
               buildParameters.linkerFlagsForRenamingMainFunction(of: target) != nil {
                args += ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "\(target.c99name)_main"]
            }
        }
        
        // If the target needs to be parsed without any special semantics involving "main.swift", do so now.
        if self.needsToBeParsedAsLibrary {
            args += ["-parse-as-library"]
        }

        // Only add the build path to the framework search path if there are binary frameworks to link against.
        if !libraryBinaryPaths.isEmpty {
            args += ["-F", buildParameters.buildPath.pathString]
        }

        // Emit the ObjC compatibility header if enabled.
        if shouldEmitObjCCompatibilityHeader {
            args += ["-emit-objc-header", "-emit-objc-header-path", objCompatibilityHeaderPath.pathString]
        }

        // Add arguments needed for code coverage if it is enabled.
        if buildParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        // Add arguments to colorize output if stdout is tty
        if buildParameters.colorizedOutput {
            args += ["-color-diagnostics"]
        }

        // Add arguments from declared build settings.
        args += self.buildSettingsFlags()

        // Add the output for the `.swiftinterface`, if requested or if library evolution has been enabled some other way.
        if buildParameters.enableParseableModuleInterfaces || args.contains("-enable-library-evolution") {
            args += ["-emit-module-interface-path", parseableModuleInterfaceOutputPath.pathString]
        }

        args += buildParameters.toolchain.extraSwiftCFlags
        // User arguments (from -Xswiftc) should follow generated arguments to allow user overrides
        args += buildParameters.swiftCompilerFlags
        return args
    }

    public func emitCommandLine() throws -> [String] {
        var result: [String] = []
        result.append(buildParameters.toolchain.swiftCompiler.pathString)

        result.append("-module-name")
        result.append(target.c99name)

        result.append("-emit-dependencies")

        // FIXME: Do we always have a module?
        result.append("-emit-module")
        result.append("-emit-module-path")
        result.append(moduleOutputPath.pathString)

        result.append("-output-file-map")
        // FIXME: Eliminate side effect.
        result.append(try writeOutputFileMap().pathString)

        if buildParameters.useWholeModuleOptimization {
            result.append("-whole-module-optimization")
            result.append("-num-threads")
            result.append(String(ProcessInfo.processInfo.activeProcessorCount))
        } else {
            result.append("-incremental")
        }

        result.append("-c")
        result.append(contentsOf: sources.map { $0.pathString })

        result.append("-I")
        result.append(buildParameters.buildPath.pathString)

        result += try self.compileArguments()
        return result
     }

    /// Command-line for emitting just the Swift module.
    public func emitModuleCommandLine() throws -> [String] {
        guard buildParameters.emitSwiftModuleSeparately else {
            throw InternalError("expecting emitSwiftModuleSeparately in build parameters")
        }

        var result: [String] = []
        result.append(buildParameters.toolchain.swiftCompiler.pathString)

        result.append("-module-name")
        result.append(target.c99name)
        result.append("-emit-module")
        result.append("-emit-module-path")
        result.append(moduleOutputPath.pathString)
        result += buildParameters.toolchain.extraSwiftCFlags

        result.append("-Xfrontend")
        result.append("-experimental-skip-non-inlinable-function-bodies")
        result.append("-force-single-frontend-invocation")

        // FIXME: Handle WMO

        for source in target.sources.paths {
            result.append(source.pathString)
        }

        result.append("-I")
        result.append(buildParameters.buildPath.pathString)

        // FIXME: Maybe refactor these into "common args".
        result += try buildParameters.targetTripleArgs(for: target)
        result += ["-swift-version", swiftVersion.rawValue]
        result += optimizationArguments
        result += testingArguments
        result += ["-g"]
        result += ["-j\(buildParameters.jobs)"]
        result += activeCompilationConditions
        result += additionalFlags
        result += moduleCacheArgs
        result += stdlibArguments
        result += self.buildSettingsFlags()

        return result
    }

    /// Command-line for emitting the object files.
    ///
    /// Note: This doesn't emit the module.
    public func emitObjectsCommandLine() throws -> [String] {
        guard buildParameters.emitSwiftModuleSeparately else {
            throw InternalError("expecting emitSwiftModuleSeparately in build parameters")
        }

        var result: [String] = []
        result.append(buildParameters.toolchain.swiftCompiler.pathString)

        result.append("-module-name")
        result.append(target.c99name)
        result.append("-incremental")
        result.append("-emit-dependencies")

        result.append("-output-file-map")
        // FIXME: Eliminate side effect.
        result.append(try writeOutputFileMap().pathString)

        // FIXME: Handle WMO

        result.append("-c")
        for source in target.sources.paths {
            result.append(source.pathString)
        }

        result.append("-I")
        result.append(buildParameters.buildPath.pathString)

        result += try buildParameters.targetTripleArgs(for: target)
        result += ["-swift-version", swiftVersion.rawValue]

        result += buildParameters.indexStoreArguments(for: target)
        result += optimizationArguments
        result += testingArguments
        result += ["-g"]
        result += ["-j\(buildParameters.jobs)"]
        result += activeCompilationConditions
        result += additionalFlags
        result += moduleCacheArgs
        result += stdlibArguments
        result += buildParameters.sanitizers.compileSwiftFlags()
        result += ["-parseable-output"]
        result += self.buildSettingsFlags()
        result += buildParameters.toolchain.extraSwiftCFlags
        result += buildParameters.swiftCompilerFlags
        return result
    }

    /// Returns true if ObjC compatibility header should be emitted.
    private var shouldEmitObjCCompatibilityHeader: Bool {
        return buildParameters.triple.isDarwin() && target.type == .library
    }

    private func writeOutputFileMap() throws -> AbsolutePath {
        let path = tempsPath.appending(component: "output-file-map.json")
        let stream = BufferedOutputByteStream()

        stream <<< "{\n"

        let masterDepsPath = tempsPath.appending(component: "master.swiftdeps")
        stream <<< "  \"\": {\n"
        if buildParameters.useWholeModuleOptimization {
            let moduleName = target.c99name
            stream <<< "    \"dependencies\": \"" <<< tempsPath.appending(component: moduleName + ".d").nativePathString(escaped: true) <<< "\",\n"
            // FIXME: Need to record this deps file for processing it later.
            stream <<< "    \"object\": \"" <<< tempsPath.appending(component: moduleName + ".o").nativePathString(escaped: true) <<< "\",\n"
        }
        stream <<< "    \"swift-dependencies\": \"" <<< masterDepsPath.nativePathString(escaped: true) <<< "\"\n"

        stream <<< "  },\n"

        // Write out the entries for each source file.
        let sources = target.sources.paths + derivedSources.paths + pluginDerivedSources.paths
        for (idx, source) in sources.enumerated() {
            let object = objects[idx]
            let objectDir = object.parentDirectory

            let sourceFileName = source.basenameWithoutExt

            let swiftDepsPath = objectDir.appending(component: sourceFileName + ".swiftdeps")

            stream <<< "  \"" <<< source.nativePathString(escaped: true) <<< "\": {\n"

            if (!buildParameters.useWholeModuleOptimization) {
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
        let path = tempsPath.appending(component: moduleMapFilename)

        let stream = BufferedOutputByteStream()
        stream <<< "module \(target.c99name) {\n"
        stream <<< "    header \"" <<< objCompatibilityHeaderPath.pathString <<< "\"\n"
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
        return tempsPath.appending(component: "\(target.name)-Swift.h")
    }

    /// Returns the build flags from the declared build settings.
    private func buildSettingsFlags() -> [String] {
        let scope = buildParameters.createScope(for: target)
        var flags: [String] = []

        // Swift defines.
        let swiftDefines = scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS)
        flags += swiftDefines.map({ "-D" + $0 })

        // Other Swift flags.
        flags += scope.evaluate(.OTHER_SWIFT_FLAGS)

        // Add C flags by prefixing them with -Xcc.
        //
        // C defines.
        let cDefines = scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS)
        flags += cDefines.flatMap({ ["-Xcc", "-D" + $0] })

        // Header search paths.
        let headerSearchPaths = scope.evaluate(.HEADER_SEARCH_PATHS)
        flags += headerSearchPaths.flatMap({ path -> [String] in
            return ["-Xcc", "-I\(target.sources.root.appending(RelativePath(path)).pathString)"]
        })

        // Other C flags.
        flags += scope.evaluate(.OTHER_CFLAGS).flatMap({ ["-Xcc", $0] })

        return flags
    }

    /// A list of compilation conditions to enable for conditional compilation expressions.
    private var activeCompilationConditions: [String] {
        var compilationConditions = ["-DSWIFT_PACKAGE"]

        switch buildParameters.configuration {
        case .debug:
            compilationConditions += ["-DDEBUG"]
        case .release:
            break
        }

        return compilationConditions
    }

    /// Optimization arguments according to the build configuration.
    private var optimizationArguments: [String] {
        switch buildParameters.configuration {
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
        } else if buildParameters.enableTestability {
            return ["-enable-testing"]
        } else {
            return []
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        return ["-module-cache-path", buildParameters.moduleCache.pathString]
    }

    private var stdlibArguments: [String] {
        if buildParameters.shouldLinkStaticSwiftStdlib &&
            buildParameters.triple.isSupportingStaticStdlib {
            return ["-static-stdlib"]
        } else {
            return []
        }
    }
}

/// The build description for a product.
public final class ProductBuildDescription {

    /// The reference to the product.
    public let product: ResolvedProduct

    /// The tools version of the package that declared the product.  This can
    /// can be used to conditionalize semantically significant changes in how
    /// a target is built.
    public let toolsVersion: ToolsVersion

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The path to the product binary produced.
    public var binary: AbsolutePath {
        return buildParameters.binaryPath(for: product)
    }

    /// All object files to link into this product.
    ///
    // Computed during build planning.
    public fileprivate(set) var objects = SortedArray<AbsolutePath>()

    /// The dynamic libraries this product needs to link with.
    // Computed during build planning.
    fileprivate(set) var dylibs: [ProductBuildDescription] = []

    /// Any additional flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The list of targets that are going to be linked statically in this product.
    fileprivate var staticTargets: [ResolvedTarget] = []

    /// The list of Swift modules that should be passed to the linker. This is required for debugging to work.
    fileprivate var swiftASTs: SortedArray<AbsolutePath> = .init()

    /// Paths to the binary libraries the product depends on.
    fileprivate var libraryBinaryPaths: Set<AbsolutePath> = []

    /// Paths to tools shipped in binary dependencies
    var availableTools: [String: AbsolutePath] = [:]

    /// Path to the temporary directory for this product.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: product.name + ".product")
    }

    /// Path to the link filelist file.
    var linkFileListPath: AbsolutePath {
        return tempsPath.appending(component: "Objects.LinkFileList")
    }

    /// File system reference.
    private let fileSystem: FileSystem

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// Create a build description for a product.
    init(product: ResolvedProduct, toolsVersion: ToolsVersion, buildParameters: BuildParameters, fileSystem: FileSystem, observabilityScope: ObservabilityScope) throws {
        guard product.type != .library(.automatic) else {
            throw InternalError("Automatic type libraries should not be described.")
        }

        self.product = product
        self.toolsVersion = toolsVersion
        self.buildParameters = buildParameters
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
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

    private var deadStripArguments: [String] {
        if !buildParameters.linkerDeadStrip {
            return []
        }

        switch buildParameters.configuration {
        case .debug:
            return []
        case .release:
            if buildParameters.triple.isDarwin() {
                return ["-Xlinker", "-dead_strip"]
            } else if buildParameters.triple.isWindows() {
                return ["-Xlinker", "/OPT:REF"]
            } else {
                return ["-Xlinker", "--gc-sections"]
            }
        }
    }

    /// The arguments to link and create this product.
    public func linkArguments() throws -> [String] {
        var args = [buildParameters.toolchain.swiftCompiler.pathString]
        args += buildParameters.sanitizers.linkSwiftFlags()
        args += additionalFlags

        // Pass `-g` during a *release* build so the Swift driver emits a dSYM file for the binary.
        if buildParameters.configuration == .release {
            if buildParameters.triple.isWindows() {
                args += ["-Xlinker", "-debug"]
            } else {
                args += ["-g"]
            }
        }

        // Only add the build path to the framework search path if there are binary frameworks to link against.
        if !libraryBinaryPaths.isEmpty {
            args += ["-F", buildParameters.buildPath.pathString]
        }

        args += ["-L", buildParameters.buildPath.pathString]
        args += ["-o", binary.pathString]
        args += ["-module-name", product.name.spm_mangledToC99ExtendedIdentifier()]
        args += dylibs.map({ "-l" + $0.product.name })

        // Add arguments needed for code coverage if it is enabled.
        if buildParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        let containsSwiftTargets = product.containsSwiftTargets

        switch product.type {
        case .library(.automatic):
            throw InternalError("automatic library not supported")
        case .library(.static):
            // No arguments for static libraries.
            return []
        case .test:
            // Test products are bundle when using objectiveC, executable when using test manifests.
            switch buildParameters.testDiscoveryStrategy {
            case .objectiveC:
                args += ["-Xlinker", "-bundle"]
            case .manifest:
                args += ["-emit-executable"]
            }
            args += deadStripArguments
        case .library(.dynamic):
            args += ["-emit-library"]
            if buildParameters.triple.isDarwin() {
                let relativePath = "@rpath/\(buildParameters.binaryRelativePath(for: product).pathString)"
                args += ["-Xlinker", "-install_name", "-Xlinker", relativePath]
            }
            args += deadStripArguments
        case .executable, .snippet:
            // Link the Swift stdlib statically, if requested.
            if buildParameters.shouldLinkStaticSwiftStdlib {
                if buildParameters.triple.isDarwin() {
                    self.observabilityScope.emit(.swiftBackDeployError)
                } else if buildParameters.triple.isSupportingStaticStdlib {
                    args += ["-static-stdlib"]
                }
            }
            args += ["-emit-executable"]
            args += deadStripArguments
            
            // If we're linking an executable whose main module is implemented in Swift,
            // we rename the `_<modulename>_main` entry point symbol to `_main` again.
            // This is because executable modules implemented in Swift are compiled with
            // a main symbol named that way to allow tests to link against it without
            // conflicts. If we're using a linker that doesn't support symbol renaming,
            // we will instead have generated a source file containing the redirect.
            // Support for linking tests against executables is conditional on the tools
            // version of the package that defines the executable product.
            let executableTarget = try product.executableTarget()
            if executableTarget.underlyingTarget is SwiftTarget, toolsVersion >= .v5_5,
               buildParameters.canRenameEntrypointFunctionName {
                if let flags = buildParameters.linkerFlagsForRenamingMainFunction(of: executableTarget) {
                    args += flags
                }
            }
        case .plugin:
            throw InternalError("unexpectedly asked to generate linker arguments for a plugin product")
        }

        // Set rpath such that dynamic libraries are looked up
        // adjacent to the product.
        if buildParameters.triple.isLinux() {
            args += ["-Xlinker", "-rpath=$ORIGIN"]
        } else if buildParameters.triple.isDarwin() {
            let rpath = product.type == .test ? "@loader_path/../../../" : "@loader_path"
            args += ["-Xlinker", "-rpath", "-Xlinker", rpath]
        }
        args += ["@\(linkFileListPath.pathString)"]

        // Embed the swift stdlib library path inside tests and executables on Darwin.
        if containsSwiftTargets {
          let useStdlibRpath: Bool
          switch product.type {
          case .library(let type):
            useStdlibRpath = type == .dynamic
          case .test, .executable, .snippet:
            useStdlibRpath = true
          case .plugin:
            throw InternalError("unexpectedly asked to generate linker arguments for a plugin product")
          }

          if useStdlibRpath && buildParameters.triple.isDarwin() {
            let stdlib = buildParameters.toolchain.macosSwiftStdlib
            args += ["-Xlinker", "-rpath", "-Xlinker", stdlib.pathString]
          }

          // When deploying to macOS prior to macOS 12, add an rpath to the
          // back-deployed concurrency libraries.
          if buildParameters.triple.isDarwin(),
             let macOSSupportedPlatform = product.targets[0].underlyingTarget.getSupportedPlatform(for: .macOS),
             macOSSupportedPlatform.version.major < 12 {
            let backDeployedStdlib = buildParameters.toolchain.macosSwiftStdlib
              .parentDirectory
              .parentDirectory
              .appending(component: "swift-5.5")
              .appending(component: "macosx")
            args += ["-Xlinker", "-rpath", "-Xlinker", backDeployedStdlib.pathString]
          }
        }

        // Don't link runtime compatibility patch libraries if there are no
        // Swift sources in the target.
        if !containsSwiftTargets {
          args += ["-runtime-compatibility-version", "none"]
        }

        // Add the target triple from the first target in the product.
        //
        // We can just use the first target of the product because the deployment target
        // setting is the package-level right now. We might need to figure out a better
        // answer for libraries if/when we support specifying deployment target at the
        // target-level.
        args += try buildParameters.targetTripleArgs(for: product.targets[0])

        // Add arguments from declared build settings.
        args += self.buildSettingsFlags()

        // Add AST paths to make the product debuggable. This array is only populated when we're
        // building for Darwin in debug configuration.
        args += swiftASTs.flatMap{ ["-Xlinker", "-add_ast_path", "-Xlinker", $0.pathString] }

        args += buildParameters.toolchain.extraSwiftCFlags
        // User arguments (from -Xlinker and -Xswiftc) should follow generated arguments to allow user overrides
        args += buildParameters.linkerFlags
        args += stripInvalidArguments(buildParameters.swiftCompilerFlags)

        // Add toolchain's libdir at the very end (even after the user -Xlinker arguments).
        //
        // This will allow linking to libraries shipped in the toolchain.
        let toolchainLibDir = buildParameters.toolchain.toolchainLibDir
        if self.fileSystem.isDirectory(toolchainLibDir) {
            args += ["-L", toolchainLibDir.pathString]
        }

        return args
    }

    /// Writes link filelist to the filesystem.
    func writeLinkFilelist(_ fs: FileSystem) throws {
        let stream = BufferedOutputByteStream()

        for object in objects {
            stream <<< object.pathString.spm_shellEscaped() <<< "\n"
        }

        try fs.createDirectory(linkFileListPath.parentDirectory, recursive: true)
        try fs.writeFileContents(linkFileListPath, bytes: stream.bytes)
    }

    /// Returns the build flags from the declared build settings.
    private func buildSettingsFlags() -> [String] {
        var flags: [String] = []

        // Linked libraries.
        let libraries = OrderedSet(staticTargets.reduce([]) {
            $0 + buildParameters.createScope(for: $1).evaluate(.LINK_LIBRARIES)
        })
        flags += libraries.map({ "-l" + $0 })

        // Linked frameworks.
        let frameworks = OrderedSet(staticTargets.reduce([]) {
            $0 + buildParameters.createScope(for: $1).evaluate(.LINK_FRAMEWORKS)
        })
        flags += frameworks.flatMap({ ["-framework", $0] })

        // Other linker flags.
        for target in staticTargets {
            let scope = buildParameters.createScope(for: target)
            flags += scope.evaluate(.OTHER_LDFLAGS)
        }

        return flags
    }
}

/// Description for a plugin target. This is treated a bit differently from the
/// regular kinds of targets, and is not included in the LLBuild description.
/// But because the package graph and build plan are not loaded for incremental
/// builds, this information is included in the BuildDescription, and the plugin
/// targets are compiled directly.
public final class PluginDescription: Codable {
    
    /// The identity of the package in which the plugin is defined.
    public let package: PackageIdentity
    
    /// The name of the plugin target in that package (this is also the name of
    /// the plugin).
    public let targetName: String

    /// The names of any plugin products in that package that vend the plugin
    /// to other packages.
    public let productNames: [String]

    /// The tools version of the package that declared the target. This affects
    /// the API that is available in the PackagePlugin module.
    public let toolsVersion: ToolsVersion
    
    /// Swift source files that comprise the plugin.
    public let sources: Sources

    /// Initialize a new plugin target description. The target is expected to be
    /// a `PluginTarget`.
    init(
        target: ResolvedTarget,
        products: [ResolvedProduct],
        package: ResolvedPackage,
        toolsVersion: ToolsVersion,
        testDiscoveryTarget: Bool = false,
        fileSystem: FileSystem
    ) throws {
        guard target.underlyingTarget is PluginTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }

        self.package = package.identity
        self.targetName = target.name
        self.productNames = products.map{ $0.name }
        self.toolsVersion = toolsVersion
        self.sources = target.sources
    }
}

/// A build plan for a package graph.
public class BuildPlan {

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        /// There is no buildable target in the graph.
        case noBuildableTarget

        public var description: String {
            switch self {
            case .noBuildableTarget:
                return "the package does not contain a buildable target"
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
    public var buildProducts: AnySequence<ProductBuildDescription> {
        return AnySequence(productMap.values)
    }

    /// The results of invoking any build tool plugins used by targets in this build.
    public let buildToolPluginInvocationResults: [ResolvedTarget: [BuildToolPluginInvocationResult]]

    /// The results of running any prebuild commands for the targets in this build.  This includes any derived
    /// source files as well as directories to which any changes should cause us to reevaluate the build plan.
    public let prebuildCommandResults: [ResolvedTarget: [PrebuildCommandResult]]

    private var testManifestTargetsMap: [ResolvedProduct: ResolvedTarget] = [:]

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

    private static func makeTestManifestTargets(
        _ buildParameters: BuildParameters,
        _ graph: PackageGraph,
        _ fileSystem: FileSystem,
        _ observabilityScope: ObservabilityScope
    ) throws -> [(product: ResolvedProduct, targetBuildDescription: SwiftTargetBuildDescription)] {
        guard case .manifest(let generate) = buildParameters.testDiscoveryStrategy else {
            throw InternalError("makeTestManifestTargets should not be used for build plan with useTestManifest set to false")
        }

        var generateRedundant = generate
        var result: [(ResolvedProduct, SwiftTargetBuildDescription)] = []
        for testProduct in graph.allProducts where testProduct.type == .test {
            generateRedundant = generateRedundant && nil == testProduct.testManifestTarget
            // if test manifest exists, prefer that over test detection,
            // this is designed as an escape hatch when test discovery is not appropriate
            // and for backwards compatibility for projects that have existing test manifests (LinuxMain.swift)
            let toolsVersion = graph.package(for: testProduct)?.manifest.toolsVersion ?? .v5_5
            if let testManifestTarget = testProduct.testManifestTarget, !generate {
                let desc = try SwiftTargetBuildDescription(
                    target: testManifestTarget,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    isTestTarget: true,
                    fileSystem: fileSystem
                )

                result.append((testProduct, desc))
            } else {
                // We'll generate sources containing the test names as part of the build process.
                let derivedTestListDir = buildParameters.buildPath.appending(components: "\(testProduct.name).derived")
                let mainFile = derivedTestListDir.appending(component: LLBuildManifest.TestDiscoveryTool.mainFileName)

                var paths: [AbsolutePath] = []
                paths.append(mainFile)
                for testTarget in testProduct.targets {
                    let path = derivedTestListDir.appending(components: testTarget.name + ".swift")
                    paths.append(path)
                }

                let src = Sources(paths: paths, root: derivedTestListDir)

                let swiftTarget = SwiftTarget(
                    testDiscoverySrc: src,
                    name: testProduct.name,
                    dependencies: testProduct.underlyingProduct.targets.map { .target($0, conditions: []) }
                )
                let testManifestTarget = ResolvedTarget(
                    target: swiftTarget,
                    dependencies: testProduct.targets.map { .target($0, conditions: []) }
                )

                let target = try SwiftTargetBuildDescription(
                    target: testManifestTarget,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    isTestTarget: true,
                    isTestDiscoveryTarget: true,
                    fileSystem: fileSystem
                )

                result.append((testProduct, target))
            }
        }

        if generateRedundant {
            observabilityScope.emit(warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms")
        }

        return result
    }

    @available(*, deprecated, message: "use observability system instead")
    public convenience init(
        buildParameters: BuildParameters,
        graph: PackageGraph,
        buildToolPluginInvocationResults: [ResolvedTarget: [BuildToolPluginInvocationResult]] = [:],
        prebuildCommandResults: [ResolvedTarget: [PrebuildCommandResult]] = [:],
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws {
        let observabilitySystem = ObservabilitySystem(diagnosticEngine: diagnostics)
        try self.init(
            buildParameters: buildParameters,
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observabilitySystem.topScope
        )
    }

    /// Create a build plan with build parameters and a package graph.
    public init(
        buildParameters: BuildParameters,
        graph: PackageGraph,
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

        // Create build target description for each target which we need to plan.
        // Plugin targets are noted, since they need to be compiled, but they do
        // not get directly incorporated into the build description that will be
        // given to LLBuild.
        var targetMap = [ResolvedTarget: TargetBuildDescription]()
        var pluginDescriptions = [PluginDescription]()
        for target in graph.allTargets.sorted(by: { $0.name < $1.name }) {

            // Validate the product dependencies of this target.
            for dependency in target.dependencies {
                switch dependency {
                case .target: break
                case .product(let product, _):
                    if buildParameters.triple.isDarwin() {
                        try BuildPlan.validateDeploymentVersionOfProductDependency(
                            product,
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
                targetMap[target] = try .swift(SwiftTargetBuildDescription(
                    target: target,
                    toolsVersion: toolsVersion,
                    buildParameters: buildParameters,
                    buildToolPluginInvocationResults: buildToolPluginInvocationResults[target] ?? [],
                    prebuildCommandResults: prebuildCommandResults[target] ?? [],
                    fileSystem: fileSystem)
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

        // Plan the test manifest target.
        if case .manifest = buildParameters.testDiscoveryStrategy {
            let testManifestTargets = try Self.makeTestManifestTargets(buildParameters, graph, self.fileSystem, self.observabilityScope)
            for item in testManifestTargets {
                targetMap[item.targetBuildDescription.target] = .swift(item.targetBuildDescription)
                testManifestTargetsMap[item.product] = item.targetBuildDescription.target
            }
        }

        var productMap: [ResolvedProduct: ProductBuildDescription] = [:]
        // Create product description for each product we have in the package graph except
        // for automatic libraries and plugins, because they don't produce any output.
        for product in graph.allProducts where product.type != .library(.automatic) && product.type != .plugin {

            // Determine the appropriate tools version to use for the product.
            // This can affect what flags to pass and other semantics.
            let toolsVersion = graph.package(for: product)?.manifest.toolsVersion ?? .v5_5
            productMap[product] = try ProductBuildDescription(
                product: product,
                toolsVersion: toolsVersion,
                buildParameters: buildParameters,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        }

        self.productMap = productMap
        self.targetMap = targetMap
        self.pluginDescriptions = pluginDescriptions
        
        // Finally plan these targets.
        try plan()
    }

    static func validateDeploymentVersionOfProductDependency(
        _ product: ResolvedProduct,
        forTarget target: ResolvedTarget,
        observabilityScope: ObservabilityScope
    ) throws {
        // Get the first target as supported platforms are on the top-level.
        // This will need to become a bit complicated once we have target-level platform support.
        let productTarget = product.underlyingProduct.targets[0]

        guard let productPlatform = productTarget.getSupportedPlatform(for: .macOS) else {
            throw StringError("Expected supported platform macOS in product target \(productTarget)")
        }
        guard let targetPlatform = target.underlyingTarget.getSupportedPlatform(for: .macOS) else {
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
            try plan(buildProduct)
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
            buildProduct.additionalFlags += pkgConfig(for: target).libs
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
                buildProduct.additionalFlags += self.buildParameters.toolchain.extraCPPFlags
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
                // Swift products. Debugging statergy is computed based on the current platform we're
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
            return target.objects
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
            // Include all the depenencies of a target.
            case .target(let target, _):
                return target.dependencies.filter { $0.satisfies(self.buildEnvironment) }

            // For a product dependency, we only include its content only if we
            // need to statically link it or if it's a plugin.
            case .product(let product, _):
                switch product.type {
                case .library(.automatic), .library(.static), .plugin:
                    return product.targets.map { .target($0, conditions: []) }
                case .library(.dynamic), .test, .executable, .snippet:
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
                case .executable, .snippet:
                    if product.targets.contains(target) {
                        staticTargets.append(target)
                    } else if product.type == .test && target.underlyingTarget is SwiftTarget {
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

        // add test manifest targets
        if case .manifest = buildParameters.testDiscoveryStrategy {
            if product.type == .test, let testManifestTarget = testManifestTargetsMap[product] {
                staticTargets.append(testManifestTarget)
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
                clangTarget.additionalFlags += pkgConfig(for: target).cFlags
            case let target as BinaryTarget:
                if case .xcframework = target.kind {
                    let libraries = try self.parseXCFramework(for: target)
                    for library in libraries {
                        if let headersPath = library.headersPath {
                            clangTarget.additionalFlags += ["-I", headersPath.pathString]
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
                swiftTarget.additionalFlags += pkgConfig(for: target).cFlags
            case let target as BinaryTarget:
                if case .xcframework = target.kind {
                    let libraries = try self.parseXCFramework(for: target)
                    for library in libraries {
                        if let headersPath = library.headersPath {
                            swiftTarget.additionalFlags += ["-Xcc", "-I", "-Xcc", headersPath.pathString]
                        }
                        swiftTarget.libraryBinaryPaths.insert(library.libraryPath)
                    }
                }
            default:
                break
            }
        }
    }

    public func createAPIToolCommonArgs(includeLibrarySearchPaths: Bool) -> [String] {
        let buildPath = buildParameters.buildPath.pathString
        var arguments = ["-I", buildPath]

        var extraSwiftCFlags = buildParameters.toolchain.extraSwiftCFlags
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
                arguments.append(contentsOf: self.pkgConfig(for: systemLib).cFlags)
                // Add the path to the module map.
                arguments += ["-I", systemLib.moduleMapPath.parentDirectory.pathString]
            }
        }

        return arguments
    }

    /// Creates arguments required to launch the Swift REPL that will allow
    /// importing the modules in the package graph.
    public func createREPLArguments() -> [String] {
        let buildPath = buildParameters.buildPath.pathString
        var arguments = ["-I" + buildPath, "-L" + buildPath]

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
                arguments += self.pkgConfig(for: systemLib).cFlags
            }
        }

        return arguments
    }

    /// Get pkgConfig arguments for a system library target.
    private func pkgConfig(for target: SystemLibraryTarget) -> (cFlags: [String], libs: [String]) {
        // If we already have these flags, we're done.
        if let flags = pkgConfigCache[target] {
            return flags
        }
        else {
            pkgConfigCache[target] = ([], [])
        }
        let results = pkgConfigArgs(for: target, fileSystem: self.fileSystem, observabilityScope: self.observabilityScope)
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
            return try target.parseArtifactArchives(for: self.buildParameters.triple, fileSystem: self.fileSystem)
        }
    }
}

private extension Basics.Diagnostic {
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
    /// Returns a target's bundle path inside the build directory.
    fileprivate func bundlePath(for target: ResolvedTarget) -> AbsolutePath? {
        target.underlyingTarget.bundleName
        .map{ $0 + triple.nsbundleExtension }
        .map(buildPath.appending(component:))
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
private func generateResourceInfoPlist(
    fileSystem: FileSystem,
    target: ResolvedTarget,
    path: AbsolutePath
) throws -> Bool {
    guard let defaultLocalization = target.underlyingTarget.defaultLocalization else {
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

fileprivate extension TSCUtility.Triple {
    var isSupportingStaticStdlib: Bool {
        isLinux() || arch == .wasm32
    }
}
