/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import func POSIX.popen
import func POSIX.mkdir
import func POSIX.fopen
import func libc.fclose
import PackageType
import Utility

public protocol Toolchain {
    var platformArgs: [String] { get }
    var sysroot: String?  { get }
    var SWIFT_EXEC: String { get }
    var clang: String { get }
}

func platformFrameworksPath() throws -> String {
    guard let  popened = try? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"]),
        let chuzzled = popened.chuzzle() else {
            throw Error.InvalidPlatformPath
    }
    return Path.join(chuzzled, "Developer/Library/Frameworks")
}

extension CModule {
    
    var moduleMap: String {
        return "module.modulemap"
    }
    
    var moduleMapPath: String {
        return Path.join(path, moduleMap)
    }
}

extension ClangModule {
    
    public enum ModuleMapError: ErrorProtocol {
        case UnsupportedIncludeLayoutForModule(String)
    }
    
    public func generateModuleMap(inDir wd: String) throws {
        
        //Return if module map is already present
        guard !moduleMapPath.isFile else {
            return
        }
        
        let includeDir = path
        
        //Warn and return if no include directory
        guard includeDir.isDirectory else {
            print("warning: No include directory found, a library can not be imported without any public headers.")
            return
        }
        
        let walked = walk(includeDir, recursively: false).map{$0}
        
        let files = walked.filter{$0.isFile && $0.hasSuffix(".h")}
        let dirs = walked.filter{$0.isDirectory}
        
        if dirs.isEmpty {
            guard !files.isEmpty else { throw ModuleMapError.UnsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .FlatHeaderLayout)
            return
        }
        
        guard let moduleHeaderDir = dirs.first where moduleHeaderDir.basename == name && files.isEmpty else {
            throw ModuleMapError.UnsupportedIncludeLayoutForModule(name)
        }
        
        let umbrellaHeader = Path.join(moduleHeaderDir, "\(name).h")
        if umbrellaHeader.isFile {
            try createModuleMap(inDir: wd, type: .HeaderFile)
        } else {
            try createModuleMap(inDir: wd, type: .ModuleNameDir)
        }
    }
    
    private enum UmbrellaType {
        case FlatHeaderLayout
        case ModuleNameDir
        case HeaderFile
    }
    
    private func createModuleMap(inDir wd: String, type: UmbrellaType) throws {
        try POSIX.mkdir(wd)
        let moduleMapFile = Path.join(wd, self.moduleMap)
        let moduleMap = try fopen(moduleMapFile, mode: .Write)
        defer { fclose(moduleMap) }
        
        try fputs("module \(name) {\n", moduleMap)
        try fputs("    umbrella ", moduleMap)
        
        switch type {
        case .FlatHeaderLayout:
            try fputs("\"\(path)\"\n", moduleMap)
        case .ModuleNameDir:
            let path = Path.join(self.path, name)
            try fputs("\"\(path)\"\n", moduleMap)
        case .HeaderFile:
            let path = Path.join(self.path, name, "\(name).h")
            try fputs("header \"\(path)\"\n", moduleMap)
            
        }
        
        try fputs("    link \"\(name)\"\n", moduleMap)
        try fputs("    export *\n", moduleMap)
        try fputs("}\n", moduleMap)
    }
}

extension Product {
    var Info: (_: Void, plist: String) {
        precondition(isTest)

        let bundleExecutable = name
        let bundleID = "org.swift.pm.\(name)"
        let bundleName = name

        var s = ""
        s += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        s += "<plist version=\"1.0\">\n"
        s += "<dict>\n"
        s += "<key>CFBundleDevelopmentRegion</key>\n"
        s += "<string>en</string>\n"
        s += "<key>CFBundleExecutable</key>\n"
        s += "<string>\(bundleExecutable)</string>\n"
        s += "<key>CFBundleIdentifier</key>\n"
        s += "<string>\(bundleID)</string>\n"
        s += "<key>CFBundleInfoDictionaryVersion</key>\n"
        s += "<string>6.0</string>\n"
        s += "<key>CFBundleName</key>\n"
        s += "<string>\(bundleName)</string>\n"
        s += "<key>CFBundlePackageType</key>\n"
        s += "<string>BNDL</string>\n"
        s += "<key>CFBundleShortVersionString</key>\n"
        s += "<string>1.0</string>\n"
        s += "<key>CFBundleSignature</key>\n"
        s += "<string>????</string>\n"
        s += "<key>CFBundleSupportedPlatforms</key>\n"
        s += "<array>\n"
        s += "<string>MacOSX</string>\n"
        s += "</array>\n"
        s += "<key>CFBundleVersion</key>\n"
        s += "<string>1</string>\n"
        s += "</dict>\n"
        s += "</plist>\n"
        return ((), plist: s)
    }
}
