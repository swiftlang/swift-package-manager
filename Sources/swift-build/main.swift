/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Build
import Get
import Multitool
import PackageLoading
import PackageModel
import Utility
#if HasCustomVersionString
import VersionInfo
#endif
import Xcodeproj

import func POSIX.getcwd
import func POSIX.getenv
import func POSIX.unlink
import func POSIX.chdir
import func POSIX.rmdir
import func libc.exit

/// Declare additional conformance for our Options type.
extension Options: XcodeprojOptions {}

do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    verbosity = Verbosity(rawValue: opts.verbosity)
    colorMode = opts.colorMode

    if let dir = opts.chdir {
        try chdir(dir)
    }

    func parseManifest(path: String, baseURL: String) throws -> Manifest {
        let swiftc = Multitool.SWIFT_EXEC
        let libdir = Multitool.libdir
        return try Manifest(path: path, baseURL: baseURL, swiftc: swiftc, libdir: libdir)
    }
    
    func fetch(_ root: String) throws -> (rootPackage: Package, externalPackages:[Package]) {
        let manifest = try parseManifest(path: root, baseURL: root)
        if opts.ignoreDependencies {
            return (Package(manifest: manifest, url: manifest.path.parentDirectory), [])
        } else {
            return try get(manifest, manifestParser: parseManifest)
        }
    }

    switch mode {
    case .Build(let conf, let toolchain):
        let (rootPackage, externalPackages) = try fetch(opts.path.root)
        try generateVersionData(opts.path.root, rootPackage: rootPackage, externalPackages: externalPackages)
        let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
        let yaml = try describe(opts.path.build, conf, modules, Set(externalModules), products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc, toolchain: toolchain)
        try build(YAMLPath: yaml, target: opts.buildTests ? "test" : nil)

    case .Init(let initMode):
        let initPackage = try InitPackage(mode: initMode)
        try initPackage.writePackageStructure()
                    
    case .Update:
        try rmtree(opts.path.Packages)
        fallthrough
        
    case .Fetch:
        _ = try fetch(opts.path.root)

    case .Usage:
        usage()

    case .Clean(.Dist):
        if opts.path.Packages.exists {
            try rmtree(opts.path.Packages)
        }
        fallthrough

    case .Clean(.Build):
        let artifacts = ["debug", "release"].map{ Path.join(opts.path.build, $0) }.map{ ($0, "\($0).yaml") }
        for (dir, yml) in artifacts {
            if dir.isDirectory { try rmtree(dir) }
            if yml.isFile { try unlink(yml) }
        }

        let db = Path.join(opts.path.build, "build.db")
        if db.isFile { try unlink(db) }

        let versionData = Path.join(opts.path.build, "versionData")
        if versionData.isDirectory { try rmtree(versionData) }

        if opts.path.build.exists {
            try rmdir(opts.path.build)
        }

    case .Doctor:
        doctor()
    
    case .ShowDependencies(let mode):
        let (rootPackage, externalPackages) = try fetch(opts.path.root)
        dumpDependenciesOf(rootPackage: rootPackage, mode: mode)

    case .Version:
        #if HasCustomVersionString
            print(String(cString: VersionInfo.DisplayString()))
        #else
            print("Apple Swift Package Manager 0.1")
        #endif
        
    case .GenerateXcodeproj(let outpath):
        let (rootPackage, externalPackages) = try fetch(opts.path.root)
        let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
        
        let xcodeModules = modules.flatMap { $0 as? XcodeModuleProtocol }
        let externalXcodeModules  = externalModules.flatMap { $0 as? XcodeModuleProtocol }

        let projectName: String
        let dstdir: String
        let packageName = rootPackage.name

        switch outpath {
        case let outpath? where outpath.hasSuffix(".xcodeproj"):
            // if user specified path ending with .xcodeproj, use that
            projectName = String(outpath.basename.characters.dropLast(10))
            dstdir = outpath.parentDirectory
        case let outpath?:
            dstdir = outpath
            projectName = packageName
        case _:
            dstdir = opts.path.root
            projectName = packageName
        }
        let outpath = try Xcodeproj.generate(dstdir: dstdir.abspath, projectName: projectName, srcroot: opts.path.root, modules: xcodeModules, externalModules: externalXcodeModules, products: products, options: opts)

        print("generated:", outpath.prettyPath)
        
    case .DumpPackage(let packagePath):
        
        let root = packagePath ?? opts.path.root
        let manifest = try parseManifest(path: root, baseURL: root)
        let package = manifest.package
        let json = try jsonString(package: package)
        print(json)
    }

} catch {
    handle(error: error, usage: usage)
}
