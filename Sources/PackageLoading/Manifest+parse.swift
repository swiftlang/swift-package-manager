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

extension Manifest {
    /// Create a manifest by loading from the given path.
    ///
    /// - path: The path to the manifest file or directory containing `Package.swift`.
    public init(path inputPath: String, baseURL: String, swiftc: String, libdir: String) throws {
        guard baseURL.chuzzle() != nil else { fatalError() }  //TODO

        // Canonicalize the URL.
        var baseURL = baseURL
        if URL.scheme(baseURL) == nil {
            baseURL = try realpath(baseURL)
        }

        // Compute the actual input file path.
        let path: String = inputPath.isDirectory ? Path.join(inputPath, Manifest.filename) : inputPath

        // Validate that the file exists.
        guard path.isFile else { throw PackageModel.Package.Error.noManifest(path) }

        // Load the manifest description.
        guard let tomlString = try parse(path: path, swiftc: swiftc, libdir: libdir) else {
            print("Empty manifest file is not supported anymore. Use `swift package init` to autogenerate.")
            throw ManifestParseError.emptyManifestFile
        }
        let toml = try TOMLItem.parse(tomlString)
        let package = PackageDescription.Package.fromTOML(toml, baseURL: baseURL)
        let products = PackageDescription.Product.fromTOML(toml)

        self.init(path: path, package: package, products: products)
    }
}

private func parse(path manifestPath: String, swiftc: String, libdir: String) throws -> String? {
    // For now, we load the manifest by having Swift interpret it directly.
    // Eventually, we should have two loading processes, one that loads only the
    // the declarative package specification using the Swift compiler directly
    // and validates it.

    var cmd = [swiftc]
    cmd += ["--driver-mode=swift"]
    cmd += verbosity.ccArgs
    cmd += ["-I", libdir]

    // When running from Xcode, load PackageDescription.framework
    // else load the dylib version of it
#if Xcode
    cmd += ["-F", libdir]
    cmd += ["-framework", "PackageDescription"]
#else
    cmd += ["-L", libdir, "-lPackageDescription"] 
#endif

#if os(OSX)
    cmd += ["-target", "x86_64-apple-macosx10.10"]
#endif
    cmd += [manifestPath]

    //Create and open a temporary file to write toml to
    let filePath = Path.join(manifestPath.parentDirectory, ".Package.toml")
    let fp = try fopen(filePath, mode: .write)
    defer { fp.closeFile() }

    //Pass the fd in arguments
    cmd += ["-fileno", "\(fp.fileDescriptor)"]
    do {
        try system(cmd)
    } catch {
        print("Can't parse Package.swift manifest file because it contains invalid format. Fix Package.swift file format and try again.")
        throw ManifestParseError.invalidManifestFormat
    }

    guard let toml = try localFileSystem.readFileContents(filePath).asString else {
        throw ManifestParseError.invalidEncoding
    }
    try Utility.removeFileTree(filePath) // Delete the temp file after reading it

    return toml != "" ? toml : nil
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

        var name: String? = nil
        if case .string(let value)? = table.items["name"] {
            name = value
        }
        
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

        // Parse the test dependencies.
        var testDependencies: [PackageDescription.Package.Dependency] = []
        if case .array(let array)? = table.items["testDependencies"] {
            for item in array.items {
                testDependencies.append(PackageDescription.Package.Dependency.fromTOML(item, baseURL: baseURL))
            }
        }

        //Parse the exclude folders.
        var exclude: [String] = []
        if case .array(let array)? = table.items["exclude"] {
            for item in array.items {
                guard case .string(let excludeItem) = item else { fatalError("exclude contains non string element") }
                exclude.append(excludeItem)
            }
        }
        
        return PackageDescription.Package(name: name, pkgConfig: pkgConfig, providers: providers, targets: targets, dependencies: dependencies, testDependencies: testDependencies, exclude: exclude)
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
                return Path.join(baseURL, url).normpath
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
