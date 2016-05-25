/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Utility
import PackageModel

extension CModule {
    
    public var moduleMap: String {
        return "module.modulemap"
    }
    
    public var moduleMapPath: String {
        return Path.join(path, moduleMap)
    }
}

extension ClangModule {
    
    public enum ModuleMapError: ErrorProtocol {
        case unsupportedIncludeLayoutForModule(String)
    }
    
    ///FIXME: we recompute the generated modulemap's path
    ///when building swift modules in `XccFlags(prefix: String)`
    ///there shouldn't be need to redo this there but is difficult 
    ///in current architecture
    public func generateModuleMap(inDir wd: String) throws {
        precondition(wd.isAbsolute)
        
        ///Return if module map is already present
        guard !moduleMapPath.isFile else {
            return
        }
        
        let includeDir = path
        
        ///Warn and return if no include directory
        guard includeDir.isDirectory else {
            print("warning: No include directory found for module '\(name)'. A library can not be imported without any public headers.")
            return
        }
        
        let walked = walk(includeDir, recursively: false).map{$0}
        
        let files = walked.filter{$0.isFile && $0.hasSuffix(".h")}
        let dirs = walked.filter{$0.isDirectory}

        ///We generate modulemap for a C module `foo` if:
        ///* `umbrella header "path/to/include/foo/foo.h"` exists and `foo` is the only
        ///   directory under include directory
        ///* `umbrella header "path/to/include/foo.h"` exists and include contains no other
        ///   directory
        ///* `umbrella "path/to/include"` in all other cases

        let umbrellaHeaderFlat = Path.join(includeDir, "\(c99name).h")
        if umbrellaHeaderFlat.isFile {
            guard dirs.isEmpty else { throw ModuleMapError.unsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeaderFlat))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir)

        let umbrellaHeader = Path.join(includeDir, c99name, "\(c99name).h")
        if umbrellaHeader.isFile {
            guard dirs.count == 1 && files.isEmpty else { throw ModuleMapError.unsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeader))
            return
        }
        diagnoseInvalidUmbrellaHeader(Path.join(includeDir, c99name))

        try createModuleMap(inDir: wd, type: .directory(includeDir))
    }

    ///warn user if in case module name and c99name are different and there a `name.h` umbrella header
    private func diagnoseInvalidUmbrellaHeader(_ path: String) {
        let umbrellaHeader = Path.join(path, "\(c99name).h")
        let invalidUmbrellaHeader = Path.join(path, "\(name).h")
        if c99name != name && invalidUmbrellaHeader.isFile {
            print("warning: \(invalidUmbrellaHeader) should be renamed to \(umbrellaHeader) to be used as an umbrella header")
        }
    }

    private enum UmbrellaType {
        case header(String)
        case directory(String)
    }
    
    private func createModuleMap(inDir wd: String, type: UmbrellaType) throws {
        try Utility.makeDirectories(wd)
        let moduleMapFile = Path.join(wd, self.moduleMap)
        let moduleMap = try fopen(moduleMapFile, mode: .write)
        defer { moduleMap.closeFile() }
        
        var output = "module \(c99name) {\n"
        switch type {
        case .header(let header):
            output += "    umbrella header \"\(header)\"\n"
        case .directory(let path):
            output += "    umbrella \"\(path)\"\n"
        }
        output += "    link \"\(c99name)\"\n"
        output += "    export *\n"
        output += "}\n"

        try fputs(output, moduleMap)
    }
}
