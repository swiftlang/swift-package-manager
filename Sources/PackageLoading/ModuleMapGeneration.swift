/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Utility
import PackageModel

extension CModule {
    public static let moduleMapFilename = "module.modulemap"
    
    public var moduleMapPath: AbsolutePath {
        return path.appending(component: CModule.moduleMapFilename)
    }
}

extension ClangModule {
    
    /// A link-declaration specifies a library or framework
    /// against which a program should be linked.
    /// More info: http://clang.llvm.org/docs/Modules.html#link-declaration
    /// A `library` modulemap style uses `link` flag for link-declaration where
    /// as a `framework` uses `link framework` flag and a framework module.
    public enum ModuleMapStyle {
        case library
        case framework

        /// Link declaration flag to be used in modulemap.
        var linkDeclFlag: String {
            switch self {
            case .library:
                return "link"
            case .framework:
                return "link framework"
            }
        }

        var moduleDeclQualifier: String? {
            switch self {
            case .library:
                return nil
            case .framework:
                return "framework"
            }
        }
    }

    public enum ModuleMapError: Swift.Error {
        case unsupportedIncludeLayoutForModule(String)
    }

    /// Create the synthesized module map, if necessary.
    //
    // FIXME: We recompute the generated modulemap's path when building swift
    // modules in `XccFlags(prefix: String)` there shouldn't be need to redo
    // this there but is difficult in current architecture.
    public func generateModuleMap(inDir wd: AbsolutePath, modulemapStyle: ModuleMapStyle = .library) throws {
        // Don't generate modulemap for a Test module.
        guard !isTest else {
            return
        }

        ///Return if module map is already present
        guard !moduleMapPath.asString.isFile else {
            return
        }
        
        let includeDir = path
        
        // Warn and return if no include directory.
        guard includeDir.asString.isDirectory else {
            print("warning: No include directory found for module '\(name)'. A library can not be imported without any public headers.")
            return
        }
        
        let walked = try localFileSystem.getDirectoryContents(includeDir).map{ includeDir.appending(component: $0) }
        
        let files = walked.filter{ $0.asString.isFile && $0.suffix == ".h" }
        let dirs = walked.filter{ $0.asString.isDirectory }

        // We generate modulemap for a C module `foo` if:
        // * `umbrella header "path/to/include/foo/foo.h"` exists and `foo` is the only
        //    directory under include directory
        // * `umbrella header "path/to/include/foo.h"` exists and include contains no other
        //    directory
        // * `umbrella "path/to/include"` in all other cases

        let umbrellaHeaderFlat = includeDir.appending(component: c99name + ".h")
        if umbrellaHeaderFlat.asString.isFile {
            guard dirs.isEmpty else { throw ModuleMapError.unsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeaderFlat), modulemapStyle: modulemapStyle)
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir)

        let umbrellaHeader = includeDir.appending(components: c99name, c99name + ".h")
        if umbrellaHeader.asString.isFile {
            guard dirs.count == 1 && files.isEmpty else { throw ModuleMapError.unsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .header(umbrellaHeader), modulemapStyle: modulemapStyle)
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir.appending(component: c99name))

        try createModuleMap(inDir: wd, type: .directory(includeDir), modulemapStyle: modulemapStyle)
    }

    /// Warn user if in case module name and c99name are different and there is a
    /// `name.h` umbrella header.
    private func diagnoseInvalidUmbrellaHeader(_ path: AbsolutePath) {
        let umbrellaHeader = path.appending(component: c99name + ".h")
        let invalidUmbrellaHeader = path.appending(component: name + ".h")
        if c99name != name && invalidUmbrellaHeader.asString.isFile {
            print("warning: \(invalidUmbrellaHeader) should be renamed to \(umbrellaHeader) to be used as an umbrella header")
        }
    }

    private enum UmbrellaType {
        case header(AbsolutePath)
        case directory(AbsolutePath)
    }
    
    private func createModuleMap(inDir wd: AbsolutePath, type: UmbrellaType, modulemapStyle: ModuleMapStyle) throws {
        try makeDirectories(wd)
        let moduleMapFile = wd.appending(component: CModule.moduleMapFilename)
        let moduleMap = try fopen(moduleMapFile.asString, mode: .write)
        defer { moduleMap.closeFile() }
        
        var output = ""
        if let qualifier = modulemapStyle.moduleDeclQualifier {
            output += qualifier + " "
        }
        output += "module \(c99name) {\n"
        switch type {
        case .header(let header):
            output += "    umbrella header \"\(header.asString)\"\n"
        case .directory(let path):
            output += "    umbrella \"\(path.asString)\"\n"
        }
        output += "    \(modulemapStyle.linkDeclFlag) \"\(c99name)\"\n"
        output += "    export *\n"
        output += "}\n"

        try fputs(output, moduleMap)
    }
}
