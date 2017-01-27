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

    /// Whether this is a test module.
    //
    // FIXME: This should probably be rolled into the type.
    public let isTest: Bool
    
    /// Suffix that's expected for test modules.
    public static let testModuleNameSuffix = "Tests"

    /// The "type" of module.
    public let type: ModuleType

    /// The sources for the module.
    public let sources: Sources

    fileprivate init(name: String, type: ModuleType, sources: Sources, isTest: Bool = false, dependencies: [Module]) {
        self.name = name
        self.type = type
        self.sources = sources
        self.dependencies = dependencies
        self.c99name = self.name.mangledToC99ExtendedIdentifier()
        self.isTest = isTest
    }
}

public class SwiftModule: Module {

    /// Create an executable Swift module from linux main test manifest file.
    public init(linuxMain: AbsolutePath, name: String, dependencies: [Module] = []) {
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)
        super.init(name: name, type: .executable, sources: sources, isTest: true, dependencies: dependencies)
    }

    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) {
        // Compute the module type.
        let isLibrary = !sources.relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        let type: ModuleType = isLibrary ? .library : .executable
        
        super.init(name: name, type: type, sources: sources, isTest: isTest, dependencies: dependencies)
    }
}

public class CModule: Module {
    public let path: AbsolutePath
    public let pkgConfig: String?
    public let providers: [SystemPackageProvider]?
    public init(name: String, type: ModuleType = .systemModule, sources: Sources, path: AbsolutePath, isTest: Bool = false, pkgConfig: String? = nil, providers: [SystemPackageProvider]? = nil, dependencies: [Module] = []) {
        self.path = path
        self.pkgConfig = pkgConfig
        self.providers = providers
        super.init(name: name, type: type, sources: sources, isTest: false, dependencies: dependencies)
    }
}

public class ClangModule: Module {

    public var includeDir: AbsolutePath {
        return sources.root.appending(component: "include")
    }

    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) {
        // Compute the module type.
        let isLibrary = !sources.relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        let type: ModuleType = isLibrary ? .library : .executable
        
        super.init(name: name, type: type, sources: sources, isTest: isTest, dependencies: dependencies)
    }
}

extension Module: CustomStringConvertible {
    public var description: String {
        return "\(type(of: self))(\(name))"
    }
}
