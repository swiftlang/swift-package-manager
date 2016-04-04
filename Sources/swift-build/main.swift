/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getcwd
import func POSIX.getenv
import func POSIX.unlink
import func POSIX.chdir
import func POSIX.rmdir
import func libc.exit
import ManifestParser
import PackageType
import Multitool
import Transmute
import Xcodeproj
import Utility
import Build
import Get

do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    verbosity = Verbosity(rawValue: opts.verbosity)

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
        return try get(manifest, manifestParser: parseManifest)
    }

    switch mode {
    case .Build(let conf, let toolchain):
        let dirs = try directories()
        let (rootPackage, externalPackages) = try fetch(dirs.root)
        try generateVersionData(dirs.root, rootPackage: rootPackage, externalPackages: externalPackages)
        let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
        let yaml = try describe(dirs.build, conf, modules, Set(externalModules), products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc, toolchain: toolchain)
        try build(YAMLPath: yaml)

    case .Init(let initMode):
        let initPackage = InitPackage(mode: initMode)
        try initPackage.writePackageStructure()
                    
    case .Fetch:
        try fetch(try directories().root)

    case .Usage:
        usage()

    case .Clean(let mode):
        let dirs = try directories()

        switch mode {
        case .Dist:
            try rmtree(dirs.Packages)
            fallthrough

        case .Build:
            let artifacts = ["debug", "release"].map{ Path.join(dirs.build, $0) }.map{ ($0, "\($0).yaml") }
            for (dir, yml) in artifacts {
                if dir.isDirectory { try rmtree(dir) }
                if yml.isFile { try unlink(yml) }
            }

            let db = Path.join(dirs.build, "build.db")
            if db.isFile { try unlink(db) }

            try rmdir(dirs.build)
        }

    case .Doctor:
        doctor()

    case .Version:
        print("Apple Swift Package Manager 0.1")
        
    case .GenerateXcodeproj(let outpath):
        let dirs = try directories()
        let (rootPackage, externalPackages) = try fetch(dirs.root)
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
            dstdir = dirs.root
            projectName = packageName
        }
        let outpath = try Xcodeproj.generate(dstdir: dstdir, projectName: projectName, srcroot: dirs.root, modules: xcodeModules, externalModules: externalXcodeModules, products: products, options: (Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc))

        print("generated:", outpath.prettyPath)
    }

} catch {
    handle(error: error, usage: usage)
}
