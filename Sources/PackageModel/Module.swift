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

@_exported import enum PackageDescription.SystemPackageProvider

public protocol ModuleProtocol {
    var name: String { get }
    var c99name: String { get }
    var dependencies: [Module] { get set }
    var recursiveDependencies: [Module] { get }
    var isTest: Bool { get }
}

public class Module: ModuleProtocol {
    /**
     This name is not the final name in many cases, instead
     use c99name if you need uniqueness.
    */
    public let name: String
    public var dependencies: [Module]  /// in build order
    public var c99name: String
    public let isTest: Bool
    private let testModuleNameSuffix = "TestSuite"

    public init(name: String, isTest: Bool = false) throws {
        // Append TestSuite to name if its a test module.
        self.name = name + (isTest ? testModuleNameSuffix : "")
        self.dependencies = []
        self.c99name = try PackageModel.c99name(name: self.name)
        self.isTest = isTest
    }

    public var recursiveDependencies: [Module] {
        return PackageModel.recursiveDependencies(dependencies)
    }

    /// The base prefix for the test module, used to associate with the target it tests.
    public var basename: String {
        guard isTest else {
            fatalError("\(self.dynamicType) should be a test module to access basename.")
        }
        precondition(name.hasSuffix(testModuleNameSuffix))
        return name[name.startIndex..<name.index(name.endIndex, offsetBy: -testModuleNameSuffix.characters.count)]
    }
}

public enum ModuleType {
    case library, executable
}

public protocol ModuleTypeProtocol {
    var sources: Sources { get }
    var type: ModuleType { get }
}

extension ModuleTypeProtocol {
    public var type: ModuleType {
        let isLibrary = !sources.relativePaths.contains { path in
           let file = path.basename.lowercased()
           // Look for a main.xxx file avoiding cases like main.xxx.xxx
           return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        return isLibrary ? .library : .executable
    }
}


public protocol XcodeModuleProtocol: ModuleProtocol, ModuleTypeProtocol {
    var fileType: String { get }
}

extension Module: Hashable, Equatable {
    public var hashValue: Int { return c99name.hashValue }
}

public func ==(lhs: Module, rhs: Module) -> Bool {
    return lhs.c99name == rhs.c99name
}

public class SwiftModule: Module {
    public let sources: Sources

    public init(name: String, isTest: Bool = false, sources: Sources) throws {
        self.sources = sources
        try super.init(name: name, isTest: isTest)
    }
}

extension SwiftModule: XcodeModuleProtocol {
    public var fileType: String {
        return "sourcecode.swift"
    }
}

public class CModule: Module {
    public let path: String
    public let pkgConfig: String?
    public let providers: [SystemPackageProvider]?
    public init(name: String, path: String, isTest: Bool = false, pkgConfig: String? = nil, providers: [SystemPackageProvider]? = nil) throws {
        self.path = path
        self.pkgConfig = pkgConfig
        self.providers = providers
        // FIXME: This is wrong, System modules should never be a test module, perhaps ClangModule
        // can be refactored into direct subclass of Module.
        try super.init(name: name, isTest: isTest)
    }
}

public class ClangModule: CModule {
    public let sources: Sources
    
    public init(name: String, isTest: Bool = false, sources: Sources) throws {
        self.sources = sources
        try super.init(name: name, path: sources.root + "/include", isTest: isTest)
    }
}

extension ClangModule: XcodeModuleProtocol {
    public var fileType: String {
        return "sourcecode.c.c"
    }
}

extension Module: CustomStringConvertible {
    public var description: String {
        return "\(self.dynamicType)(\(name))"
    }
}

private func recursiveDependencies(_ modules: [Module]) -> [Module] {
    // FIXME: Refactor this to a common algorithm.
    var stack = modules
    var set = Set<Module>()
    var rv = [Module]()

    while stack.count > 0 {
        let top = stack.removeFirst()
        if !set.contains(top) {
            rv.append(top)
            set.insert(top)
            stack += top.dependencies
        }
    }

    return rv
}
