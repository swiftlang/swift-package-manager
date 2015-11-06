/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import dep
import POSIX
import sys

// Initialize the resource support.
public var globalSymbolInMainBinary = 0
Resources.initialize(&globalSymbolInMainBinary)

do {
    switch try CommandLine.parse() {
    case .Usage:
        print("swift build [--chdir DIRECTORY]")
        print("swift build --clean")

    case .Clean:
        try rmtree(try findSourceRoot(), ".build")

    case .Build(let dir):
        if let dir = dir {
            try chdir(dir)
        }

        let rootd = try findSourceRoot()
        let manifest = try Manifest(path: "\(rootd)/Package.swift", baseURL: rootd)
        let pkgname = manifest.package.name ?? rootd.basename
        let computedTargets = try determineTargets(packageName: pkgname, prefix: rootd, ignore: ["\(rootd)/deps"])
        let targets = try manifest.configureTargets(computedTargets)
        let dependencies = try get(manifest.package.dependencies, prefix: rootd)
        let builddir = getenv("SWIFT_BUILD_PATH") ?? Path.join(rootd, ".build")

        for pkg in dependencies {
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: dependencies, prefix: Path.join(builddir, pkg.name), tmpdir: Path.join(builddir, pkg.name, "o"))
        }

        // build the current directory
        try llbuild(srcroot: rootd, targets: targets, dependencies: dependencies, prefix: Path.join(builddir, "debug"), tmpdir: Path.join(builddir, "debug/o"))
    }

} catch {
    print("swift build:", error, toStream: &stderr)
    exit(1)
}
