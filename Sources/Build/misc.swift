/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import func POSIX.popen
import PackageType
import Utility

public protocol Toolchain {
    var platformArgs: [String] { get }
    var sysroot: String?  { get }
    var SWIFT_EXEC: String { get }
    var clang: String { get }
}

func platformFrameworksPath() throws -> String {
    // Lazily compute the platform the first time it is needed.
    struct Static {
        static let value = { try? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"]) }()
    }
    guard let popened = Static.value, let chuzzled = popened.chuzzle() else {
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
    
    ///FIXME: we recompute the generated modulemap's path
    ///when building swift modules in `XccFlags(prefix: String)`
    ///there shouldn't be need to redo this there but is difficult 
    ///in current architecture
    public func generateModuleMap(inDir wd: String) throws {
        
        ///Return if module map is already present
        guard !moduleMapPath.isFile else {
            return
        }
        
        let includeDir = path
        
        ///Warn and return if no include directory
        guard includeDir.isDirectory else {
            print("warning: No include directory found, a library can not be imported without any public headers.")
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
            guard dirs.isEmpty else { throw ModuleMapError.UnsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .Header(umbrellaHeaderFlat))
            return
        }
        diagnoseInvalidUmbrellaHeader(includeDir)

        let umbrellaHeader = Path.join(includeDir, c99name, "\(c99name).h")
        if umbrellaHeader.isFile {
            guard dirs.count == 1 && files.isEmpty else { throw ModuleMapError.UnsupportedIncludeLayoutForModule(name) }
            try createModuleMap(inDir: wd, type: .Header(umbrellaHeader))
            return
        }
        diagnoseInvalidUmbrellaHeader(Path.join(includeDir, c99name))

        try createModuleMap(inDir: wd, type: .Directory(includeDir))
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
        case Header(String)
        case Directory(String)
    }
    
    private func createModuleMap(inDir wd: String, type: UmbrellaType) throws {
        try Utility.mkdir(wd)
        let moduleMapFile = Path.join(wd, self.moduleMap)
        let moduleMap = try fopen(moduleMapFile, mode: .Write)
        defer { moduleMap.closeFile() }
        
        var output = "module \(c99name) {\n"
        switch type {
        case .Header(let header):
            output += "    umbrella header \"\(header)\"\n"
        case .Directory(let path):
            output += "    umbrella \"\(path)\"\n"
        }
        output += "    link \"\(c99name)\"\n"
        output += "    export *\n"
        output += "}\n"

        try fputs(output, moduleMap)
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

extension SystemPackageProvider {
    
    var installText: String {
        switch self {
        case .Brew(let name):
            return "    brew install \(name)\n"
        case .Apt(let name):
            return "    apt-get install \(name)\n"
        }
    }
    
    var isAvailable: Bool {
        guard let platform = Platform.currentPlatform else { return false }
        switch self {
        case .Brew(_):
            if case .Darwin = platform  {
                return true
            }
        case .Apt(_):
            if case .Linux(.Debian) = platform  {
                return true
            }
        }
        return false
    }
    
    static func providerForCurrentPlatform(providers: [SystemPackageProvider]) -> SystemPackageProvider? {
        return providers.filter{ $0.isAvailable }.first
    }
}

protocol ClangModuleCachable {
    func moduleCacheArgs(prefix: String) -> [String]
}

extension ClangModuleCachable {
    func moduleCacheDir(prefix: String) -> String {
        return Path.join(prefix, "ModuleCache")
    }
}

extension ClangModule: ClangModuleCachable {
    func moduleCacheArgs(prefix: String) -> [String] {
        // FIXME: We use this hack to let swiftpm's functional test use shared cache
        // so it doesn't become painfully slow.
        if let _ = getenv("IS_SWIFTPM_TEST") { return [] }
        let moduleCachePath = moduleCacheDir(prefix: prefix)
        return ["-fmodules-cache-path=\(moduleCachePath)"]
    }
}

extension SwiftModule: ClangModuleCachable {
    func moduleCacheArgs(prefix: String) -> [String] {
        // FIXME: We use this hack to let swiftpm's functional test use shared cache
        // so it doesn't become painfully slow.
        if let _ = getenv("IS_SWIFTPM_TEST") { return [] }
        let moduleCachePath = moduleCacheDir(prefix: prefix)
        return ["-module-cache-path", moduleCachePath]
    }
}
