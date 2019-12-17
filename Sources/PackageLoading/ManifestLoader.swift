/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel
import TSCUtility
import SPMLLBuild
import class Foundation.ProcessInfo
public typealias FileSystem = TSCBasic.FileSystem

public enum ManifestParseError: Swift.Error {
    /// The manifest contains invalid format.
    case invalidManifestFormat(String, diagnosticFile: AbsolutePath?)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])

    /// The manifest contains a product that references no targets.
    case emptyProductTargets(productName: String)

    /// The manifest contains a product that references a target that does not exist.
    case productTargetNotFound(productName: String, targetName: String)

    /// The manifest contains dependencies with the same URL.
    case duplicateDependencyURLs([[PackageDependencyDescription]])

    /// The manifest contains dependencies with the same name.
    case duplicateDependencyNames([[PackageDependencyDescription]])

    /// The manifest contains targets with the same name.
    case duplicateTargetNames([String])

    /// The manifest contains target product dependencies that reference an unknown package.
    case unknownTargetDependencyPackage(targetName: String, packageName: String)
}

/// Resources required for manifest loading.
///
/// These requirements are abstracted out to make it easier to add support for
/// using the package manager with alternate toolchains in the future.
public protocol ManifestResourceProvider {
    /// The path of the swift compiler.
    var swiftCompiler: AbsolutePath { get }

    /// The path of the library resources.
    var libDir: AbsolutePath { get }

    /// The path to SDK root.
    ///
    /// If provided, it will be passed to the swift interpreter.
    var sdkRoot: AbsolutePath? { get }

    /// The bin directory.
    var binDir: AbsolutePath? { get }
}

/// Default implemention for the resource provider.
public extension ManifestResourceProvider {

    var sdkRoot: AbsolutePath? {
        return nil
    }

    var binDir: AbsolutePath? {
        return nil
    }
}

/// Protocol for the manifest loader interface.
public protocol ManifestLoaderProtocol {
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - toolsVersion: The version of the tools the manifest supports.
    ///   - kind: The kind of package the manifest is from.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    ///   - diagnostics: The diagnostics engine.
    func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        fileSystem: FileSystem?,
        diagnostics: DiagnosticsEngine?
    ) throws -> Manifest
}

extension ManifestLoaderProtocol {
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - toolsVersion: The version of the tools the manifest supports.
    ///   - kind: The kind of package the manifest is from.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    ///   - diagnostics: The diagnostics engine.
    public func load(
        package path: AbsolutePath,
        baseURL: String,
        version: Version? = nil,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        fileSystem: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> Manifest {
        return try load(
            packagePath: path,
            baseURL: baseURL,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            fileSystem: fileSystem,
            diagnostics: diagnostics
        )
    }
}

public protocol ManifestLoaderDelegate {
    func willLoad(manifest: AbsolutePath)
    func willParse(manifest: AbsolutePath)
}

/// Utility class for loading manifest files.
///
/// This class is responsible for reading the manifest data and produce a
/// properly formed `PackageModel.Manifest` object. It currently does so by
/// interpreting the manifest source using Swift -- that produces a JSON
/// serialized form of the manifest (as implemented by `PackageDescription`'s
/// `atexit()` handler) which is then deserialized and loaded.
public final class ManifestLoader: ManifestLoaderProtocol {

    let resources: ManifestResourceProvider
    let serializedDiagnostics: Bool
    let isManifestSandboxEnabled: Bool
    var isManifestCachingEnabled: Bool {
        return cacheDir != nil
    }
    let cacheDir: AbsolutePath!
    let delegate: ManifestLoaderDelegate?

    public init(
        manifestResources: ManifestResourceProvider,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        cacheDir: AbsolutePath? = nil,
        delegate: ManifestLoaderDelegate? = nil
    ) {
        self.resources = manifestResources
        self.serializedDiagnostics = serializedDiagnostics
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
        self.delegate = delegate

        // Resolve symlinks since we can't use them in sandbox profiles.
        if let cacheDir = cacheDir {
            try? localFileSystem.createDirectory(cacheDir, recursive: true)
        }
        self.cacheDir = cacheDir.map(resolveSymlinks)
    }

    @available(*, deprecated)
    public convenience init(
        resources: ManifestResourceProvider,
        isManifestSandboxEnabled: Bool = true
    ) {
        self.init(
            manifestResources: resources,
            isManifestSandboxEnabled: isManifestSandboxEnabled
       )
    }

    /// Loads a manifest from a package repository using the resources associated with a particular `swiftc` executable.
    ///
    /// - Parameters:
    ///     - packagePath: The absolute path of the package root.
    ///     - swiftCompiler: The absolute path of a `swiftc` executable.
    ///         Its associated resources will be used by the loader.
    ///     - kind: The kind of package the manifest is from.
    public static func loadManifest(
        packagePath: AbsolutePath,
        swiftCompiler: AbsolutePath,
        packageKind: PackageReference.Kind
    ) throws -> Manifest {
        let resources = try UserManifestResources(swiftCompiler: swiftCompiler)
        let loader = ManifestLoader(manifestResources: resources)
        let toolsVersion = try ToolsVersionLoader().load(at: packagePath, fileSystem: localFileSystem)
        return try loader.load(
            package: packagePath,
            baseURL: packagePath.pathString,
            toolsVersion: toolsVersion,
            packageKind: packageKind
        )
    }

    public func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        fileSystem: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> Manifest {
        return try loadFile(
            path: Manifest.path(atPackagePath: path, fileSystem: fileSystem ?? localFileSystem),
            baseURL: baseURL,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            fileSystem: fileSystem,
            diagnostics: diagnostics
        )
    }

    /// Create a manifest by loading a specific manifest file from the given `path`.
    ///
    /// - Parameters:
    ///   - path: The path to the manifest file (or a package root).
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - kind: The kind of package the manifest is from.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    func loadFile(
        path inputPath: AbsolutePath,
        baseURL: String,
        version: Version?,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        fileSystem: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> Manifest {

        // Inform the delegate.
        self.delegate?.willLoad(manifest: inputPath)

        // Validate that the file exists.
        guard (fileSystem ?? localFileSystem).isFile(inputPath) else {
            throw PackageModel.Package.Error.noManifest(
                baseURL: baseURL, version: version?.description)
        }

        // Get the JSON string for the manifest.
        let identity = PackageReference.computeIdentity(packageURL: baseURL)
        let jsonString = try loadJSONString(
            path: inputPath,
            toolsVersion: toolsVersion,
            packageIdentity: identity,
            fs: fileSystem,
            diagnostics: diagnostics
        )

        // Load the manifest from JSON.
        let json = try JSON(string: jsonString)
        var manifestBuilder = ManifestBuilder(
            toolsVersion: toolsVersion,
            baseURL: baseURL,
            fileSystem: fileSystem ?? localFileSystem
        )
        try manifestBuilder.build(v4: json, toolsVersion: toolsVersion)

        // Throw if we encountered any runtime errors.
        guard manifestBuilder.errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(manifestBuilder.errors)
        }

        // Ensure no dupicate target definitions are found.
        let duplicateTargetNames: [String] = manifestBuilder.targets.map({ $0.name }).spm_findDuplicates()
        if !duplicateTargetNames.isEmpty {
            throw ManifestParseError.duplicateTargetNames(duplicateTargetNames)
        }

        let manifest = Manifest(
            name: manifestBuilder.name,
            platforms: manifestBuilder.platforms,
            path: inputPath,
            url: baseURL,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            pkgConfig: manifestBuilder.pkgConfig,
            providers: manifestBuilder.providers,
            cLanguageStandard: manifestBuilder.cLanguageStandard,
            cxxLanguageStandard: manifestBuilder.cxxLanguageStandard,
            swiftLanguageVersions: manifestBuilder.swiftLanguageVersions,
            dependencies: manifestBuilder.dependencies,
            products: manifestBuilder.products,
            targets: manifestBuilder.targets
        )

        try validate(manifest, toolsVersion: toolsVersion)

        return manifest
    }

    /// Validate the provided manifest.
    private func validate(_ manifest: Manifest, toolsVersion: ToolsVersion) throws {
        try validateProducts(manifest)
        try validateDependencyURLs(manifest)

        // Checks reserved for tools version 5.2 features
        if toolsVersion >= .v5_2 {
            try validateDependencyNames(manifest)
            try validateTargetDependencyReferences(manifest)
        }
    }

    private func validateProducts(_ manifest: Manifest) throws {
        for product in manifest.products {
            // Check that the product contains targets.
            guard !product.targets.isEmpty else {
                throw ManifestParseError.emptyProductTargets(productName: product.name)
            }

            // Check that the product references existing targets.
            for target in product.targets {
                if !manifest.targetMap.keys.contains(target) {
                    throw ManifestParseError.productTargetNotFound(productName: product.name, targetName: target)
                }
            }
        }
    }

    private func validateDependencyURLs(_ manifest: Manifest) throws {
        let duplicateDependenciesByURL = manifest.dependencies
            .lazy
            .map({ KeyedPair($0, key: PackageReference.computeIdentity(packageURL: $0.url)) })
            .spm_findDuplicateElements()
        if !duplicateDependenciesByURL.isEmpty {
            let duplicates = duplicateDependenciesByURL.map({ $0.map({ $0.item }) })
            throw ManifestParseError.duplicateDependencyURLs(duplicates)
        }
    }

    /// Validates that all dependencies have different names.
    private func validateDependencyNames(_ manifest: Manifest) throws {
        let duplicateDependenciesByName = manifest.dependencies
            .lazy
            .map({ KeyedPair($0, key: $0.name!) })
            .spm_findDuplicateElements()
        if !duplicateDependenciesByName.isEmpty {
            let duplicates = duplicateDependenciesByName.map({ $0.map({ $0.item }) })
            throw ManifestParseError.duplicateDependencyNames(duplicates)
        }
    }

    /// Validates that product target dependencies reference an existing package.
    private func validateTargetDependencyReferences(_ manifest: Manifest) throws {
        for target in manifest.targets {
            for targetDependency in target.dependencies {
                // If this is a target dependency (or byName that references a target), we don't need to check.
                if case .target = targetDependency { continue }
                if case .byName(let name) = targetDependency, manifest.targetMap.keys.contains(name) { continue }

                // If we can't find the package dependency it references, the manifest is invalid.
                if manifest.packageDependency(referencedBy: targetDependency) == nil {
                    let packageName: String
                    switch targetDependency {
                    case .product(_, package: let name?),
                         .byName(let name):
                        packageName = name
                    default:
                        fatalError("Invalid case: this shouldn't be a target, or a product with no name")
                    }

                    throw ManifestParseError.unknownTargetDependencyPackage(
                        targetName: target.name,
                        packageName: packageName
                    )
                }
            }
        }
    }

    /// Load the JSON string for the given manifest.
    private func loadJSONString(
        path inputPath: AbsolutePath,
        toolsVersion: ToolsVersion,
        packageIdentity: String,
        fs: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> String {
        let result: ManifestParseResult
        let pathOrContents: ManifestPathOrContents

        if let fs = fs {
            let contents = try fs.readFileContents(inputPath).contents
            pathOrContents = .contents(contents)
        } else {
            pathOrContents = .path(inputPath)
        }

        if !self.isManifestCachingEnabled {
            // Load directly if manifest caching is not enabled.
            result = parse(
                packageIdentity: packageIdentity,
                pathOrContents: pathOrContents, toolsVersion: toolsVersion)
        } else {
            let key = ManifestLoadRule.RuleKey(
                packageIdentity: packageIdentity,
                pathOrContents: pathOrContents, toolsVersion: toolsVersion)
            result = try getEngine().build(key: key)
        }

        // Throw now if we weren't able to parse the manifest.
        guard let parsedManifest = result.parsedManifest else {
            let errors = result.errorOutput ?? result.compilerOutput ?? "<unknown>"
            throw ManifestParseError.invalidManifestFormat(errors, diagnosticFile: result.diagnosticFile)
        }

        // We should not have any fatal error at this point.
        assert(result.errorOutput == nil)

        // We might have some non-fatal output (warnings/notes) from the compiler even when
        // we were able to parse the manifest successfully.
        if let compilerOutput = result.compilerOutput {
            diagnostics?.emit(.warning(ManifestLoadingDiagnostic(output: compilerOutput, diagnosticFile: result.diagnosticFile)))
        }

        return parsedManifest
    }

    fileprivate struct ManifestParseResult: LLBuildValue {
        var hasErrors: Bool {
            return parsedManifest == nil
        }

        /// The path to the diagnostics file (.dia).
        ///
        /// This is only present if serialized diagnostics are enabled.
        var diagnosticFile: AbsolutePath?

        /// The output from compiler, if any.
        ///
        /// This would contain the errors and warnings produced when loading the manifest file.
        var compilerOutput: String?

        /// The parsed manifest in JSON format.
        var parsedManifest: String?

        /// Any non-compiler error that might have occurred during manifest loading.
        ///
        /// For e.g., we could have failed to spawn the process or create temporary file.
        var errorOutput: String? {
            didSet {
                assert(parsedManifest == nil && compilerOutput == nil)
            }
        }
    }

    /// Parse the manifest at the given path to JSON.
    fileprivate func parse(
        packageIdentity: String,
        pathOrContents: ManifestPathOrContents,
        toolsVersion: ToolsVersion
    ) -> ManifestParseResult {

        /// Helper method for parsing the manifest.
        func _parse(
            path manifestPath: AbsolutePath,
            toolsVersion: ToolsVersion,
            manifestParseResult: inout ManifestParseResult
        ) throws {
            self.delegate?.willParse(manifest: manifestPath)

            // The compiler has special meaning for files with extensions like .ll, .bc etc.
            // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
            assert(manifestPath.extension == "swift",
                   "Manifest files must contain .swift suffix in their name, given: \(manifestPath).")

            // For now, we load the manifest by having Swift interpret it directly.
            // Eventually, we should have two loading processes, one that loads only
            // the declarative package specification using the Swift compiler directly
            // and validates it.

            // Compute the path to runtime we need to load.
            let runtimePath = self.runtimePath(for: toolsVersion)
            let interpreterFlags = self.interpreterFlags(for: toolsVersion)

            // FIXME: Workaround for the module cache bug that's been haunting Swift CI
            // <rdar://problem/48443680>
            let moduleCachePath = ProcessEnv.vars["SWIFTPM_MODULECACHE_OVERRIDE"] ?? ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"]

            var cmd = [String]()
          #if os(macOS)
            // If enabled, use sandbox-exec on macOS. This provides some safety against
            // arbitrary code execution when parsing manifest files. We only allow
            // the permissions which are absolutely necessary for manifest parsing.
            if isManifestSandboxEnabled {
                let cacheDirs = [
                    cacheDir,
                    moduleCachePath.map{ AbsolutePath($0) }
                ].compactMap{$0}
                cmd += ["sandbox-exec", "-p", sandboxProfile(cacheDirs)]
            }
          #endif
            cmd += [resources.swiftCompiler.pathString]
            cmd += ["--driver-mode=swift"]
            cmd += verbosity.ccArgs
          #if Xcode
            cmd += ["-F", runtimePath.appending(component: "PackageFrameworks").pathString, "-framework", "PackageDescription"]
          #else
            cmd += ["-L", runtimePath.pathString, "-lPackageDescription"]
          #endif
            cmd += interpreterFlags
            if let moduleCachePath = moduleCachePath {
                cmd += ["-module-cache-path", moduleCachePath]
            }

            // Add the arguments for emitting serialized diagnostics, if requested.
            if serializedDiagnostics, cacheDir != nil {
                let diaDir = cacheDir.appending(component: "ManifestLoading")
                let diagnosticFile = diaDir.appending(component: packageIdentity + ".dia")
                try localFileSystem.createDirectory(diaDir, recursive: true)
                cmd += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticFile.pathString]
                manifestParseResult.diagnosticFile = diagnosticFile
            }

            cmd += [manifestPath.pathString]

            // Create and open a temporary file to write json to.
            try withTemporaryFile { file in
                // Pass the fd in arguments.
                cmd += ["-fileno", "\(file.fileHandle.fileDescriptor)"]

                // Prefer swiftinterface if both swiftmodule and swiftinterface files are present.
                //
                // This will avoid failures during incremental builds when the
                // slate swiftmodule file is still present from the previous
                // install. We should be able to remove this after some
                // transition period.
                var env = ProcessEnv.vars
              #if os(macOS)
                env["SWIFT_FORCE_MODULE_LOADING"] = "prefer-parseable"
              #endif

                // Run the command.
                let result = try Process.popen(arguments: cmd, environment: env)
                let output = try (result.utf8Output() + result.utf8stderrOutput()).spm_chuzzle()
                manifestParseResult.compilerOutput = output

                // Return now if there was an error.
                if result.exitStatus != .terminated(code: 0) {
                    return
                }

                guard let json = try localFileSystem.readFileContents(file.path).validDescription else {
                    throw StringError("the manifest has invalid encoding")
                }
                manifestParseResult.parsedManifest = json
            }
        }

        var manifestParseResult = ManifestParseResult()
        do {
            switch pathOrContents {
            case .path(let path):
                try _parse(
                    path: path,
                    toolsVersion: toolsVersion,
                    manifestParseResult: &manifestParseResult
                )
            case .contents(let contents):
                try withTemporaryFile(suffix: ".swift") { tempFile in
                  try localFileSystem.writeFileContents(tempFile.path, bytes: ByteString(contents))
                  try _parse(
                      path: tempFile.path,
                      toolsVersion: toolsVersion,
                      manifestParseResult: &manifestParseResult
                  )
                }
            }
        } catch {
            assert(manifestParseResult.parsedManifest == nil)
            manifestParseResult.errorOutput = error.localizedDescription
        }

        return manifestParseResult
    }

    /// Returns path to the sdk, if possible.
    private func sdkRoot() -> AbsolutePath? {
        if let sdkRoot = _sdkRoot {
            return sdkRoot
        }

        // Find SDKROOT on macOS using xcrun.
      #if os(macOS)
        let foundPath = try? Process.checkNonZeroExit(
            args: "xcrun", "--sdk", "macosx", "--show-sdk-path")
        guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
            return nil
        }
        _sdkRoot = AbsolutePath(sdkRoot)
      #endif

        return _sdkRoot
    }
    // Cache storage for computed sdk path.
    private var _sdkRoot: AbsolutePath? = nil

    /// Returns the interpreter flags for a manifest.
    public func interpreterFlags(
        for toolsVersion: ToolsVersion
    ) -> [String] {
        var cmd = [String]()
        let runtimePath = self.runtimePath(for: toolsVersion)
        cmd += ["-swift-version", toolsVersion.swiftLanguageVersion.rawValue]
        cmd += ["-I", runtimePath.pathString]
      #if os(macOS)
        cmd += ["-target", "x86_64-apple-macosx10.10"]
      #endif
        if let sdkRoot = resources.sdkRoot ?? self.sdkRoot() {
            cmd += ["-sdk", sdkRoot.pathString]
        }
        cmd += ["-package-description-version", toolsVersion.description]
        return cmd
    }

    /// Returns the runtime path given the manifest version and path to libDir.
    private func runtimePath(for version: ToolsVersion) -> AbsolutePath {
        // Bin dir will be set when developing swiftpm without building all of the runtimes.
        return resources.binDir ?? resources.libDir.appending(version.runtimeSubpath)
    }

    /// Returns the build engine.
    private func getEngine() throws -> LLBuildEngine {
        if let engine = _engine {
            return engine
        }

        let cacheDelegate = ManifestCacheDelegate()
        let engine = LLBuildEngine(delegate: cacheDelegate)
        cacheDelegate.loader = self

        if isManifestCachingEnabled {
            try localFileSystem.createDirectory(cacheDir, recursive: true)
            try engine.attachDB(path: cacheDir.appending(component: "manifest.db").pathString)
        }
        _engine = engine
        return engine
    }
    private var _engine: LLBuildEngine?
}

/// Returns the sandbox profile to be used when parsing manifest on macOS.
private func sandboxProfile(_ cacheDirs: [AbsolutePath] = []) -> String {
    let stream = BufferedOutputByteStream()
    stream <<< "(version 1)" <<< "\n"
    // Deny everything by default.
    stream <<< "(deny default)" <<< "\n"
    // Import the system sandbox profile.
    stream <<< "(import \"system.sb\")" <<< "\n"
    // Allow reading all files.
    stream <<< "(allow file-read*)" <<< "\n"
    // These are required by the Swift compiler.
    stream <<< "(allow process*)" <<< "\n"
    stream <<< "(allow sysctl*)" <<< "\n"
    // Allow writing in temporary locations.
    stream <<< "(allow file-write*" <<< "\n"
    for directory in Platform.darwinCacheDirectories() {
        stream <<< "    (regex #\"^\(directory.pathString)/org\\.llvm\\.clang.*\")" <<< "\n"
    }
    for cacheDir in cacheDirs {
        stream <<< "    (subpath \"\(cacheDir.pathString)\")" <<< "\n"
    }
    stream <<< ")" <<< "\n"
    return stream.bytes.description
}

// MARK:- Caching support.

final class ManifestCacheDelegate: LLBuildEngineDelegate {

    weak var loader: ManifestLoader!

    func lookupRule(rule: String, key: Key) -> Rule {
        switch rule {
        case ManifestLoadRule.ruleName:
            return ManifestLoadRule(key, loader: loader)
        case FileInfoRule.ruleName:
            return FileInfoRule(key)
        case SwiftPMVersionRule.ruleName:
            return SwiftPMVersionRule()
        case ProcessEnvRule.ruleName:
            return ProcessEnvRule()
        default:
            fatalError("Unknown rule \(rule)")
        }
    }
}

/// A rule to load a package manifest.
///
/// The rule can currently only load manifests which are physically present on
/// the local file system. The rule will re-run if the manifest is modified.
final class ManifestLoadRule: LLBuildRule {

    fileprivate struct RuleKey: LLBuildKey {
        typealias BuildValue = ManifestLoader.ManifestParseResult
        typealias BuildRule = ManifestLoadRule

        let packageIdentity: String
        let pathOrContents: ManifestPathOrContents
        let toolsVersion: ToolsVersion
    }

    override class var ruleName: String { return "\(ManifestLoadRule.self)" }

    private let key: RuleKey
    private weak var loader: ManifestLoader!

    init(_ key: Key, loader: ManifestLoader) {
        self.key = RuleKey(key)
        self.loader = loader
        super.init()
    }

    override func start(_ engine: LLTaskBuildEngine) {
        // FIXME: Ideally, we should expose an API in the manifest file to track individual
        // environment variables instead of blindly invalidating when *anything* changes.
        engine.taskNeedsInput(ProcessEnvRule.RuleKey(), inputID: 1)

        engine.taskNeedsInput(SwiftPMVersionRule.RuleKey(), inputID: 2)
        if case .path(let path) = key.pathOrContents {
            engine.taskNeedsInput(FileInfoRule.RuleKey(path: path), inputID: 3)
        }
    }

    override func isResultValid(_ priorValue: Value) -> Bool {
        // Always rebuild if we had a failure.
        let value = RuleKey.BuildValue(priorValue)
        if value.hasErrors { return false }

        return super.isResultValid(priorValue)
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        let value = loader.parse(
            packageIdentity: key.packageIdentity,
            pathOrContents: key.pathOrContents, toolsVersion: key.toolsVersion)
        engine.taskIsComplete(value)
    }
}

// FIXME: Find a proper place for this rule.
/// A rule to compute the current process environment.
///
/// This rule will always run.
final class ProcessEnvRule: LLBuildRule {

    struct RuleKey: LLBuildKey {
        typealias BuildValue = RuleValue
        typealias BuildRule = ProcessEnvRule
    }

    struct RuleValue: LLBuildValue, Equatable {
        let env: [String: String]
    }

    override class var ruleName: String { return "\(ProcessEnvRule.self)" }

    override func isResultValid(_ priorValue: Value) -> Bool {
        // Always rebuild this rule.
        return false
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        let env = ProcessInfo.processInfo.environment
        engine.taskIsComplete(RuleValue(env: env))
    }
}

// FIXME: Find a proper place for this rule.
/// A rule to get file info of a file on disk.
final class FileInfoRule: LLBuildRule {

    struct RuleKey: LLBuildKey {
        typealias BuildValue = RuleValue
        typealias BuildRule = FileInfoRule

        let path: AbsolutePath
    }

    typealias RuleValue = CodableResult<TSCBasic.FileInfo, StringError>

    override class var ruleName: String { return "\(FileInfoRule.self)" }

    private let key: RuleKey

    init(_ key: Key) {
        self.key = RuleKey(key)
        super.init()
    }

    override func isResultValid(_ priorValue: Value) -> Bool {
        let priorValue = RuleValue(priorValue)

        // Always rebuild if we had a failure.
        if case .failure = priorValue.result {
            return false
        }
        return getFileInfo(key.path).result == priorValue.result
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        engine.taskIsComplete(getFileInfo(key.path))
    }

    private func getFileInfo(_ path: AbsolutePath) -> RuleValue {
        return RuleValue(body: {
            try localFileSystem.getFileInfo(key.path)
        })
    }
}

// FIXME: Find a proper place for this rule.
/// A rule to compute the current version of the pacakge manager.
///
/// This rule will always run.
final class SwiftPMVersionRule: LLBuildRule {

    struct RuleKey: LLBuildKey {
        typealias BuildValue = RuleValue
        typealias BuildRule = SwiftPMVersionRule
    }

    struct RuleValue: LLBuildValue, Equatable {
        let version: String
    }

    override class var ruleName: String { return "\(SwiftPMVersionRule.self)" }

    override func isResultValid(_ priorValue: Value) -> Bool {
        // Always rebuild this rule.
        return false
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        // FIXME: We need to include git hash in the version
        // string to make this rule more correct.
        let version = Versioning.currentVersion.displayString
        engine.taskIsComplete(RuleValue(version: version))
    }
}

/// Enum to represent either the manifest path or its content.
private enum ManifestPathOrContents {
    case path(AbsolutePath)
    case contents([UInt8])
}

extension ManifestPathOrContents: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case contents
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .path:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(AbsolutePath.self)
            self = .path(a1)
        case .contents:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode([UInt8].self)
            self = .contents(a1)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .path(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .path)
            try unkeyedContainer.encode(a1)
        case let .contents(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .contents)
            try unkeyedContainer.encode(a1)
        }
    }
}

extension CodableResult: LLBuildValue { }
