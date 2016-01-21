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

import func libc.fileno
import var libc.stdin
import var libc.stderr
import var sys.stderr


// Initialize the resource support.
public var globalSymbolInMainBinary = 0
Resources.initialize(&globalSymbolInMainBinary)

do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    sys.verbosity = Verbosity(rawValue: opts.verbosity)

    if let dir = opts.chdir {
        try chdir(dir)
    }

    // keep the working directory around for the duration of our process
    try opendir(".")

    switch mode {
    case .Usage:
        usage()

    case .Clean(let cleanMode):
        if case .Dist = cleanMode {
            try rmtree(try findSourceRoot(), "Packages")
        }
        try rmtree(try findSourceRoot(), ".build")

    case .Build(let configuration):
        let rootd = try findSourceRoot()
        let manifest = try Manifest(path: "\(rootd)/Package.swift", baseURL: rootd)
        let pkgname = manifest.package.name ?? rootd.basename
        let excludedirs = manifest.package.exclude.map { Path.join(rootd, $0) }

        let depsdir = Path.join(rootd, "Packages")
        let computedTargets = try determineTargets(packageName: pkgname, prefix: rootd, ignore: [depsdir] + excludedirs)

        let targets = try manifest.configureTargets(computedTargets)
        let builddir = Path.join(getenv("SWIFT_BUILD_PATH") ?? Path.join(rootd, ".build"), configuration.dirname)

        guard targets.count > 0 else {
            throw Error.NoTargetsFound
        }

        func llbuild(srcroot srcroot: String, targets: [Target], dependencies: [Package], prefix: String, tmpdir: String, configuration: BuildParameters.Configuration) throws {
            try dep.llbuild(srcroot: srcroot, targets: targets, dependencies: dependencies, prefix: prefix, tmpdir: tmpdir, configuration: configuration, Xcc: opts.Xcc, Xlinker: opts.Xlinker)
        }

        func build(dependencies: [Package]) throws {
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
        }

        do {
            let dependencies = try get(manifest.package.dependencies, prefix: depsdir)
            
            if opts.pull == false {
                try build(dependencies)
                try build(try get(manifest.package.testDependencies, prefix: depsdir))

                // build the current directory
                try llbuild(srcroot: rootd, targets: targets, dependencies: dependencies, prefix: builddir, tmpdir: Path.join(builddir, "\(pkgname).o"), configuration: configuration)
            }
        } catch POSIX.Error.ExitStatus(let foo) {
#if os(Linux)
            // it is a common error on Linux for clang++ to not be installed, but
            // we need it for linking. swiftc itself gives a non-useful error, so
            // we try to help here.
            //FIXME using which is non-ideal: it may not be available

            if (try? sys.popen(["which", "clang++"])) == nil {
                print("warning: clang++ not found: this will cause build failure", toStream: &stderr)
            }
#endif
            throw POSIX.Error.ExitStatus(foo)
        }


    case .Version:
        print("Apple Swift Package Manager 0.1")
    }

} catch CommandLineError.InvalidUsage(let hint, let mode) {

    print("error: invalid usage:", hint, toStream: &stderr)

    if isatty(fileno(libc.stdin)) {
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

    func red(input: Any) -> String {
        let input = "\(input)"
        let ESC = "\u{001B}"
        let CSI = "\(ESC)["
        return CSI + "31m" + input + CSI + "0m"
    }

    if !isatty(fileno(libc.stderr)) {
        print("swift-build: error:", error, toStream: &stderr)
    } else {
        print(red("error:"), error, toStream: &stderr)
    }

    exit(1)
}
