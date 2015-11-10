/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.fclose
import PackageDescription
import POSIX
import sys

public struct BuildConfiguration {
    public init() {
        srcroot = ""
        targets = []
        dependencies = []
    }

    public var srcroot: String
    public var targets: [Target]
    public var dependencies: [Package]

    public var prefix: String = ""
    public var tmpdir: String = ""

    private func requiredSubdirectories() -> [String] {
        return targets.flatMap { target in
            return target.sources.map { Path(components: $0, "..").relative(to: self.srcroot) }
        } + [prefix]
    }
}

public func llbuild(srcroot srcroot: String, targets: [Target], dependencies: [Package], prefix: String, tmpdir: String) throws -> BuildConfiguration {
    var conf = BuildConfiguration()
    conf.srcroot = srcroot
    conf.targets = targets
    conf.dependencies = dependencies
    conf.prefix = prefix
    conf.tmpdir = tmpdir
    try llbuild(conf)
    return conf
}

public func llbuild(conf: BuildConfiguration) throws {
    for subdir in conf.requiredSubdirectories() {
        try mkdir(conf.tmpdir, subdir)
    }

    let yaml = try YAML(buildConfiguration: conf)
    try yaml.write()

    let toolPath = getenv("SWIFT_BUILD_TOOL") ?? Resources.findExecutable("swift-build-tool")
    var args = [toolPath]
    if sys.verbosity != .Concise {
        args.append("-v")
    }
    args += ["-f", yaml.filename]
    try system(args)
}

private class YAML {
    let conf: BuildConfiguration
    var f: UnsafeMutablePointer<FILE>
    let filename: String

    init(buildConfiguration: BuildConfiguration) throws {
        self.conf = buildConfiguration
        let path = Path.join(buildConfiguration.tmpdir, "llbuild.yaml")
        self.filename = path
        do {
            self.f = try fopen(path, mode: "w")
        } catch {
            self.f = nil
            throw error
        }
    }

    deinit {
        if f != nil {
            fclose(f)
        }
    }

    func targetsString() -> String { return conf.targets.map{$0.targetNode}.joinWithSeparator(", ") }

    func print(s: String = "") throws {
        try fputs(s, f)
        try fputs("\n", f)
    }

    /**
      Get the 'swiftc' executable path to use.
      FIXME: We eventually will need to locate this relative to ourselves.
    */
    var swiftcPath: String {
        return getenv("SWIFTC") ?? Resources.findExecutable("swiftc")
    }

    /// Get the sysroot option, used by the bootstrap script.
    var sysroot: String? {
        return getenv("SYSROOT")
    }

    func write() throws {
        try print("client:")
        try print("  name: swift-build")
        try print()

        try print("tools: {}")
        try print()

        try print("targets:")
        try print("  \"\": [\(targetsString())]")
        for target in conf.targets {
            try print("  \(target.productName): [\(target.targetNode)]")
        }
        try print()

        try print("commands:")

        for target in conf.targets {
            try writeCompileNode(target)
            try writeLinkNode(target)
        }

        fclose(f)
        f = nil
    }


    func ofiles(target: Target) -> [String] {
        return target.sources.map { srcfile -> String in
            let tip = Path(srcfile).relative(to: conf.srcroot)
            return Path.join(conf.tmpdir, "\(tip).o")
        }
    }

    func writeCompileNode(target: Target) throws {
        let importPaths = conf.dependencies.flatMap{ $0.path } + [conf.prefix]
        let prodpath = Path.join(conf.tmpdir, target.productName)
        let modulepath = Path.join(conf.prefix, "\(target.moduleName).swiftmodule")
        let sources = target.sources.chuzzle()?.joinWithSeparator(" ") ?? "\"\""
        let objects = ofiles(target).chuzzle()?.joinWithSeparator(" ") ?? "\"\""
        let inputs = (target.dependencies.map{"<\($0.productName)>"} + target.sources.map(quote)).joinWithSeparator(", ")
        let outputs = (["<\(target.productName)-swiftc>", modulepath] + ofiles(target).map(quote)).joinWithSeparator(", ")

        func args() -> String {
            var args = "-Onone -g"
            args += " -j8" //TODO
          #if os(OSX)
            args += " -target x86_64-apple-macosx10.10 "
          #endif
            if target.type == .Library {
                args += " -enable-testing"
            }
            if sysroot != nil {
                args += " -sdk \(quote(sysroot!))"
            }
            return args
        }

        try print("  <\(target.productName)-swiftc>:")
        try print("    tool: swift-compiler")
        try print("    executable: \(quote(swiftcPath))")
        try print("    inputs: [\(inputs)]")
        try print("    outputs: [\(outputs)]")
        try print("    module-name: \(target.moduleName)")
        try print("    module-output-path: \(modulepath)")
        try print("    is-library: \(target.type == .Library)")
        try print("    sources: \(sources)")
        try print("    objects: \(objects)")
        try print("    import-paths: \(importPaths.joinWithSeparator(" "))")
        try print("    temps-path: \(prodpath)")
        try print("    other-args: \(args())")
    }

    func writeLinkNode(target: Target) throws {
        let inputs = (["<\(target.productName)-swiftc>"] + ofiles(target).map(quote)).joinWithSeparator(", ")
        let objectargs = ofiles(target).map(quote).joinWithSeparator(" ")
        let productPath = Path.join(conf.prefix, target.productFilename)

        func args() throws -> String {
            switch target.type {
            case .Library:
                return "rm -f \(quote(productPath)); env ZERO_AR_DATE=1 ar cr \(quote(productPath)) \(objectargs)"
            case .Executable:
                var args = ""
                args += "\(swiftcPath) -o \(quote(productPath)) \(objectargs) "
#if os(OSX)
                args += "-Xlinker -all_load "
                args += "-target x86_64-apple-macosx10.10 "
#endif

                // We support a custom override in conjunction with the
                // bootstrap script to allow embedding an appropriate RPATH for
                // the package manager tools themselves on Linux, so they can be
                // relocated with the Swift compiler.
                if let rpathValue = getenv("SWIFTPM_EMBED_RPATH") {
                    args += "-Xlinker -rpath=\(rpathValue) "
                }

                if sysroot != nil {
                    args += "-sdk \(quote(sysroot!)) "
                }

                let libsInOtherPackages = try conf.dependencies.flatMap { pkg -> [String] in
                    return try pkg.targets()
                        .filter{ $0.type == .Library }
                        .map{ $0.productFilename }
                        .map{ Path.join(pkg.path, $0) }
                }

                let libsInThisPackage = target.dependencies
                    .filter{ $0.type == .Library }
                    .map{ $0.productFilename }
                    .map{ Path.join(conf.prefix, $0) }

                // Add the static libraries of our dependencies.
                //
                // We currently pass this with -Xlinker because the 'swift-autolink-extract' tool does not understand how to work with archives (<rdar://problem/23045632>).
                args += (libsInThisPackage + libsInOtherPackages).flatMap{ ["-Xlinker", quote($0)] }.joinWithSeparator(" ")

                return args
            }
        }

        let relativeProductPath = Path(productPath).relative(to: (try? getcwd()) ?? "/")
        let description = "Linking \(target.type):  \(relativeProductPath)"

        try print("  \(target.targetNode):")
        try print("    tool: shell")
        try print("    inputs: [\(inputs)]")
        try print("    outputs: [\(target.targetNode), \(quote(productPath))]")
        try print("    args: \(args())")
        try print("    description: \"\(description)\"")
    }
}

private func quote(input: String) -> String {
    return "\"\(input)\""
}

private extension Target {
    /// The name of the (virtual) top-level target node.
    var targetNode: String {
        return "<\(self.productName)>"
    }

    var productFilename: String {
        switch type {
        case .Library:
            return "\(productName).a"
        case .Executable:
            return productName
        }
    }
}

extension Array {
    private func pick(body: (Element) -> Bool) -> Element? {
        for x in self {
            if body(x) { return x }
        }
        return nil
    }

    private func chuzzle() -> [Element]? {
        if isEmpty {
            return nil
        } else {
            return self
        }
    }
}
