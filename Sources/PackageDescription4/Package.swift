/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

/// The description for a complete package.
public final class Package {

    /// Represents a package dependency.
    public class Dependency {

        /// The dependency requirement.
        public enum Requirement {
            case exactItem(Version)
            case rangeItem(Range<Version>)
            case revisionItem(String)
            case branchItem(String)
        }

        /// The url of the dependency.
        public let url: String

        /// The dependency requirement.
        public let requirement: Requirement

        /// Create a dependency.
        init(url: String, requirement: Requirement) {
            self.url = url
            self.requirement = requirement
        }
    }

    /// The name of the package.
    public var name: String

    /// pkgconfig name to use for C Modules. If present, swiftpm will try to
    /// search for <name>.pc file to get the additional flags needed for the
    /// system target.
    public var pkgConfig: String?

    /// Providers array for System target
    public var providers: [SystemPackageProvider]?

    /// The list of targets.
    public var targets: [Target]

    /// The list of products vended by this package.
    public var products: [Product]

    /// The list of dependencies.
    public var dependencies: [Dependency]

    /// The list of swift versions, this package is compatible with.
    public var swiftLanguageVersions: [Int]?

    /// The C language standard to use for all C targets in this package.
    public var cLanguageStandard: CLanguageStandard?

    /// The C++ language standard to use for all C++ targets in this package.
    public var cxxLanguageStandard: CXXLanguageStandard?

    /// Construct a package.
    public init(
        name: String,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        products: [Product] = [],
        dependencies: [Dependency] = [],
        targets: [Target] = [],
        swiftLanguageVersions: [Int]? = nil,
        cLanguageStandard: CLanguageStandard? = nil,
        cxxLanguageStandard: CXXLanguageStandard? = nil
    ) {
        self.name = name
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.products = products
        self.dependencies = dependencies
        self.targets = targets
        self.swiftLanguageVersions = swiftLanguageVersions
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard

        // Add custom exit handler to cause package to be dumped at exit, if
        // requested.
        //
        // FIXME: This doesn't belong here, but for now is the mechanism we use
        // to get the interpreter to dump the package when attempting to load a
        // manifest.
        if CommandLine.argc > 0,
           let fileNoOptIndex = CommandLine.arguments.index(of: "-fileno"),
           let fileNo = Int32(CommandLine.arguments[fileNoOptIndex + 1]) {
            dumpPackageAtExit(self, fileNo: fileNo)
        }
    }
}

/// Represents system package providers.
public enum SystemPackageProvider {
    case brewItem([String])
    case aptItem([String])

    /// Declare the list of packages installable using the homebrew package
    /// manager on macOS.
    public static func brew(_ packages: [String]) -> SystemPackageProvider {
        return .brewItem(packages)
    }

    /// Declare the list of packages installable using the apt-get package
    /// manager on Ubuntu.
    public static func apt(_ packages: [String]) -> SystemPackageProvider {
        return .aptItem(packages)
    }
}

// MARK: Package JSON serialization

extension SystemPackageProvider: Equatable {

    public static func == (lhs: SystemPackageProvider, rhs: SystemPackageProvider) -> Bool {
        switch (lhs, rhs) {
        case (.brewItem(let lhs), .brewItem(let rhs)):
            return lhs == rhs
        case (.brewItem, _):
            return false
        case (.aptItem(let lhs), .aptItem(let rhs)):
            return lhs == rhs
        case (.aptItem, _):
            return false
        }
    }

    func toJSON() -> JSON {
        let name: String
        let values: [String]
        switch self {
        case .brewItem(let packages):
            name = "brew"
            values = packages
        case .aptItem(let packages):
            name = "apt"
            values = packages
        }
        return .dictionary([
            "name": .string(name),
            "values": .array(values.map(JSON.string)),
        ])
    }
}

extension Package {
    func toJSON() -> JSON {
        var dict: [String: JSON] = [:]
        dict["name"] = .string(name)
        if let pkgConfig = self.pkgConfig {
            dict["pkgConfig"] = .string(pkgConfig)
        }
        dict["dependencies"] = .array(dependencies.map({ $0.toJSON() }))
        dict["targets"] = .array(targets.map({ $0.toJSON() }))
        dict["products"] = .array(products.map({ $0.toJSON() }))
        if let providers = self.providers {
            dict["providers"] = .array(providers.map({ $0.toJSON() }))
        }
        if let swiftLanguageVersions = self.swiftLanguageVersions {
            dict["swiftLanguageVersions"] = .array(swiftLanguageVersions.map(JSON.int))
        }
        dict["cLanguageStandard"] = cLanguageStandard?.toJSON() ?? .null
        dict["cxxLanguageStandard"] = cxxLanguageStandard?.toJSON() ?? .null
        return .dictionary(dict)
    }
}

extension Target {
    func toJSON() -> JSON {
        return .dictionary([
            "name": .string(name),
            "isTest": .bool(isTest),
            "publicHeadersPath": publicHeadersPath.map(JSON.string) ?? JSON.null,
            "dependencies": .array(dependencies.map({ $0.toJSON() })),
            "path": path.map(JSON.string) ?? JSON.null,
            "exclude": .array(exclude.map(JSON.string)),
            "sources": sources.map({ JSON.array($0.map(JSON.string)) }) ?? JSON.null,
        ])
    }
}

extension Target.Dependency {
    func toJSON() -> JSON {
        var dict = [String: JSON]()
        switch self {
        case .targetItem(let name):
            dict["name"] = .string(name)
            dict["type"] = .string("target")
        case .productItem(let name, let package):
            dict["name"] = .string(name)
            dict["type"] = .string("product")
            dict["package"] = package.map(JSON.string) ?? .null
        case .byNameItem(let name):
            dict["name"] = .string(name)
            dict["type"] = .string("byname")
        }
        return .dictionary(dict)
    }
}

// MARK: Package Dumping

struct Errors {
    /// Storage to hold the errors.
    private var errors = [String]()

    /// Adds error to global error array which will be serialized and dumped in
    /// JSON at exit.
    mutating func add(_ str: String) {
        // FIXME: This will produce invalid JSON if string contains quotes.
        // Assert it for now and fix when we have escaping in JSON.
        assert(!str.contains("\""), "Error string shouldn't have quotes in it.")
        errors += [str]
    }

    func toJSON() -> JSON {
        return .array(errors.map(JSON.string))
    }
}

func manifestToJSON(_ package: Package) -> String {
    var dict: [String: JSON] = [:]
    dict["package"] = package.toJSON()
    dict["errors"] = errors.toJSON()
    return JSON.dictionary(dict).toString()
}

// FIXME: This function is public to let other targets access JSON string
// representation of the package without exposing the enum JSON defined in this
// target because that'll leak to clients of PackageDescription i.e every
// Package.swift file.
public func jsonString(package: Package) -> String {
    return package.toJSON().toString()
}

var errors = Errors()
private var dumpInfo: (package: Package, fileNo: Int32)?
private func dumpPackageAtExit(_ package: Package, fileNo: Int32) {
    func dump() {
        guard let dumpInfo = dumpInfo else { return }
        let fd = fdopen(dumpInfo.fileNo, "w")
        guard fd != nil else { return }
        fputs(manifestToJSON(dumpInfo.package), fd)
        fclose(fd)
    }
    dumpInfo = (package, fileNo)
    atexit(dump)
}
