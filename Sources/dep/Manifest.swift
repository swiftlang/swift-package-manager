/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines the support for loading the Swift-based manifest files.
*/

import PackageDescription
import POSIX
import sys

extension PackageDescription.Package {
    public static func fromTOML(item: TOMLItem, baseURL: String? = nil) -> PackageDescription.Package {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .Table(let topLevelTable) = item else { fatalError("unexpected item") }
        guard case .Some(.Table(let table)) = topLevelTable.items["package"] else { fatalError("missing package") }

        var name: String? = nil
        if case .Some(.String(let value)) = table.items["name"] {
            name = value
        }

        // Parse the targets.
        var targets: [PackageDescription.Target] = []
        if case .Some(.Array(let array)) = table.items["targets"] {
            for item in array.items {
                targets.append(PackageDescription.Target.fromTOML(item))
            }
        }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Package.Dependency] = []
        if case .Some(.Array(let array)) = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Package.Dependency.fromTOML(item, baseURL: baseURL))
            }
        }
        
        return PackageDescription.Package(name: name, targets: targets, dependencies: dependencies)
    }
}

extension PackageDescription.Package.Dependency {
    public static func fromTOML(item: TOMLItem, baseURL: String?) -> PackageDescription.Package.Dependency {
        guard case .Array(let array) = item where array.items.count == 3 else {
            fatalError("Unexpected TOMLItem")
        }
        guard case .String(let url) = array.items[0],
              case .String(let vv1) = array.items[1],
              case .String(let vv2) = array.items[2],
              let v1 = Version(vv1), v2 = Version(vv2)
        else {
            fatalError("Unexpected TOMLItem")
        }

        func fixURL() -> String {
            if let baseURL = baseURL where URL.scheme(url) == nil {
                return Path.join(baseURL, url).normpath
            } else {
                return url
            }
        }

        return PackageDescription.Package.Dependency.Package(url: fixURL(), versions: v1..<v2)
    }
}

extension PackageDescription.Target {
    private static func fromTOML(item: TOMLItem) -> PackageDescription.Target {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .Table(let table) = item else { fatalError("unexpected item") }

        guard case .Some(.String(let name)) = table.items["name"] else { fatalError("missing name") }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Target.Dependency] = []
        if case .Some(.Array(let array)) = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Target.Dependency.fromTOML(item))
            }
        }
        
        return PackageDescription.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription.Target.Dependency {
    private static func fromTOML(item: TOMLItem) -> PackageDescription.Target.Dependency {
        guard case .String(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}


/**
 MARK: Manifest Loading

 This contains the declarative specification loaded from package manifest
 files, and the tools for working with the manifest.
*/
public struct Manifest {
    /// The top-level package definition.
    public let package: PackageDescription.Package

    /// Create a manifest from a pre-formed package.
    init(package: PackageDescription.Package) {
        self.package = package
    }
    
    /// Load the manifest at the given path.
    public init(path: String, baseURL: String? = nil) throws {
        // For now, we load the manifest by having Swift interpret it directly
        // and using a special environment variable to trigger the PackageDescription
        // library to dump the package (as TOML) at exit.  Eventually, we should
        // have two loading processes, one that loads only the the declarative
        // package specification using the Swift compiler directly and validates
        // it.
        //
        // FIXME: We also should make the mechanism for communicating the
        // package between the PackageDescription module more robust, for example by passing
        // in the id of another file descriptor to write the output onto.
        let libDir = Resources.runtimeLibPath
        let swiftcPath = getenv("SWIFTC") ?? Resources.findExecutable("swiftc")
        var cmd = [swiftcPath, "--driver-mode=swift", "-I", libDir, "-L", libDir, "-lPackageDescription"]
#if os(OSX)
        cmd += ["-target", "x86_64-apple-macosx10.10"]
#endif
        cmd.append(path)
        let toml = try popen(cmd, environment: ["SWIFT_DUMP_PACKAGE": "1"])

        // As a special case, we accept an empty file as an unnamed package.
        if toml.chuzzle() == nil {
            self.package = PackageDescription.Package()
            return
        }

        // canonicalize URLs
        var baseURL = baseURL
        if baseURL != nil && URL.scheme(baseURL!) == nil {
            baseURL = try realpath(baseURL!)
        }
        
        // Deserialize the package.
        do {
            self.package = PackageDescription.Package.fromTOML(try TOMLItem.parse(toml), baseURL: baseURL)
        } catch let err as TOMLParsingError {
            throw Error.InvalidManifest("unable to parse package dump", errors: err.errors, data: toml)
        }
    }

    public static var filename: String {
        return "Package.swift"
    }
}
