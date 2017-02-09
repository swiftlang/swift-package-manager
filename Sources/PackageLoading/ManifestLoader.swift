/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageDescription
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
    var swiftCompilerPath: AbsolutePath { get }

    /// The path of the library resources.
    var libraryPath: AbsolutePath { get }
}

/// Protocol for the manifest loader interface.
public protocol ManifestLoaderProtocol {
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    func load(packagePath path: AbsolutePath, baseURL: String, version: Version?, fileSystem: FileSystem?) throws -> Manifest
}

extension ManifestLoaderProtocol {
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    public func load(packagePath path: AbsolutePath, baseURL: String, version: Version?) throws -> Manifest {
        return try load(packagePath: path, baseURL: baseURL, version: version, fileSystem: nil)
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

    public func load(packagePath path: AbsolutePath, baseURL: String, version: Version?, fileSystem: FileSystem? = nil) throws -> Manifest {
        // As per our versioning support, determine the appropriate manifest version to load.
        for versionSpecificKey in Versioning.currentVersionSpecificKeys { 
            let versionSpecificPath = path.appending(component: Manifest.basename + versionSpecificKey + ".swift")
            if (fileSystem ?? localFileSystem).exists(versionSpecificPath) {
                return try loadFile(path: versionSpecificPath, baseURL: baseURL, version: version, fileSystem: fileSystem)
            }
        }
        
        return try loadFile(path: path.appending(component: Manifest.filename), baseURL: baseURL, version: version, fileSystem: fileSystem)
    }

    /// Create a manifest by loading a specific manifest file from the given `path`.
    ///
    /// - Parameters:
    ///   - path: The path to the manifest file (or a package root).
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    func loadFile(path inputPath: AbsolutePath, baseURL: String, version: Version?, fileSystem: FileSystem? = nil) throws -> Manifest {
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
            return try loadFile(path: tmpFile.path, baseURL: baseURL, version: version)
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

        // Load the manifest description.
        guard let jsonString = try parse(path: path) else {
            throw ManifestParseError.emptyManifestFile
        }
        let json = try JSON(string: jsonString)
        let package = PackageDescription.Package.fromJSON(json, baseURL: baseURL)
        let products = PackageDescription.Product.fromJSON(json)
        let errors = parseErrors(json)

        guard errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(errors)
        }

        return Manifest(path: path, url: baseURL, package: package, legacyProducts: products, version: version)
    }

    /// Parse the manifest at the given path to JSON.
    private func parse(path manifestPath: AbsolutePath) throws -> String? {
        // The compiler has special meaning for files with extensions like .ll, .bc etc.
        // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
        assert(manifestPath.extension == "swift", "Manifest files must contain .swift suffix in their name, given: \(manifestPath.asString).")

        // For now, we load the manifest by having Swift interpret it directly.
        // Eventually, we should have two loading processes, one that loads only the
        // the declarative package specification using the Swift compiler directly
        // and validates it.
    
        var cmd = [resources.swiftCompilerPath.asString]
        cmd += ["--driver-mode=swift"]
        cmd += verbosity.ccArgs
        cmd += ["-I", resources.libraryPath.asString]
    
        // When running from Xcode, load PackageDescription.framework
        // else load the dylib version of it
    #if Xcode
        cmd += ["-F", resources.libraryPath.asString]
        cmd += ["-framework", "PackageDescription"]
    #else
        cmd += ["-L", resources.libraryPath.asString, "-lPackageDescription"] 
    #endif
    
    #if os(macOS)
        cmd += ["-target", "x86_64-apple-macosx10.10"]
    #endif
        cmd += [manifestPath.asString]

        // Create and open a temporary file to write json to.
        let file = try TemporaryFile()
        // Pass the fd in arguments.
        cmd += ["-fileno", "\(file.fileHandle.fileDescriptor)"]

        // FIXME: Move this to the new Process class once we have that.
        var output = ""
        do {
            try popen(cmd, redirectStandardError: true) { output += $0 }
        } catch {
            output += String(describing: error)
        }
        // We expect output from interpreter to be empty, if something was emitted
        // throw and report it.
        guard output.isEmpty else {
            throw ManifestParseError.invalidManifestFormat(output)
        }
    
        guard let json = try localFileSystem.readFileContents(file.path).asString else {
            throw ManifestParseError.invalidEncoding
        }
    
        return json.isEmpty ? nil : json
    }
}

// MARK: JSON Deserialization

// We separate this out from the raw PackageDescription module, so that the code
// we need to load to interpret the `Package.swift` manifests is as minimal as
// possible.
//
// FIXME: These APIs are `internal` so they can be unit tested, but otherwise
// could be private.

extension PackageDescription.Package {
    static func fromJSON(_ json: JSON, baseURL: String? = nil) -> PackageDescription.Package {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
        guard case .dictionary(let package)? = topLevelDict["package"] else { fatalError("missing package") }

        guard case .string(let name)? = package["name"] else { fatalError("missing 'name'") }

        var pkgConfig: String? = nil
        if case .string(let value)? = package["pkgConfig"] {
            pkgConfig = value
        }

        // Parse the targets.
        var targets: [PackageDescription.Target] = []
        if case .array(let array)? = package["targets"] {
            targets = array.map(PackageDescription.Target.fromJSON)
        }

        var providers: [PackageDescription.SystemPackageProvider]? = nil
        if case .array(let array)? = package["providers"] {
            providers = array.map(PackageDescription.SystemPackageProvider.fromJSON)
        }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Package.Dependency] = []
        if case .array(let array)? = package["dependencies"] {
            dependencies = array.map { PackageDescription.Package.Dependency.fromJSON($0, baseURL: baseURL) }
        }

        // Parse the exclude folders.
        var exclude: [String] = []
        if case .array(let array)? = package["exclude"] {
            exclude = array.map { element in
                guard case .string(let excludeString) = element else { fatalError("exclude contains non string element") }
                return excludeString
            }
        }

        return PackageDescription.Package(name: name, pkgConfig: pkgConfig, providers: providers, targets: targets, dependencies: dependencies, exclude: exclude)
    }
}

extension PackageDescription.Package.Dependency {
    static func fromJSON(_ json: JSON, baseURL: String?) -> PackageDescription.Package.Dependency {
        guard case .dictionary(let dict) = json else { fatalError("Unexpected item") }

        guard case .string(let url)? = dict["url"],
              case .dictionary(let versionDict)? = dict["version"],
              case .string(let vv1)? = versionDict["lowerBound"],
              case .string(let vv2)? = versionDict["upperBound"],
              let v1 = Version(vv1), let v2 = Version(vv2)
        else {
            fatalError("Unexpected item")
        }

        func fixURL() -> String {
            if let baseURL = baseURL, URL.scheme(url) == nil {
                // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
                return AbsolutePath(url, relativeTo: AbsolutePath(baseURL)).asString
            } else {
                return url
            }
        }

        return PackageDescription.Package.Dependency.Package(url: fixURL(), versions: v1..<v2)
    }
}

extension PackageDescription.SystemPackageProvider {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription.SystemPackageProvider {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing name") }
        guard case .string(let value)? = dict["value"] else { fatalError("missing value") }
        switch name {
        case "Brew":
            return .Brew(value)
        case "Apt":
            return .Apt(value)
        default:
            fatalError("unexpected string")
        }
    }
}

extension PackageDescription.Target {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription.Target {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing name") }

        var dependencies: [PackageDescription.Target.Dependency] = []
        if case .array(let array)? = dict["dependencies"] {
            dependencies = array.map(PackageDescription.Target.Dependency.fromJSON)
        }

        return PackageDescription.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription.Target.Dependency {
    fileprivate static func fromJSON(_ item: JSON) -> PackageDescription.Target.Dependency {
        guard case .string(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}

extension PackageDescription.Product {

    fileprivate static func fromJSON(_ json: JSON) -> [PackageDescription.Product] {
        guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
        guard case .array(let array)? = topLevelDict["products"] else { fatalError("unexpected item") }
        return array.map(Product.init)
    }

    private init(_ json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing item") }
        guard case .string(let productType)? = dict["type"] else { fatalError("missing item") }
        guard case .array(let targetsJSON)? = dict["modules"] else { fatalError("missing item") }

        let targets: [String] = targetsJSON.map {
            guard case JSON.string(let string) = $0 else { fatalError("invalid item") }
            return string
        }
        self.init(name: name, type: ProductType(productType), modules: targets)
    }
}

extension PackageDescription.ProductType {
    fileprivate init(_ string: String) {
        switch string {
        case "exe":
            self = .Executable		
        case "a":
            self = .Library(.Static)
        case "dylib":
            self = .Library(.Dynamic)
        case "test":
            self = .Test
        default:
            fatalError("invalid string \(string)")
        }
    }
}

func parseErrors(_ json: JSON) -> [String] {
    guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
    guard case .array(let errors)? = topLevelDict["errors"] else { fatalError("missing errors") }
    return errors.map { error in
        guard case .string(let string) = error else { fatalError("unexpected item") }
        return string
    }
}
