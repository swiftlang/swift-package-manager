/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import SPMUtility
import PackageModel
import PackageGraph
import PackageLoading
import func POSIX.getenv

public struct BuildParameters {

    /// Mode for the indexing-while-building feature.
    public enum IndexStoreMode: Equatable {
        /// Index store should be enabled.
        case on
        /// Index store should be disabled.
        case off
        /// Index store should be enabled in debug configuration.
        case auto
    }

    // FIXME: Error handling.
    //
    /// Path to the module cache directory to use for SwiftPM's own tests.
    public static let swiftpmTestCache = resolveSymlinks(try! determineTempDirectory()).appending(component: "org.swift.swiftpm.tests-3")

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
    public let configuration: BuildConfiguration

    /// The path to the build directory (inside the data directory).
    public var buildPath: AbsolutePath {
        return dataPath.appending(component: configuration.dirname)
    }

    /// The path to the index store directory.
    public var indexStore: AbsolutePath {
        assert(indexStoreMode != .off, "index store is disabled")
        return buildPath.appending(components: "index", "store")
    }

    /// The path to the code coverage directory.
    public var codeCovPath: AbsolutePath {
        return buildPath.appending(component: "codecov")
    }

    /// The path to the code coverage profdata file.
    public var codeCovDataFile: AbsolutePath {
        return codeCovPath.appending(component: "default.profdata")
    }

    /// The toolchain.
    public let toolchain: Toolchain

    /// Destination triple.
    public let triple: Triple

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

    /// The tools version to use.
    public let toolsVersion: ToolsVersion

    /// If should link the Swift stdlib statically.
    public let shouldLinkStaticSwiftStdlib: Bool

    /// Which compiler sanitizers should be enabled
    public let sanitizers: EnabledSanitizers

    /// If should enable llbuild manifest caching.
    public let shouldEnableManifestCaching: Bool

    /// The mode to use for indexing-while-building feature.
    public let indexStoreMode: IndexStoreMode

    /// Whether to enable code coverage.
    public let enableCodeCoverage: Bool

    /// Whether to enable generation of `.swiftinterface` files alongside
    /// `.swiftmodule`s.
    public let enableParseableModuleInterfaces: Bool

    /// Checks if stdout stream is tty.
    fileprivate let isTTY: Bool = {
        guard let stream = stdoutStream.stream as? LocalFileOutputByteStream else {
            return false
        }
        return TerminalController.isTTY(stream)
    }()

    public var regenerateManifestToken: AbsolutePath {
        return dataPath.appending(components: "..", "regenerate-token")
    }

    public var llbuildManifest: AbsolutePath {
        return dataPath.appending(components: "..", configuration.dirname + ".yaml")
    }

    public init(
        dataPath: AbsolutePath,
        configuration: BuildConfiguration,
        toolchain: Toolchain,
        destinationTriple: Triple = Triple.hostTriple,
        flags: BuildFlags,
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        shouldLinkStaticSwiftStdlib: Bool = false,
        shouldEnableManifestCaching: Bool = false,
        sanitizers: EnabledSanitizers = EnabledSanitizers(),
        enableCodeCoverage: Bool = false,
        indexStoreMode: IndexStoreMode = .auto,
        enableParseableModuleInterfaces: Bool = false
    ) {
        self.dataPath = dataPath
        self.configuration = configuration
        self.toolchain = toolchain
        self.triple = destinationTriple
        self.flags = flags
        self.toolsVersion = toolsVersion
        self.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
        self.shouldEnableManifestCaching = shouldEnableManifestCaching
        self.sanitizers = sanitizers
        self.enableCodeCoverage = enableCodeCoverage
        self.indexStoreMode = indexStoreMode
        self.enableParseableModuleInterfaces = enableParseableModuleInterfaces
    }

    /// Returns the compiler arguments for the index store, if enabled.
    fileprivate var indexStoreArguments: [String] {
        let addIndexStoreArguments: Bool
        switch indexStoreMode {
        case .on:
            addIndexStoreArguments = true
        case .off:
            addIndexStoreArguments = false
        case .auto:
            addIndexStoreArguments = configuration == .debug
        }

        if addIndexStoreArguments {
            return ["-index-store-path", indexStore.pathString]
        }
        return []
    }

    /// Computes the target triple arguments for a given resolved target.
    fileprivate func targetTripleArgs(for target: ResolvedTarget) -> [String] {
        var args = ["-target"]
        // Compute the triple string for Darwin platform using the platform version.
        if triple.isDarwin() {
            guard let macOSSupportedPlatform = target.underlyingTarget.getSupportedPlatform(for: .macOS) else {
                fatalError("the target \(target) doesn't support building for macOS")
            }
            args += [triple.tripleString(forPlatformVersion: macOSSupportedPlatform.version.versionString)]
        } else {
            args += [triple.tripleString]
        }
        return args
    }

    /// The current platform we're building for.
    var currentPlatform: PackageModel.Platform {
        if self.triple.isDarwin() {
            return .macOS
        } else {
            return .linux
        }
    }

    /// Returns the scoped view of build settings for a given target.
    fileprivate func createScope(for target: ResolvedTarget) -> BuildSettings.Scope {
        return BuildSettings.Scope(target.underlyingTarget.buildSettings, boundCondition: (currentPlatform, configuration))
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
}

/// Target description for a Clang target i.e. C language family target.
public final class ClangTargetBuildDescription {

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
            let object = tempsPath.appending(RelativePath("\(source.pathString).o"))
            let deps = tempsPath.appending(RelativePath("\(source.pathString).d"))
            return (source, path, object, deps)
        })
    }

    /// Builds up basic compilation arguments for this target.
    public func basicArguments() -> [String] {
        var args = [String]()
        // Only enable ARC on macOS.
        if buildParameters.triple.isDarwin() {
            args += ["-fobjc-arc"]
        }
        args += buildParameters.targetTripleArgs(for: target)
        args += buildParameters.toolchain.extraCCFlags
        args += optimizationArguments
        args += activeCompilationConditions
        args += ["-fblocks"]

        // Enable index store, if appropriate.
        //
        // This feature is not widely available in OSS clang. So, we only enable
        // index store for Apple's clang or if explicitly asked to.
        if Process.env.keys.contains("SWIFTPM_ENABLE_CLANG_INDEX_STORE") {
            args += buildParameters.indexStoreArguments
        } else if buildParameters.triple.isDarwin(), (try? buildParameters.toolchain._isClangCompilerVendorApple()) == true {
            args += buildParameters.indexStoreArguments
        }

        if !buildParameters.triple.isWindows() {
            // Using modules currently conflicts with the Windows SDKs.
            args += ["-fmodules", "-fmodule-name=" + target.c99name]
        }
        args += ["-I", clangTarget.includeDir.pathString]
        args += additionalFlags
        if !buildParameters.triple.isWindows() {
            args += moduleCacheArgs
        }
        args += buildParameters.sanitizers.compileCFlags()

        // Add agruments from declared build settings.
        args += self.buildSettingsFlags()

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

        // Frameworks.
        let frameworks = scope.evaluate(.LINK_FRAMEWORKS)
        flags += frameworks.flatMap({ ["-framework", $0] })

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
            if buildParameters.triple.isWindows() {
                return ["-g", "-gcodeview", "-O0"]
            } else {
                return ["-g", "-O0"]
            }
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


    /// Helper function to compute the modulemap path.
    ///
    /// This function either returns path to user provided modulemap or tries to automatically generates it.
    private func computeModulemapPath() throws -> AbsolutePath {
        // If user provided the modulemap, we're done.
        if fileSystem.isFile(clangTarget.moduleMapPath) {
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
        return ["-fmodules-cache-path=\(buildParameters.moduleCache.pathString)"]
    }
}

/// Target description for a Swift target.
public final class SwiftTargetBuildDescription {

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
        return target.sources.relativePaths.map({ tempsPath.appending(RelativePath("\($0.pathString).o")) })
    }

    /// The path to the swiftmodule file after compilation.
    var moduleOutputPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".swiftmodule")
    }

    /// The path to the swifinterface file after compilation.
    var parseableModuleInterfaceOutputPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: target.c99name + ".swiftinterface")
    }

    /// Any addition flags to be added. These flags are expected to be computed during build planning.
    fileprivate var additionalFlags: [String] = []

    /// The swift version for this target.
    var swiftVersion: SwiftLanguageVersion {
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
        args += buildParameters.targetTripleArgs(for: target)
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

        args += buildParameters.indexStoreArguments
        args += buildParameters.toolchain.extraSwiftCFlags
        args += optimizationArguments
        args += ["-j\(SwiftCompilerTool.numThreads)"]
        args += activeCompilationConditions
        args += additionalFlags
        args += moduleCacheArgs
        args += buildParameters.sanitizers.compileSwiftFlags()

        // Add arguments needed for code coverage if it is enabled.
        if buildParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        // Add arguments to colorize output if stdout is tty
        if buildParameters.isTTY {
            args += ["-Xfrontend", "-color-diagnostics"]
        }

        // Add the output for the `.swiftinterface`, if requested.
        if buildParameters.enableParseableModuleInterfaces {
            args += ["-emit-parseable-module-interface-path", parseableModuleInterfaceOutputPath.pathString]
        }

        // Add agruments from declared build settings.
        args += self.buildSettingsFlags()

        // User arguments (from -Xswiftc) should follow generated arguments to allow user overrides
        args += buildParameters.swiftCompilerFlags
        return args
    }

    /// Returns the build flags from the declared build settings.
    private func buildSettingsFlags() -> [String] {
        let scope = buildParameters.createScope(for: target)
        var flags: [String] = []

        // Swift defines.
        let swiftDefines = scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS)
        flags += swiftDefines.map({ "-D" + $0 })

        // Frameworks.
        let frameworks = scope.evaluate(.LINK_FRAMEWORKS)
        flags += frameworks.flatMap({ ["-framework", $0] })

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
            return ["-Onone", "-g", "-enable-testing"]
        case .release:
            return ["-O"]
        }
    }

    /// Module cache arguments.
    private var moduleCacheArgs: [String] {
        return ["-module-cache-path", buildParameters.moduleCache.pathString]
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
            if buildParameters.triple.isWindows() {
                return RelativePath("\(name).exe")
            } else {
                return RelativePath(name)
            }
        case .library(.static):
            return RelativePath("lib\(name).a")
        case .library(.dynamic):
            return RelativePath("lib\(name)\(self.buildParameters.triple.dynamicLibraryExtension)")
        case .library(.automatic):
            fatalError()
        case .test:
            let base = "\(name).xctest"
            if buildParameters.triple.isDarwin() {
                return RelativePath("\(base)/Contents/MacOS/\(name)")
            } else {
                return RelativePath(base)
            }
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

    /// The list of targets that are going to be linked statically in this product.
    fileprivate var staticTargets: [ResolvedTarget] = []

    /// Path to the temporary directory for this product.
    var tempsPath: AbsolutePath {
        return buildParameters.buildPath.appending(component: product.name + ".product")
    }

    /// Path to the link filelist file.
    var linkFileListPath: AbsolutePath {
        return tempsPath.appending(component: "Objects.LinkFileList")
    }

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
        var args = [buildParameters.toolchain.swiftCompiler.pathString]
        args += buildParameters.toolchain.extraSwiftCFlags
        args += buildParameters.sanitizers.linkSwiftFlags()
        args += additionalFlags

        if buildParameters.configuration == .debug {
            if buildParameters.triple.isWindows() {
                args += ["-Xlinker","-debug"]
            } else {
                args += ["-g"]
            }
        }
        args += ["-L", buildParameters.buildPath.pathString]
        args += ["-o", binary.pathString]
        args += ["-module-name", product.name.spm_mangledToC99ExtendedIdentifier()]
        args += dylibs.map({ "-l" + $0.product.name })

        // Add arguements needed for code coverage if it is enabled.
        if buildParameters.enableCodeCoverage {
            args += ["-profile-coverage-mapping", "-profile-generate"]
        }

        switch product.type {
        case .library(.automatic):
            fatalError()
        case .library(.static):
            // No arguments for static libraries.
            return []
        case .test:
            // Test products are bundle on macOS, executable on linux.
            if buildParameters.triple.isDarwin() {
                args += ["-Xlinker", "-bundle"]
            } else {
                args += ["-emit-executable"]
            }
        case .library(.dynamic):
            args += ["-emit-library"]
        case .executable:
            // Link the Swift stdlib statically if requested.
            if buildParameters.shouldLinkStaticSwiftStdlib {
                // FIXME: This does not work for linux yet (SR-648).
                if !buildParameters.triple.isLinux() {
                    args += ["-static-stdlib"]
                }
            }
            args += ["-emit-executable"]
        }

        // On linux, set rpath such that dynamic libraries are looked up
        // adjacent to the product. This happens by default on macOS.
        if buildParameters.triple.isLinux() {
            args += ["-Xlinker", "-rpath=$ORIGIN"]
        }
        args += ["@\(linkFileListPath.pathString)"]

        // Embed the swift stdlib library path inside tests and executables on Darwin.
        switch product.type {
        case .library: break
        case .test, .executable:
            if buildParameters.triple.isDarwin() {
                let stdlib = buildParameters.toolchain.macosSwiftStdlib
                args += ["-Xlinker", "-rpath", "-Xlinker", stdlib.pathString]
            }
        }

        // Add agruments from declared build settings.
        args += self.buildSettingsFlags()

        // User arguments (from -Xlinker and -Xswiftc) should follow generated arguments to allow user overrides
        args += buildParameters.linkerFlags
        args += stripInvalidArguments(buildParameters.swiftCompilerFlags)
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

/// A build plan for a package graph.
public class BuildPlan {

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        /// The linux main file is missing.
        case missingLinuxMain

        /// There is no buildable target in the graph.
        case noBuildableTarget

        public var description: String {
            switch self {
            case .missingLinuxMain:
                return "missing LinuxMain.swift file in the Tests directory"
            case .noBuildableTarget:
                return "the package does not contain a buildable target"
            }
        }
    }

    /// The build parameters.
    public let buildParameters: BuildParameters

    /// The package graph.
    public let graph: PackageGraph

    /// The target build description map.
    public let targetMap: [ResolvedTarget: TargetBuildDescription]

    /// The product build description map.
    public let productMap: [ResolvedProduct: ProductBuildDescription]

    /// The build targets.
    public var targets: AnySequence<TargetBuildDescription> {
        return AnySequence(targetMap.values)
    }

    /// The products in this plan.
    public var buildProducts: AnySequence<ProductBuildDescription> {
        return AnySequence(productMap.values)
    }

    /// The filesystem to operate on.
    let fileSystem: FileSystem

    /// Diagnostics Engine to emit diagnostics
    let diagnostics: DiagnosticsEngine

    /// Create a build plan with build parameters and a package graph.
    public init(
        buildParameters: BuildParameters,
        graph: PackageGraph,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem = localFileSystem
    ) throws {
        self.buildParameters = buildParameters
        self.graph = graph
        self.diagnostics = diagnostics
        self.fileSystem = fileSystem

        // Create build target description for each target which we need to plan.
        var targetMap = [ResolvedTarget: TargetBuildDescription]()
        for target in graph.allTargets {

            // Validate the product dependencies of this target.
            for dependency in target.dependencies {
                switch dependency {
                case .target: break
                case .product(let product):
                    if buildParameters.triple.isDarwin() {
                        BuildPlan.validateDeploymentVersionOfProductDependency(
                            product, forTarget: target, diagnostics: diagnostics)
                    }
                }
            }

             switch target.underlyingTarget {
             case is SwiftTarget:
                 targetMap[target] = .swift(SwiftTargetBuildDescription(target: target, buildParameters: buildParameters))
             case is ClangTarget:
                targetMap[target] = try .clang(ClangTargetBuildDescription(
                    target: target,
                    buildParameters: buildParameters,
                    fileSystem: fileSystem))
             case is SystemLibraryTarget:
                 break
             default:
                 fatalError("unhandled \(target.underlyingTarget)")
             }
        }

        /// Ensure we have at least one buildable target.
        guard !targetMap.isEmpty else {
            throw Error.noBuildableTarget
        }

        // Abort now if we have any diagnostics at this point.
        guard !diagnostics.hasErrors else {
            throw Diagnostics.fatalError
        }

        if buildParameters.triple.isLinux() {
            // FIXME: Create a target for LinuxMain file on linux.
            // This will go away once it is possible to auto detect tests.
            let testProducts = graph.allProducts.filter({ $0.type == .test })

            for product in testProducts {
                guard let linuxMainTarget = product.linuxMainTarget else {
                    throw Error.missingLinuxMain
                }
                let target = SwiftTargetBuildDescription(
                        target: linuxMainTarget, buildParameters: buildParameters, isTestTarget: true)
                targetMap[linuxMainTarget] = .swift(target)
            }
        }

        var productMap: [ResolvedProduct: ProductBuildDescription] = [:]
        // Create product description for each product we have in the package graph except
        // for automatic libraries because they don't produce any output.
        for product in graph.allProducts where product.type != .library(.automatic) {
            productMap[product] = ProductBuildDescription(
                product: product, buildParameters: buildParameters)
        }

        self.productMap = productMap
        self.targetMap = targetMap
        // Finally plan these targets.
        try plan()
    }

    static func validateDeploymentVersionOfProductDependency(
        _ product: ResolvedProduct,
        forTarget target: ResolvedTarget,
        diagnostics: DiagnosticsEngine
    ) {
        // Get the first target as supported platforms are on the top-level.
        // This will need to become a bit complicated once we have target-level platform support.
        let productTarget = product.underlyingProduct.targets[0]

        guard let productPlatform = productTarget.getSupportedPlatform(for: .macOS) else {
            fatalError("Expected supported platform macOS in product target \(productTarget)")
        }
        guard let targetPlatform = target.underlyingTarget.getSupportedPlatform(for: .macOS) else {
            fatalError("Expected supported platform macOS in target \(target)")
        }

        // Check if the version requirement is satisfied.
        //
        // If the product's platform version is greater than ours, then it is incompatible.
        if productPlatform.version > targetPlatform.version {
            diagnostics.emit(data: ProductRequiresHigherPlatformVersion(product: product.name, platform: productPlatform))
        }
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
            try plan(buildProduct)
        }
        // FIXME: We need to find out if any product has a target on which it depends
        // both static and dynamically and then issue a suitable diagnostic or auto
        // handle that situation.
    }

    /// Plan a product.
    private func plan(_ buildProduct: ProductBuildDescription) throws {
        // Compute the product's dependency.
        let dependencies = computeDependencies(of: buildProduct.product)

        // Add flags for system targets.
        for systemModule in dependencies.systemModules {
            guard case let target as SystemLibraryTarget = systemModule.underlyingTarget else {
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

        buildProduct.staticTargets = dependencies.staticTargets
        buildProduct.dylibs = dependencies.dylibs.map({ productMap[$0]! })
        buildProduct.objects += dependencies.staticTargets.flatMap({ targetMap[$0]!.objects })

        // Write the link filelist file.
        //
        // FIXME: We should write this as a custom llbuild task once we adopt it
        // as a library.
        try buildProduct.writeLinkFilelist(fileSystem)
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

        if buildParameters.triple.isLinux() {
            if product.type == .test {
                product.linuxMainTarget.map({ staticTargets.append($0) })
            }
        }

        return (linkLibraries, staticTargets, systemModules)
    }

    /// Plan a Clang target.
    private func plan(clangTarget: ClangTargetBuildDescription) {
        for dependency in clangTarget.target.recursiveDependencies() {
            switch dependency.underlyingTarget {
            case let target as ClangTarget where target.type == .library:
                // Setup search paths for C dependencies:
                clangTarget.additionalFlags += ["-I", target.includeDir.pathString]
            case let target as SystemLibraryTarget:
                clangTarget.additionalFlags += ["-fmodule-map-file=\(target.moduleMapPath.pathString)"]
                clangTarget.additionalFlags += pkgConfig(for: target).cFlags
            default: continue
            }
        }
    }

    /// Plan a Swift target.
    private func plan(swiftTarget: SwiftTargetBuildDescription) throws {
        // We need to iterate recursive dependencies because Swift compiler needs to see all the targets a target
        // depends on.
        for dependency in swiftTarget.target.recursiveDependencies() {
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
                    "-Xcc", "-fmodule-map-file=\(moduleMap.pathString)",
                    "-I", target.clangTarget.includeDir.pathString,
                ]
            case let target as SystemLibraryTarget:
                swiftTarget.additionalFlags += ["-Xcc", "-fmodule-map-file=\(target.moduleMapPath.pathString)"]
                swiftTarget.additionalFlags += pkgConfig(for: target).cFlags
            default: break
            }
        }
    }

    /// Creates arguments required to launch the Swift REPL that will allow
    /// importing the modules in the package graph.
    public func createREPLArguments() -> [String] {
        let buildPath = buildParameters.buildPath.pathString
        var arguments = ["-I" + buildPath, "-L" + buildPath]

        // Link the special REPL product that contains all of the library targets.
        let replProductName = graph.rootPackages[0].manifest.name + Product.replProductSuffix
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
        // Otherwise, get the result and cache it.
        guard let result = pkgConfigArgs(for: target, diagnostics: diagnostics) else {
            pkgConfigCache[target] = ([], [])
            return pkgConfigCache[target]!
        }
        // If there is no pc file on system and we have an available provider, emit a warning.
        if let provider = result.provider, result.couldNotFindConfigFile {
            diagnostics.emit(data: PkgConfigHintDiagnostic(pkgConfigName: result.pkgConfigName, installText: provider.installText))
        } else if let error = result.error {
            diagnostics.emit(
                data: PkgConfigGenericDiagnostic(error: "\(error)"),
                location: PkgConfigDiagnosticLocation(pcFile: result.pkgConfigName, target: target.name))
        }
        pkgConfigCache[target] = (result.cFlags, result.libs)
        return pkgConfigCache[target]!
    }

    /// Cache for pkgConfig flags.
    private var pkgConfigCache = [SystemLibraryTarget: (cFlags: [String], libs: [String])]()
}

struct ProductRequiresHigherPlatformVersion: DiagnosticData {
    static let id = DiagnosticID(
        type: ProductRequiresHigherPlatformVersion.self,
        name: "org.swift.diags.\(ProductRequiresHigherPlatformVersion.self)",
        defaultBehavior: .error,
        description: {
            $0 <<< "the product" <<< { "'\($0.product)'" }
            $0 <<< "requires minimum platform version" <<< { $0.platform.version.versionString }
            $0 <<< "for" <<< { $0.platform.platform.name } <<< "platform"
    })

    public let product: String
    public let platform: SupportedPlatform

    init(product: String, platform: SupportedPlatform) {
        self.product = product
        self.platform = platform
    }
}
