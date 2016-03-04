/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getcwd
import func POSIX.getenv
import func POSIX.chdir
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
    
    func parseManifest(path path: String, baseURL: String) throws -> Manifest {
        let bindir = try! Process.arguments.first!.parentDirectory.abspath()
        let libdir: String
        if Path.join(bindir, "PackageDescription.swiftmodule").isDirectory { //FIXME HACK
            libdir = bindir
        } else {
            libdir = try! Path.join(bindir, "../lib/swift/pm").abspath()
        }
        return try Manifest(path: path, baseURL: baseURL, swiftc: Toolchain.swiftc, libdir: libdir)
    }
    
    func fetch(root: String) throws -> [Package] {
        let manifest = try parseManifest(path: root, baseURL: root)
        return try get(manifest, manifestParser: parseManifest)
    }

    switch mode {
    case .Build(let conf):
        let dirs = try directories()
        let packages = try fetch(dirs.root)
        let (modules, products) = try transmute(packages)
        let yaml = try describe(dirs.build, conf, modules, products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc)
        try build(YAMLPath: yaml, target: "default")

    case .Init:
        try initPackage()
        
    case .Fetch:
        try fetch(try directories().root)

    case .Usage:
        usage()

    case .Clean(.Dist):
        try rmtree(try directories().root, "Packages")
        fallthrough
    case .Clean(.Build):
        try rmtree(try directories().root, ".build")

    case .Version:
        Swift.print("Apple Swift Package Manager 0.1")

    case .Dump:
        let dirs = try directories()
        let packages = try fetch(dirs.root)
        let (modules, products) = try transmute(packages)
        let swiftModules = modules.flatMap{ $0 as? SwiftModule }

        try Xcodeproj.create(path: try getcwd(), package: packages.last!, modules: swiftModules, products: products)
    }

} catch {
    handleError(error, usage: usage)
}
