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

public protocol ModuleProtocol {
    var name: String { get }
    var c99name: String { get }
    var dependencies: [Module] { get set }
    var recursiveDependencies: [Module] { get }
}

public class Module: ModuleProtocol {
    /**
     This name is not the final name in many cases, instead
     use c99name if you need uniqueness.
    */
    public let name: String
    public var dependencies: [Module]  /// in build order
    public var c99name: String

    public init(name: String) throws {
        self.name = name
        self.dependencies = []
        self.c99name = try PackageType.c99name(name: name)
    }

    public var recursiveDependencies: [Module] {
        return PackageType.recursiveDependencies(dependencies)
    }
}

public enum ModuleType {
    case Library, Executable
}

public protocol ModuleTypeProtocol {
    var sources: Sources { get }
    var type: ModuleType { get }
    var mainFile: String { get }
}

extension ModuleTypeProtocol {
    public var type: ModuleType {
        let isLibrary = !sources.relativePaths.contains { path in
            path.basename.lowercased() == mainFile
        }
        return isLibrary ? .Library : .Executable
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

    public init(name: String, sources: Sources) throws {
        self.sources = sources
        try super.init(name: name)
    }
}

extension SwiftModule: ModuleTypeProtocol {
    public var mainFile: String {
        return "main.swift"
    }
}

extension SwiftModule: XcodeModuleProtocol {
    public var fileType: String {
        return "sourcecode.swift"
    }
}

public class CModule: Module {
    public let path: String

    public init(name: String, path: String) throws {
        self.path = path
        try super.init(name: name)
    }
}

public class ClangModule: CModule {
    public let sources: Sources
    
    public init(name: String, sources: Sources) throws {
        self.sources = sources
        try super.init(name: name, path: sources.root + "/include")
    }
}

extension ClangModule: XcodeModuleProtocol {
    public var fileType: String {
        return "sourcecode.c.c"
    }
}

extension ClangModule: ModuleTypeProtocol {
    public var mainFile: String {
        return "main.c"
    }
}

public class TestModule: SwiftModule {

    public init(basename: String, sources: Sources) throws {
        try super.init(name: "\(basename).testsuite", sources: sources)
        c99name = try PackageType.c99name(name: basename) + "TestSuite"
    }

    public var basename: String {
        return String(name.characters.dropLast(10))
    }
}


extension Module: CustomStringConvertible {
    public var description: String {
        return "\(self.dynamicType)(\(name))"
    }
}


//FIXME swift on Linux crashed with this:
//extension Array where Element: Module {
//    public func recursiveDependencies() -> [Module] {
//        var stack: [Module] = self
//        var set = Set<Module>()
//        var rv = [Module]()
//
//        while stack.count > 0 {
//            let top = stack.removeFirst()
//            if !set.contains(top) {
//                rv.append(top)
//                set.insert(top)
//                stack += top.dependencies
//            }
//        }
//
//        return rv
//    }
//}

public func recursiveDependencies(_ modules: [Module]) -> [Module] {
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
