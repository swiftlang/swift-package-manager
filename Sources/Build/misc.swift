/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import PackageModel

import func POSIX.getenv
import func POSIX.popen

public protocol Toolchain {
    var platformArgsClang: [String] { get }
    var platformArgsSwiftc: [String] { get }
    var sysroot: String?  { get }
    var SWIFT_EXEC: String { get }
    var swift: String { get }
    var clang: String { get }
}

extension String {
    var isCpp: Bool {
        guard let ext = self.fileExt else {
            return false
        }
        return SupportedLanguageExtension.cppExtensions.contains(ext)
    }
}

extension ClangModule {
    // Returns language specific arguments for a ClangModule.
    var languageLinkArgs: [String] {
        var args = [String]() 
        // Check if this module contains any cpp file.
        var linkCpp = self.containsCppFiles

        // Otherwise check if any of its dependencies contains a cpp file.
        // FIXME: It is expensive to iterate over all of the dependencies.
        // Figure out a way to cache this kind of lookups.
        if !linkCpp {
            for case let dep as ClangModule in recursiveDependencies {
                if dep.containsCppFiles {
                    linkCpp = true
                    break
                }
            }
        }
        // Link C++ if found any cpp source. 
        if linkCpp {
            args += ["-lc++"]
        }
        return args
    }

    var containsCppFiles: Bool {
        return sources.paths.contains { $0.isCpp } 
    }
}

extension Product {
    /// Returns true iff all the modules in this product are ClangModules. 
    var containsOnlyClangModules: Bool {
        return modules.filter{ $0 is ClangModule }.count == modules.count
    }

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
            if case .darwin = platform  {
                return true
            }
        case .Apt(_):
            if case .linux(.debian) = platform  {
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
