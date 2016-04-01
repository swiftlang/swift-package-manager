/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import struct Utility.Path

protocol Buildable {
    var targetName: String { get }
    var isTest: Bool { get }
}

extension CModule {
    func workingDirectory(prefix: String) -> String {
        return Path.join(prefix, "\(c99name).build")
    }
}

extension Module: Buildable {
    var isTest: Bool {
        return self is TestModule
    }

    func XccFlagsForPrefix(prefix: String) -> [String] {
        return recursiveDependencies.flatMap { module -> [String] in
            if let module = module as? ClangModule {
                var moduleMap: String? = nil
                
                if module.moduleMapPath.isFile {
                    moduleMap = module.moduleMapPath
                }
    
                let genModuleMap = Path.join(module.workingDirectory(prefix), module.moduleMap)
                if genModuleMap.isFile {
                    moduleMap = genModuleMap
                }
                //No module map found, return with no args
                if let moduleMap = moduleMap {
                    return ["-Xcc", "-fmodule-map-file=\(moduleMap)"]
                }
                return []
            } else if let module = module as? CModule {
                return ["-Xcc", "-fmodule-map-file=\(module.moduleMapPath)"]
            } else {
                return []
            }
        }
    }

    var targetName: String {
        return "<\(name).module>"
    }
}

extension Product: Buildable {
    var isTest: Bool {
        if case .Test = type {
            return true
        }
        return false
    }

    var targetName: String {
        switch type {
        case .Library(.Dynamic):
            return "<\(name).dylib>"
        case .Test:
            return "<\(name).test>"
        case .Library(.Static):
            return "<\(name).a>"
        case .Executable:
            return "<\(name).exe>"
        }
    }
}
