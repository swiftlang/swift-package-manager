/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import func POSIX.chdir
import func libc.exit
import ManifestParser
import PackageType
import Multitool
import Transmute
import Utility
import Build
import Get


// Initialize the resource support.
public var globalSymbolInMainBinary = 0
Resources.initialize(&globalSymbolInMainBinary)


do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    verbosity = Verbosity(rawValue: opts.verbosity)

    if let dir = opts.chdir {
        try chdir(dir)
    }
    
    func fetch(root: String) throws -> [Package] {
        let manifest = try Manifest(path: root, Manifest.filename, baseURL: root)
        return try get(manifest)
    }

    switch mode {
        case .Build(let conf):
            let dirs = try directories()
            let packages = try fetch(dirs.root)
            let (modules, products) = try transmute(packages)
            let yaml = try describe(dirs.build, conf, modules, products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc)
            try build(YAMLPath: yaml, target: "default")

        case .Init(let initMode):
            let initPackage = try InitPackage(mode: initMode)
            try initPackage.writePackageStructure()
                        
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
            print("Apple Swift Package Manager 0.1")
    }

} catch {
    handleError(error, usage: usage)
}
