/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

@_exported import enum PackageDescription.SystemPackageProvider

public enum ModuleType: String {
    case executable
    case library
    case systemModule = "system-module"
    case test
}

public class Module: ObjectIdentifierProtocol {
    /// The name of the module.
    ///
    /// NOTE: This name is not the language-level module (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public let name: String

    /// The dependencies of this module.
    public let dependencies: [Module]

    /// The language-level module name.
    public let c99name: String

    /// Suffix that's expected for test modules.
    public static let testModuleNameSuffix = "Tests"

    /// The "type" of module.
    public let type: ModuleType

    /// The sources for the module.
    public let sources: Sources

    fileprivate init(name: String, type: ModuleType, sources: Sources, dependencies: [Module]) {
        self.name = name
        self.type = type
        self.sources = sources
        self.dependencies = dependencies
        self.c99name = self.name.mangledToC99ExtendedIdentifier()
    }
}

public class SwiftModule: Module {

    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) {
        let type: ModuleType = isTest ? .test : sources.computeModuleType()
        super.init(name: name, type: type, sources: sources, dependencies: dependencies)
    }
}

public class CModule: Module {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProvider]?

    /// The package path.
    public var path: AbsolutePath {
        return sources.root
    }

    public init(
        name: String,
        path: AbsolutePath,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        super.init(name: name, type: .systemModule, sources: sources, dependencies: [])
    }
}

public class ClangModule: Module {

    public var includeDir: AbsolutePath {
        return sources.root.appending(component: "include")
    }

    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) {
        let type: ModuleType = isTest ? .test : sources.computeModuleType()
        super.init(name: name, type: type, sources: sources, dependencies: dependencies)
    }
}

extension Module: CustomStringConvertible {
    public var description: String {
        return "\(type(of: self))(\(name))"
    }
}

extension Sources {
    /// Determine module type based on the sources.
    fileprivate func computeModuleType() -> ModuleType {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        return isLibrary ? .library : .executable
    }
}
