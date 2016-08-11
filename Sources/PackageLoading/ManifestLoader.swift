/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageDescription
import PackageModel
import Utility

import func POSIX.realpath

private enum ManifestParseError: Swift.Error {
    /// The manifest file is empty.
    case emptyManifestFile
    /// The manifest had a string encoding error.
    case invalidEncoding
    /// The manifest contains invalid format.
    case invalidManifestFormat
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

/// Utility class for loading manifest files.
///
/// This class is responsible for reading the manifest data and produce a
/// properly formed `PackageModel.Manifest` object. It currently does so by
/// interpreting the manifest source using Swift -- that produces a TOML
/// serialized form of the manifest (as implemented by `PackageDescription`'s
/// `atexit()` handler) which is then deserialized and loaded.
public final class ManifestLoader {
    let resources: ManifestResourceProvider

    public init(resources: ManifestResourceProvider) {
        self.resources = resources
    }

    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    public func load(packagePath: AbsolutePath, baseURL: String, version: Version?, fileSystem: FileSystem? = nil) throws -> Manifest {
        // As per our versioning support, determine the appropriate manifest version to load.
        for versionSpecificKey in Versioning.currentVersionSpecificKeys { 
            let versionSpecificPath = packagePath.appending(component: Manifest.basename + versionSpecificKey + ".swift")
            if (fileSystem ?? localFileSystem).exists(versionSpecificPath) {
                return try loadFile(path: versionSpecificPath, baseURL: baseURL, version: version, fileSystem: fileSystem)
            }
        }
        
        return try loadFile(path: packagePath.appending(component: Manifest.filename), baseURL: baseURL, version: version, fileSystem: fileSystem)
    }

    /// Create a manifest by loading a specific manifest file from the given `path`.
    ///
    /// - Parameters:
    ///   - path: The path to the manifest file (or a package root).
    ///   - baseURL: The URL the manifest was loaded from.
    ///   - version: The version the manifest is from, if known.
    ///   - fileSystem: If given, the file system to load from (otherwise load from the local file system).
    //
    // FIXME: We should stop exposing this publicly, from a public perspective
    // we should only ever load complete repositories.
    public func loadFile(path inputPath: AbsolutePath, baseURL: String, version: Version?, fileSystem: FileSystem? = nil) throws -> Manifest {
        // If we were given a file system, load via a temporary file.
        if let fileSystem = fileSystem {
            let tmpFile = try TemporaryFile()
            let contents = try fileSystem.readFileContents(inputPath)
            try localFileSystem.writeFileContents(tmpFile.path, bytes: contents)
            return try loadFile(path: tmpFile.path, baseURL: baseURL, version: version)
        }

        guard baseURL.chuzzle() != nil else { fatalError() }  //TODO

        // Canonicalize the URL.
        //
        // This is important when the baseURL is a file system path, so that the
        // URLs embedded into the manifest are canonical.
        //
        // FIXME: We really shouldn't be handling this here and in this fashion.
        var baseURL = baseURL
        if URL.scheme(baseURL) == nil {
            baseURL = try realpath(baseURL)
        }

        // Compute the actual input file path.
        let path: AbsolutePath = isDirectory(inputPath) ? inputPath.appending(component: Manifest.filename) : inputPath

        // Validate that the file exists.
        guard isFile(path) else { throw PackageModel.Package.Error.noManifest(path.asString) }

        // Load the manifest description.
        guard let tomlString = try parse(path: path) else {
            print("Empty manifest file is not supported anymore. Use `swift package init` to autogenerate.")
            throw ManifestParseError.emptyManifestFile
        }
        let toml = try TOMLItem.parse(tomlString)
        let package = PackageDescription.Package.fromTOML(toml, baseURL: baseURL)
        let products = PackageDescription.Product.fromTOML(toml)

        return Manifest(path: path, url: baseURL, package: package, products: products, version: version)
    }

    /// Parse the manifest at the given path to TOML.
    private func parse(path manifestPath: AbsolutePath) throws -> String? {
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

        // Create and open a temporary file to write toml to.
        let file = try TemporaryFile()
        // Pass the fd in arguments.
        cmd += ["-fileno", "\(file.fileHandle.fileDescriptor)"]
        do {
            try system(cmd)
        } catch {
            print("Can't parse Package.swift manifest file because it contains invalid format. Fix Package.swift file format and try again.")
            throw ManifestParseError.invalidManifestFormat
        }
    
        guard let toml = try localFileSystem.readFileContents(file.path).asString else {
            throw ManifestParseError.invalidEncoding
        }
    
        return toml != "" ? toml : nil
    }
}

// MARK: TOML Deserialization

// We separate this out from the raw PackageDescription module, so that the code
// we need to load to interpret the `Package.swift` manifests is as minimal as
// possible.
//
// FIXME: These APIs are `internal` so they can be unit tested, but otherwise
// could be private.

extension PackageDescription.Package {
    static func fromTOML(_ item: TOMLItem, baseURL: String? = nil) -> PackageDescription.Package {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .table(let topLevelTable) = item else { fatalError("unexpected item") }
        guard case .table(let table)? = topLevelTable.items["package"] else { fatalError("missing package") }

        guard case .string(let name)? = table.items["name"] else { fatalError("missing 'name'") }
        
        var pkgConfig: String? = nil
        if case .string(let value)? = table.items["pkgConfig"] {
            pkgConfig = value
        }

        // Parse the targets.
        var targets: [PackageDescription.Target] = []
        if case .array(let array)? = table.items["targets"] {
            for item in array.items {
                targets.append(PackageDescription.Target.fromTOML(item))
            }
        }
        
        var providers: [PackageDescription.SystemPackageProvider]? = nil
        if case .array(let array)? = table.items["providers"] {
            providers = []
            for item in array.items {
                providers?.append(PackageDescription.SystemPackageProvider.fromTOML(item))
            }
        }
        
        // Parse the dependencies.
        var dependencies: [PackageDescription.Package.Dependency] = []
        if case .array(let array)? = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Package.Dependency.fromTOML(item, baseURL: baseURL))
            }
        }

        // Parse the exclude folders.
        var exclude: [String] = []
        if case .array(let array)? = table.items["exclude"] {
            for item in array.items {
                guard case .string(let excludeItem) = item else { fatalError("exclude contains non string element") }
                exclude.append(excludeItem)
            }
        }
        
        return PackageDescription.Package(name: name, pkgConfig: pkgConfig, providers: providers, targets: targets, dependencies: dependencies, exclude: exclude)
    }
}

extension PackageDescription.Package.Dependency {
    static func fromTOML(_ item: TOMLItem, baseURL: String?) -> PackageDescription.Package.Dependency {
        guard case .array(let array) = item, array.items.count == 3 else {
            fatalError("Unexpected TOMLItem")
        }
        guard case .string(let url) = array.items[0],
              case .string(let vv1) = array.items[1],
              case .string(let vv2) = array.items[2],
              let v1 = Version(vv1), let v2 = Version(vv2)
        else {
            fatalError("Unexpected TOMLItem")
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
    fileprivate static func fromTOML(_ item: TOMLItem) -> PackageDescription.SystemPackageProvider {
        guard case .table(let table) = item else { fatalError("unexpected item") }
        guard case .string(let name)? = table.items["name"] else { fatalError("missing name") }
        guard case .string(let value)? = table.items["value"] else { fatalError("missing value") }
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
    fileprivate static func fromTOML(_ item: TOMLItem) -> PackageDescription.Target {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .table(let table) = item else { fatalError("unexpected item") }

        guard case .string(let name)? = table.items["name"] else { fatalError("missing name") }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Target.Dependency] = []
        if case .array(let array)? = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Target.Dependency.fromTOML(item))
            }
        }
        
        return PackageDescription.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription.Target.Dependency {
    fileprivate static func fromTOML(_ item: TOMLItem) -> PackageDescription.Target.Dependency {
        guard case .string(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}


extension PackageDescription.Product {
    private init(toml item: TOMLItem) {
        guard case .table(let table) = item else { fatalError("unexpected item") }
        guard case .string(let name)? = table.items["name"] else { fatalError("missing name") }

        let type: ProductType
        switch table.items["type"] {
        case .string("exe")?:
            type = .Executable
        case .string("a")?:
            type = .Library(.Static)
        case .string("dylib")?:
            type = .Library(.Dynamic)
        case .string("test")?:
            type = .Test
        default:
            fatalError("missing type")
        }

        guard case .array(let mods)? = table.items["mods"] else { fatalError("missing mods") }

        let modules = mods.items.map { item -> String in
            guard case TOMLItem.string(let string) = item else { fatalError("invalid modules") }
            return string
        }

        self.init(name: name, type: type, modules: modules)
    }

    static func fromTOML(_ item: TOMLItem) -> [PackageDescription.Product] {
        guard case .table(let root) = item else { fatalError("unexpected item") }
        guard let productsItem = root.items["products"] else { return [] }
        guard case .array(let array) = productsItem else { fatalError("products wrong type") }
        return array.items.map(Product.init)
    }
}
