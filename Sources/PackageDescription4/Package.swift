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
        public enum Requirement: Equatable {
          #if PACKAGE_DESCRIPTION_4_2
            case _exactItem(Version)
            case _rangeItem(Range<Version>)
            case _revisionItem(String)
            case _branchItem(String)
            case _localPackageItem
          #else
            case exactItem(Version)
            case rangeItem(Range<Version>)
            case revisionItem(String)
            case branchItem(String)
            case localPackageItem
          #endif
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

  #if PACKAGE_DESCRIPTION_4
    /// The list of swift versions, this package is compatible with.
    public var swiftLanguageVersions: [Int]?
  #elseif PACKAGE_DESCRIPTION_4_2
    /// The list of swift versions, this package is compatible with.
    public var swiftLanguageVersions: [SwiftVersion]?
  #else
    // The public API is an Int array but we will use String internally to
    // allow storing different types in the module when its loaded into SwiftPM.
    // This should go away in future once we stop using the same modules
    // internally and as the runtime.
    public var swiftLanguageVersions: [String]?
  #endif

    /// The C language standard to use for all C targets in this package.
    public var cLanguageStandard: CLanguageStandard?

    /// The C++ language standard to use for all C++ targets in this package.
    public var cxxLanguageStandard: CXXLanguageStandard?

  #if PACKAGE_DESCRIPTION_4_2
    /// Construct a package.
    public init(
        name: String,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        products: [Product] = [],
        dependencies: [Dependency] = [],
        targets: [Target] = [],
        swiftLanguageVersions: [SwiftVersion]? = nil,
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
        registerExitHandler()
    }
  #else
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

      #if PACKAGE_DESCRIPTION_4
        /// The list of swift versions, this package is compatible with.
        self.swiftLanguageVersions = swiftLanguageVersions
      #elseif PACKAGE_DESCRIPTION_4_2
        self.swiftLanguageVersions = swiftLanguageVersions?.map(String.init).map(SwiftVersion.version)
      #else
        self.swiftLanguageVersions = swiftLanguageVersions?.map(String.init)
      #endif

        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        registerExitHandler()
    }
  #endif

    private func registerExitHandler() {
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
public enum SystemPackageProvider: Equatable {

  #if PACKAGE_DESCRIPTION_4_2
    case _brewItem([String])
    case _aptItem([String])
  #else
    case brewItem([String])
    case aptItem([String])
  #endif

    /// Declare the list of packages installable using the homebrew package
    /// manager on macOS.
    public static func brew(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4_2
        return ._brewItem(packages)
      #else
        return .brewItem(packages)
      #endif
    }

    /// Declare the list of packages installable using the apt-get package
    /// manager on Ubuntu.
    public static func apt(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4_2
        return ._aptItem(packages)
      #else
        return .aptItem(packages)
      #endif
    }
}

// MARK: Package JSON serialization

extension SystemPackageProvider {

    func toJSON() -> JSON {
        let name: String
        let values: [String]

      #if PACKAGE_DESCRIPTION_4_2
        switch self {
        case ._brewItem(let packages):
            name = "brew"
            values = packages
        case ._aptItem(let packages):
            name = "apt"
            values = packages
        }
      #else
        switch self {
        case .brewItem(let packages):
            name = "brew"
            values = packages
        case .aptItem(let packages):
            name = "apt"
            values = packages
        }
      #endif

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

        let swiftLanguageVersionsString: [String]?
      #if PACKAGE_DESCRIPTION_4
        swiftLanguageVersionsString = self.swiftLanguageVersions?.map(String.init)
      #elseif PACKAGE_DESCRIPTION_4_2
        swiftLanguageVersionsString = self.swiftLanguageVersions?.map({ $0.toString() })
      #else
        swiftLanguageVersionsString = self.swiftLanguageVersions
      #endif
        if let swiftLanguageVersions = swiftLanguageVersionsString {
            dict["swiftLanguageVersions"] = .array(swiftLanguageVersions.map(JSON.string))
        }

        dict["cLanguageStandard"] = cLanguageStandard?.toJSON() ?? .null
        dict["cxxLanguageStandard"] = cxxLanguageStandard?.toJSON() ?? .null
        return .dictionary(dict)
    }
}

extension Target {
    func toJSON() -> JSON {
        var dict: [String: JSON] = [
            "name": .string(name),
            "type": .string(type.rawValue),
            "publicHeadersPath": publicHeadersPath.map(JSON.string) ?? JSON.null,
            "dependencies": .array(dependencies.map({ $0.toJSON() })),
            "path": path.map(JSON.string) ?? JSON.null,
            "exclude": .array(exclude.map(JSON.string)),
            "sources": sources.map({ JSON.array($0.map(JSON.string)) }) ?? JSON.null,
        ]
        if let pkgConfig = self.pkgConfig {
            dict["pkgConfig"] = .string(pkgConfig)
        }
        if let providers = self.providers {
            dict["providers"] = .array(providers.map({ $0.toJSON() }))
        }
        return .dictionary(dict)
    }
}

extension Target.Dependency {
    func toJSON() -> JSON {
        var dict = [String: JSON]()

      #if PACKAGE_DESCRIPTION_4_2
        switch self {
        case ._targetItem(let name):
            dict["name"] = .string(name)
            dict["type"] = .string("target")
        case ._productItem(let name, let package):
            dict["name"] = .string(name)
            dict["type"] = .string("product")
            dict["package"] = package.map(JSON.string) ?? .null
        case ._byNameItem(let name):
            dict["name"] = .string(name)
            dict["type"] = .string("byname")
        }
      #else
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
      #endif

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
