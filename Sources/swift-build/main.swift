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
    let args = Array(Process.arguments.dropFirst())
    let (mode, chdir, verbosity) = try parse(commandLineArguments: args)

    sys.verbosity = Verbosity(rawValue: verbosity)

    if let dir = chdir {
        try POSIX.chdir(dir)
    }

    // keep the working directory around for the duration of our process
    try opendir(".")

    switch mode {
    case .Usage:
        usage()

    case .Clean:
        try rmtree(try findSourceRoot(), ".build")

    case .Build(let configuration):
        let rootd = try findSourceRoot()
        let manifest = try Manifest(path: "\(rootd)/Package.swift", baseURL: rootd)
        let pkgname = manifest.package.name ?? rootd.basename
        let depsdir = Path.join(rootd, "Packages")
        let computedTargets = try determineTargets(packageName: pkgname, prefix: rootd, ignore: [depsdir])
        let targets = try manifest.configureTargets(computedTargets)
        let dependencies = try get(manifest.package.dependencies, prefix: depsdir)
        let builddir = Path.join(getenv("SWIFT_BUILD_PATH") ?? Path.join(rootd, ".build"), configuration.dirname)

        for pkg in dependencies {
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: dependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkg.name).o"), configuration: configuration)
        }

        // build the current directory
        try llbuild(srcroot: rootd, targets: targets, dependencies: dependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkgname).o"), configuration: configuration)

    case .Version:
        print("Apple Swift Package Manager 0.1")
    }

} catch CommandLineError.InvalidUsage(let hint, let mode) {

    print("Invalid usage: \(hint)", toStream: &stderr)

    if attachedToTerminal() {
        switch mode {
        case .Imply:
            print("Enter `swift build --help` for usage information.", toStream: &stderr)
        case .Print:
            print("", toStream: &stderr)
            usage { print($0, toStream: &stderr) }
        }
    }

    exit(1)

} catch {
    print("swift-build:", error, toStream: &stderr)
    exit(1)
}
