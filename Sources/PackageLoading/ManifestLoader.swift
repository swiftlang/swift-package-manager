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

import func POSIX.realpath

public enum ManifestParseError: Swift.Error {
    /// The manifest file is empty.
    case emptyManifestFile(url: String, version: String?)

    /// The manifest had a string encoding error.
    case invalidEncoding

    /// The manifest contains invalid format.
    case invalidManifestFormat(String)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])
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
        return major == 3 ? .three : .four
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
        fileSystem: FileSystem?
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
        fileSystem: FileSystem? = nil
    ) throws -> Manifest {
        return try load(
            packagePath: path,
            baseURL: baseURL,
            version: version,
            manifestVersion: manifestVersion,
            fileSystem: fileSystem)
    }
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

    public init(
        resources: ManifestResourceProvider,
        isManifestSandboxEnabled: Bool = true
    ) {
        self.resources = resources
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
    }

    public func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        manifestVersion: ManifestVersion,
        fileSystem: FileSystem? = nil
    ) throws -> Manifest {
        return try loadFile(
            path: Manifest.path(atPackagePath: path, fileSystem: fileSystem ?? localFileSystem),
            baseURL: baseURL,
            version: version,
            manifestVersion: manifestVersion,
            fileSystem: fileSystem)
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
        manifestVersion: ManifestVersion = .three,
        fileSystem: FileSystem? = nil
    ) throws -> Manifest {
        // If we were given a file system, load via a temporary file.
        if let fileSystem = fileSystem {
            let contents: ByteString
            do {
                contents = try fileSystem.readFileContents(inputPath)
            } catch FileSystemError.noEntry {
                throw PackageModel.Package.Error.noManifest(baseURL: baseURL, version: version?.description)
            }
            let tmpFile = try TemporaryFile(suffix: ".swift")
            try localFileSystem.writeFileContents(tmpFile.path, bytes: contents)
            return try loadFile(
                path: tmpFile.path,
                baseURL: baseURL,
                version: version,
                manifestVersion: manifestVersion)
        }

        guard baseURL.chuzzle() != nil else { fatalError() }  //TODO

        // Validate that the file exists.
        guard isFile(inputPath) else {
            throw PackageModel.Package.Error.noManifest(baseURL: baseURL, version: version?.description)
        }

        let parseResult = try parse(path: inputPath, manifestVersion: manifestVersion)

        // Get the json from manifest.
        guard let jsonString = parseResult.jsonString else {
            // FIXME: This only supports version right now, we need support for
            // branch and revision too.
            throw ManifestParseError.emptyManifestFile(url: baseURL, version: version?.description) 
        }
        let json = try JSON(string: jsonString)

        // The loaded manifest object.
        let manifest: Manifest

        // Load the correct version from JSON.
        switch manifestVersion {
        case .three:
            let pd = try loadPackageDescription(json, baseURL: baseURL)
            manifest = Manifest(
                path: inputPath,
                url: baseURL,
                package: .v3(pd.package),
                legacyProducts: pd.products,
                version: version,
                interpreterFlags: parseResult.interpreterFlags)

        case .four:
            let package = try loadPackageDescription4(json, baseURL: baseURL)
            manifest = Manifest(
                path: inputPath,
                url: baseURL,
                package: .v4(package),
                version: version,
                interpreterFlags: parseResult.interpreterFlags)
        }

        return manifest
    }

    /// Parse the manifest at the given path to JSON.
    private func parse(
        path manifestPath: AbsolutePath,
        manifestVersion: ManifestVersion
    ) throws -> (jsonString: String?, interpreterFlags: [String]) {
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
        cmd += ["-L", runtimePath, "-lPackageDescription", "-suppress-warnings"]
        cmd += interpreterFlags
        cmd += [manifestPath.asString]

        // Create and open a temporary file to write json to.
        let file = try TemporaryFile()
        // Pass the fd in arguments.
        cmd += ["-fileno", "\(file.fileHandle.fileDescriptor)"]

        // Run the command.
        let result = try Process.popen(arguments: cmd)
        let output = try (result.utf8Output() + result.utf8stderrOutput()).chuzzle()

        // We expect output from interpreter to be empty, if something was emitted
        // throw and report it.
        if let output = output {
            throw ManifestParseError.invalidManifestFormat(output)
        }

        guard let json = try localFileSystem.readFileContents(file.path).asString else {
            throw ManifestParseError.invalidEncoding
        }

        return (json.isEmpty ? nil : json, interpreterFlags)
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
        cmd += ["-swift-version", String(manifestVersion.rawValue)]
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
        return resources.libDir.appending(component: String(version.rawValue))
    }
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
