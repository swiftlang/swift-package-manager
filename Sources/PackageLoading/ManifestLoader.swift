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
    case emptyManifestFile

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

    /// The path to the directory containing sandbox profile.
    var sandboxProfileDir: AbsolutePath { get }
}

/// The supported manifest versions.
public enum ManifestVersion: Int {
    case three = 3
    case four
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
        return try load(packagePath: path, baseURL: baseURL, version: version, manifestVersion: manifestVersion, fileSystem: fileSystem)
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

    public init(resources: ManifestResourceProvider) {
        self.resources = resources
    }

    public func load(
        packagePath path: AbsolutePath,
        baseURL: String,
        version: Version?,
        manifestVersion: ManifestVersion,
        fileSystem: FileSystem? = nil
    ) throws -> Manifest {
        // As per our versioning support, determine the appropriate manifest version to load.
        for versionSpecificKey in Versioning.currentVersionSpecificKeys { 
            let versionSpecificPath = path.appending(component: Manifest.basename + versionSpecificKey + ".swift")
            if (fileSystem ?? localFileSystem).exists(versionSpecificPath) {
                return try loadFile(path: versionSpecificPath, baseURL: baseURL, version: version, manifestVersion: manifestVersion, fileSystem: fileSystem)
            }
        }
        
        return try loadFile(
            path: path.appending(component: Manifest.filename), baseURL: baseURL, version: version, manifestVersion: manifestVersion, fileSystem: fileSystem)
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
            return try loadFile(path: tmpFile.path, baseURL: baseURL, version: version, manifestVersion: manifestVersion)
        }

        guard baseURL.chuzzle() != nil else { fatalError() }  //TODO

        // Attempt to canonicalize the URL.
        //
        // This is important when the baseURL is a file system path, so that the
        // URLs embedded into the manifest are canonical.
        //
        // FIXME: We really shouldn't be handling this here and in this fashion.
        var baseURL = baseURL
        if URL.scheme(baseURL) == nil {
            if let resolved = try? realpath(baseURL) {
                baseURL = resolved
            }
        }

        // Compute the actual input file path.
        let path: AbsolutePath = isDirectory(inputPath) ? inputPath.appending(component: Manifest.filename) : inputPath

        // Validate that the file exists.
        guard isFile(path) else { throw PackageModel.Package.Error.noManifest(baseURL: baseURL, version: version?.description) }

        // Get the json from manifest.
        guard let jsonString = try parse(path: path, manifestVersion: manifestVersion) else {
            throw ManifestParseError.emptyManifestFile
        }
        let json = try JSON(string: jsonString)

        // Load the correct version from JSON.
        switch manifestVersion {
        case .three:
            let pd = try loadPackageDescription(json, baseURL: baseURL)
            return Manifest(path: path, url: baseURL, package: .v3(pd.package), legacyProducts: pd.products, version: version)

        case .four:
            let package = try loadPackageDescription4(json, baseURL: baseURL)
            return Manifest(path: path, url: baseURL, package: .v4(package), version: version)
        }
    }

    /// Parse the manifest at the given path to JSON.
    private func parse(path manifestPath: AbsolutePath, manifestVersion: ManifestVersion) throws -> String? {
        // The compiler has special meaning for files with extensions like .ll, .bc etc.
        // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
        assert(manifestPath.extension == "swift", "Manifest files must contain .swift suffix in their name, given: \(manifestPath.asString).")

        // For now, we load the manifest by having Swift interpret it directly.
        // Eventually, we should have two loading processes, one that loads only the
        // the declarative package specification using the Swift compiler directly
        // and validates it.

        // Compute the path to runtime we need to load.
        let runtimePath = resources.libDir.appending(component: String(manifestVersion.rawValue)).asString

        var cmd = [String]()
      #if os(macOS)
        // Use sandbox-exec on macOS. This provides some safety against
        // arbitrary code execution when parsing manifest files. We only allow
        // the permissions which are absolutely necessary for manifest parsing.
        cmd += ["sandbox-exec", "-p", sandboxProfile()]
      #endif
        cmd += [resources.swiftCompiler.asString]
        cmd += ["--driver-mode=swift"]
        cmd += verbosity.ccArgs
        cmd += ["-I", runtimePath]
        cmd += ["-L", runtimePath, "-lPackageDescription"] 
    
    #if os(macOS)
        cmd += ["-target", "x86_64-apple-macosx10.10"]
    #endif
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
    
        return json.isEmpty ? nil : json
    }
}

/// Returns the sandbox profile to be used when parsing manifest on macOS.
private func sandboxProfile() -> String {
    let stream = BufferedOutputByteStream()
    stream <<< "(version 1)" <<< "\n"
    // Deny everything by default.
    stream <<< "(deny default)" <<< "\n"
    // Allow reading all files.
    stream <<< "(allow file-read*)" <<< "\n"
    // These are required by the Swift compiler.
    stream <<< "(allow process*)" <<< "\n"
    stream <<< "(allow sysctl*)" <<< "\n"
    stream <<< "(allow mach*)" <<< "\n"
    stream <<< "(allow signal)" <<< "\n"
    // Allow writing in temporary locations.
    stream <<< "(allow file-write*" <<< "\n"
    stream <<< "    (subpath \"/private/var\")" <<< "\n"
    stream <<< ")" <<< "\n"
    return stream.bytes.asString!
}
