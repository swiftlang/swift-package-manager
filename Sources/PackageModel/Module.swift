/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------------

 A Target is a collection of sources and configuration that can be built
 into a product.
 
 TODO should be a protocol
*/

import Basic

@_exported import enum PackageDescription.SystemPackageProvider

public enum ModuleType: String {
    case executable
    case library
    case systemModule = "system-module"
}

public class Module {
    /// The name of the module.
    ///
    /// NOTE: This name is not the language-level module (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public let name: String

    /// The dependencies of this module, once loaded.
    public var dependencies: [Module]

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

    public init(name: String, type: ModuleType, sources: Sources, isTest: Bool = false, dependencies: [Module]) throws {
        self.name = name
        self.type = type
        self.sources = sources
        self.dependencies = dependencies
        self.c99name = self.name.mangledToC99ExtendedIdentifier()
        self.isTest = isTest
    }

    /// The transitive closure of the module dependencies, in build order.
    //
    // FIXME: This should be cached, once we have an immutable model.
    public var recursiveDependencies: [Module] {
        return (try! topologicalSort(dependencies, successors: { $0.dependencies })).reversed()
    }

    /// The base prefix for the test module, used to associate with the target it tests.
    public var basename: String {
        guard isTest else {
            fatalError("\(type(of: self)) should be a test module to access basename.")
        }
        precondition(name.hasSuffix(Module.testModuleNameSuffix))
        return name[name.startIndex..<name.index(name.endIndex, offsetBy: -Module.testModuleNameSuffix.characters.count)]
    }
}

extension Module: Hashable, Equatable {
    public var hashValue: Int { return c99name.hashValue }
}

public func ==(lhs: Module, rhs: Module) -> Bool {
    return lhs.c99name == rhs.c99name
}

public class SwiftModule: Module {
    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) throws {
        // Compute the module type.
        let isLibrary = !sources.relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        let type: ModuleType = isLibrary ? .library : .executable
        
        try super.init(name: name, type: type, sources: sources, isTest: isTest, dependencies: dependencies)
    }
}

public class CModule: Module {
    public let path: AbsolutePath
    public let pkgConfig: RelativePath?
    public let providers: [SystemPackageProvider]?
    public init(name: String, type: ModuleType = .systemModule, sources: Sources, path: AbsolutePath, isTest: Bool = false, pkgConfig: RelativePath? = nil, providers: [SystemPackageProvider]? = nil, dependencies: [Module] = []) throws {
        self.path = path
        self.pkgConfig = pkgConfig
        self.providers = providers
        try super.init(name: name, type: type, sources: sources, isTest: false, dependencies: dependencies)
    }
}

public class ClangModule: Module {

    public var includeDir: AbsolutePath {
        return sources.root.appending(component: "include")
    }

    public init(name: String, isTest: Bool = false, sources: Sources, dependencies: [Module] = []) throws {
        // Compute the module type.
        let isLibrary = !sources.relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        let type: ModuleType = isLibrary ? .library : .executable
        
        try super.init(name: name, type: type, sources: sources, isTest: isTest, dependencies: dependencies)
    }
}

extension Module: CustomStringConvertible {
    public var description: String {
        return "\(type(of: self))(\(name))"
    }
}
