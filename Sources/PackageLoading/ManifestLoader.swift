/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility
import SPMLLBuild
import struct POSIX.FileInfo
public typealias FileSystem = Basic.FileSystem

public enum ManifestParseError: Swift.Error {
    /// The manifest contains invalid format.
    case invalidManifestFormat(String)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])

    case duplicateDependencyDecl([[PackageDependencyDescription]])
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
}

/// Default implemention for the resource provider.
public extension ManifestResourceProvider {

    var sdkRoot: AbsolutePath? {
        return nil
    }
}

extension ToolsVersion {
    /// Returns the manifest version for this tools version.
    public var manifestVersion: ManifestVersion {
        // FIXME: This works for now but we may want to do something better here
        // if we're going to have a lot of manifest versions. We can make
        // ManifestVersion a proper version type and then automatically
        // determine the best version from the available versions.
        //
        // If the tools version is less than 4.2, return manifest version 4.
        if major == 4 && minor < 2 {
            return .v4
        }

        // Return 4.2 otherwise.
        return .v4_2
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
    ///   - manifestVersion: The version of manifest to load.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        manifestVersion: ManifestVersion,
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
    ///   - fileSystem: The file system to load from.
    public func load(
        package path: AbsolutePath,
        baseURL: String,
        version: Version? = nil,
        manifestVersion: ManifestVersion,
        fileSystem: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> Manifest {
        return try load(
            packagePath: path,
            baseURL: baseURL,
            version: version,
            manifestVersion: manifestVersion,
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
    let isManifestSandboxEnabled: Bool
    let isManifestCachingEnabled: Bool
    let cacheDir: AbsolutePath
    let delegate: ManifestLoaderDelegate?

    public init(
        resources: ManifestResourceProvider,
        isManifestSandboxEnabled: Bool = true,
        isManifestCachingEnabled: Bool = true,
        cacheDir: AbsolutePath = determineTempDirectory(),
        delegate: ManifestLoaderDelegate? = nil
    ) {
        self.resources = resources
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
        self.isManifestCachingEnabled = isManifestCachingEnabled
        self.delegate = delegate
        self.cacheDir = cacheDir
    }

    @available(*, deprecated)
    public convenience init(
        resources: ManifestResourceProvider,
        isManifestSandboxEnabled: Bool = true
    ) {
        self.init(
            resources: resources,
            isManifestSandboxEnabled: isManifestSandboxEnabled,
            isManifestCachingEnabled: false,
            cacheDir: determineTempDirectory()
       )
    }

    public func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        manifestVersion: ManifestVersion,
        fileSystem: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> Manifest {
        return try loadFile(
            path: Manifest.path(atPackagePath: path, fileSystem: fileSystem ?? localFileSystem),
            baseURL: baseURL,
            version: version,
            manifestVersion: manifestVersion,
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
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    func loadFile(
        path inputPath: AbsolutePath,
        baseURL: String,
        version: Version?,
        manifestVersion: ManifestVersion,
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
        let jsonString: String
        do {
            jsonString = try loadJSONString(
                path: inputPath, manifestVersion: manifestVersion,
                fs: fileSystem, diagnostics: diagnostics)
        } catch let error as StringError {
            throw ManifestParseError.invalidManifestFormat(error.description)
        }

        // Load the manifest from JSON.
        let json = try JSON(string: jsonString)
        let manifestBuilder = try ManifestBuilder(v4: json, baseURL: baseURL)

        // Throw if we encountered any runtime errors.
        guard manifestBuilder.errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(manifestBuilder.errors)
        }

        let manifest = Manifest(
            name: manifestBuilder.name,
            path: inputPath,
            url: baseURL,
            version: version,
            manifestVersion: manifestVersion,
            pkgConfig: manifestBuilder.pkgConfig,
            providers: manifestBuilder.providers,
            cLanguageStandard: manifestBuilder.cLanguageStandard,
            cxxLanguageStandard: manifestBuilder.cxxLanguageStandard,
            swiftLanguageVersions: manifestBuilder.swiftLanguageVersions,
            dependencies: manifestBuilder.dependencies,
            products: manifestBuilder.products,
            targets: manifestBuilder.targets
        )

        try validate(manifest)

        return manifest
    }

    /// Validate the provided manifest.
    private func validate(_ manifest: Manifest) throws {
        let duplicateDecls = manifest.dependencies.map({ KeyedPair($0, key: PackageReference.computeIdentity(packageURL: $0.url)) }).findDuplicateElements()
        if !duplicateDecls.isEmpty {
            throw ManifestParseError.duplicateDependencyDecl(duplicateDecls.map({ $0.map({ $0.item }) }))
        }
    }

    /// Load the JSON string for the given manifest.
    func loadJSONString(
        path inputPath: AbsolutePath,
        manifestVersion: ManifestVersion,
        fs: FileSystem? = nil,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> String {
        // If we were given a filesystem, load via a temporary file.
        if let fs = fs {
            let contents = try fs.readFileContents(inputPath)
            let tmpFile = try TemporaryFile(suffix: ".swift")
            try localFileSystem.writeFileContents(tmpFile.path, bytes: contents)
            return try parse(path: tmpFile.path, manifestVersion: manifestVersion, diagnostics: diagnostics)
        }

        // Load directly if manifest caching is not enabled.
        if !self.isManifestCachingEnabled {
            return try parse(path: inputPath, manifestVersion: manifestVersion, diagnostics: diagnostics)
        }

        // Otherwise load via llbuild.
        let key = ManifestLoadRule.RuleKey(
            path: inputPath, manifestVersion: manifestVersion)
        let value = try getEngine().build(key: key)

        return try value.dematerialize()
    }

    /// Parse the manifest at the given path to JSON.
    func parse(
        path manifestPath: AbsolutePath,
        manifestVersion: ManifestVersion,
        diagnostics: DiagnosticsEngine? = nil
    ) throws -> String {
        self.delegate?.willParse(manifest: manifestPath)

        // The compiler has special meaning for files with extensions like .ll, .bc etc.
        // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
        assert(manifestPath.extension == "swift",
               "Manifest files must contain .swift suffix in their name, given: \(manifestPath.asString).")

        // For now, we load the manifest by having Swift interpret it directly.
        // Eventually, we should have two loading processes, one that loads only
        // the declarative package specification using the Swift compiler directly
        // and validates it.

        // Compute the path to runtime we need to load.
        let runtimePath = self.runtimePath(for: manifestVersion).asString
        let interpreterFlags = self.interpreterFlags(for: manifestVersion)

        var cmd = [String]()
      #if os(macOS)
        // If enabled, use sandbox-exec on macOS. This provides some safety against
        // arbitrary code execution when parsing manifest files. We only allow
        // the permissions which are absolutely necessary for manifest parsing.
        if isManifestSandboxEnabled {
            cmd += ["sandbox-exec", "-p", sandboxProfile()]
        }
      #endif
        cmd += [resources.swiftCompiler.asString]
        cmd += ["--driver-mode=swift"]
        cmd += verbosity.ccArgs
        cmd += ["-L", runtimePath, "-lPackageDescription"]
        cmd += interpreterFlags
        cmd += [manifestPath.asString]

        // Create and open a temporary file to write json to.
        let file = try TemporaryFile()
        // Pass the fd in arguments.
        cmd += ["-fileno", "\(file.fileHandle.fileDescriptor)"]

        // Run the command.
        let result = try Process.popen(arguments: cmd)
        let output = try (result.utf8Output() + result.utf8stderrOutput()).chuzzle()

        // Throw an error if there was a non-zero exit or emit the output
        // produced by the process. A process output will usually mean there
        // was a warning emitted by the Swift compiler.
        if result.exitStatus != .terminated(code: 0) {
            throw StringError(output ?? "<unknown>")
        } else if let output = output {
            diagnostics?.emit(data: ManifestLoadingDiagnostic(output: output))
        }

        guard let json = try localFileSystem.readFileContents(file.path).asString else {
            throw StringError("the manifest has invalid encoding")
        }

        return json
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
        guard let sdkRoot = foundPath?.chomp(), !sdkRoot.isEmpty else {
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
        for manifestVersion: ManifestVersion
    ) -> [String] {
        var cmd = [String]()
        let runtimePath = self.runtimePath(for: manifestVersion)
        cmd += ["-swift-version", manifestVersion.swiftLanguageVersion.rawValue]
        cmd += ["-I", runtimePath.asString]
      #if os(macOS)
        cmd += ["-target", "x86_64-apple-macosx10.10"]
      #endif
        if let sdkRoot = resources.sdkRoot ?? self.sdkRoot() {
            cmd += ["-sdk", sdkRoot.asString]
        }
        return cmd
    }

    /// Returns the runtime path given the manifest version and path to libDir.
    private func runtimePath(for version: ManifestVersion) -> AbsolutePath {
        return resources.libDir.appending(component: version.rawValue)
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
            try engine.attachDB(path: cacheDir.appending(component: "manifest.db").asString)
        }
        _engine = engine
        return engine
    }
    private var _engine: LLBuildEngine?
}

/// Returns the sandbox profile to be used when parsing manifest on macOS.
private func sandboxProfile() -> String {
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
        stream <<< "    (regex #\"^\(directory.asString)/org\\.llvm\\.clang.*\")" <<< "\n"
    }
    stream <<< ")" <<< "\n"
    return stream.bytes.asString!
}

/// Represents a string error.
// FIXME: We should probably just remove this and make all Manifest errors Codable.
struct StringError: Equatable, Codable, CustomStringConvertible, Error {

    /// The description of the error.
    public let description: String

    /// Create an instance of StringError.
    public init(_ description: String) {
        self.description = description
    }
}

extension Result where ErrorType == StringError {
    /// Create an instance of Result<Value, StringError>.
    ///
    /// Errors will be encoded as StringError using their description.
    init(string body: () throws -> Value) {
        do {
            self = .success(try body())
        } catch let error as StringError {
            self = .failure(error)
        } catch {
            self = .failure(StringError(String(describing: error)))
        }
    }
}

// MARK:- Caching support.

extension Result: LLBuildValue where Value: Codable, ErrorType: Codable {}

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

    struct RuleKey: LLBuildKey {
        typealias BuildValue = RuleValue
        typealias BuildRule = ManifestLoadRule

        let path: AbsolutePath
        let manifestVersion: ManifestVersion
    }

    typealias RuleValue = Result<String, StringError>

    override class var ruleName: String { return "\(ManifestLoadRule.self)" }

    private let key: RuleKey
    private weak var loader: ManifestLoader!

    init(_ key: Key, loader: ManifestLoader) {
        self.key = RuleKey(key)
        self.loader = loader
        super.init()
    }

    override func start(_ engine: LLTaskBuildEngine) {
        engine.taskNeedsInput(SwiftPMVersionRule.RuleKey(), inputID: 1)
        engine.taskNeedsInput(FileInfoRule.RuleKey(path: key.path), inputID: 2)
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        let value = RuleValue(string: {
            try loader.parse(path: key.path, manifestVersion: key.manifestVersion)
        })
        engine.taskIsComplete(value)
    }
}

/// A rule to get file info of a file on disk.
// FIXME: Find a proper place for this rule.
final class FileInfoRule: LLBuildRule {

    struct RuleKey: LLBuildKey {
        typealias BuildValue = RuleValue
        typealias BuildRule = FileInfoRule

        let path: AbsolutePath
    }

    typealias RuleValue = Result<FileInfo, StringError>

    override class var ruleName: String { return "\(FileInfoRule.self)" }

    private let key: RuleKey

    init(_ key: Key) {
        self.key = RuleKey(key)
        super.init()
    }

    override func isResultValid(_ priorValue: Value) -> Bool {
        let priorValue = RuleValue(priorValue)

        // Always rebuild if we had a failure.
        if case .failure = priorValue {
            return false
        }
        return getFileInfo(key.path) == priorValue
    }

    override func inputsAvailable(_ engine: LLTaskBuildEngine) {
        engine.taskIsComplete(getFileInfo(key.path))
    }

    private func getFileInfo(_ path: AbsolutePath) -> RuleValue {
        return RuleValue(string: {
            try localFileSystem.getFileInfo(key.path)
        })
    }
}

/// A rule to compute the current version of the pacakge manager.
///
/// This rule will always run.
// FIXME: Find a proper place for this rule.
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
