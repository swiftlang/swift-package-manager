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

public class Module {
    /**
     This name is not the final name in many cases, instead
     use c99name if you need uniqueness.
    */
    public let name: String
    public var dependencies: [Module]  /// in build order

    public init(name: String) {
        self.name = name
        self.dependencies = []
    }

    public var recursiveDependencies: [Module] {
        return PackageType.recursiveDependencies(dependencies)
    }
}

extension Module: Hashable, Equatable {
    public var hashValue: Int { return c99name.hashValue }
}

public func ==(lhs: Module, rhs: Module) -> Bool {
    return lhs.c99name == rhs.c99name
}

public class SwiftModule: Module {
    public let sources: Sources

    public init(name: String, sources: Sources) {
        self.sources = sources
        super.init(name: name)
    }

    public enum ModuleType {
        case Library, Executable
    }

    public var type: ModuleType {
        let isLibrary = !sources.relativePaths.contains { path in
            path.basename.lowercased() == "main.swift"
        }
        return isLibrary ? .Library : .Executable
    }
}

public class CModule: Module {
    public let path: String

    public init(name: String, path: String) {
        self.path = path
        super.init(name: name)
    }
}

public class TestModule: SwiftModule {

    public init(basename: String, sources: Sources) {
        super.init(name: "\(basename).test", sources: sources)
    }

    public var basename: String {
        return String(name.characters.dropLast(5))
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

public func recursiveDependencies(modules: [Module]) -> [Module] {
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
