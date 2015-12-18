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
        let excludedirs = manifest.package.exclude.map { Path.join(rootd, $0) }

        let depsdir = Path.join(rootd, "Packages")
        let computedTargets = try determineTargets(packageName: pkgname, prefix: rootd, ignore: [depsdir] + excludedirs)

        let targets = try manifest.configureTargets(computedTargets)
        let dependencies = try get(manifest.package.dependencies, prefix: depsdir)
        let builddir = Path.join(getenv("SWIFT_BUILD_PATH") ?? Path.join(rootd, ".build"), configuration.dirname)

        // build dependencies
        for pkg in dependencies {
            // pass only the dependencies of this package
            // we have to map them from PackageDescription.Package to dep.Package
            let manifest = try Manifest(path: Path.join(pkg.path, "Package.swift"), baseURL: pkg.url)  //TODO cache
            let dependencies = manifest.package.dependencies.map { dd -> Package in
                for d in dependencies where d.url == dd.url { return d }
                fatalError("Could not find dependency for \(dd)")
            }
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: dependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkg.name).o"), configuration: configuration)
        }

        let testDependencies = try get(manifest.package.testDependencies, prefix: depsdir)
        for pkg in testDependencies {
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: testDependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkg.name).o"), configuration: configuration)
        }

        do {
            // build the current directory
            try llbuild(srcroot: rootd, targets: targets, dependencies: dependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkgname).o"), configuration: configuration)
        } catch POSIX.Error.ExitStatus(let foo) {
#if os(Linux)
            // it is a common error on Linux for clang++ to not be installed, but
            // we need it for linking. swiftc itself gives a non-useful error, so
            // we try to help here.

            //TODO really we should figure out if clang++ is installed in a better way
            // however, since this is an error path, the performance implications are
            // less severe, so it will do for now.

            if (try? popen(["clang++", "--version"], redirectStandardError: true)) == nil {
                print("warning: clang++ not found: this will cause build failure", toStream: &stderr)
            }
#endif
            throw POSIX.Error.ExitStatus(foo)
        }


    case .Version:
        print("Apple Swift Package Manager 0.1")
    }

} catch CommandLineError.InvalidUsage(let hint, let mode) {

    print("Invalid usage:", hint, toStream: &stderr)

    if attachedToTerminal() {
        switch mode {
        case .Imply:
            print("Enter `swift build --help' for usage information.", toStream: &stderr)
        case .Print:
            print("", toStream: &stderr)
            usage { print($0, toStream: &stderr) }
        }
    }

    exit(1)

} catch {
    print("swift-build:", red(error), toStream: &stderr)
    exit(1)
}
