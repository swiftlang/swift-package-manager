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

public struct BuildParameters {
    public enum Configuration {
        case Debug, Release

        public var dirname: String {
            switch self {
                case .Debug: return "debug"
                case .Release: return "release"
            }
        }
    }

    public init() {
        srcroot = ""
        targets = []
        dependencies = []
        conf = .Debug
    }

    public var srcroot: String
    public var targets: [Target]
    public var dependencies: [Package]

    public var prefix: String = ""
    public var tmpdir: String = ""

    public var conf: Configuration

    private func requiredSubdirectories() -> [String] {
        return targets.flatMap { target in
            return target.sources.map { Path(components: $0, "..").relative(to: self.srcroot) }
        } + [prefix]
    }
}

public func llbuild(srcroot srcroot: String, targets: [Target], dependencies: [Package], prefix: String, tmpdir: String, configuration: BuildParameters.Configuration) throws -> BuildParameters {
    var parms = BuildParameters()
    parms.srcroot = srcroot
    parms.targets = targets
    parms.dependencies = dependencies
    parms.prefix = prefix
    parms.tmpdir = tmpdir
    parms.conf = configuration
    try llbuild(parms)
    return parms
}

public func llbuild(parms: BuildParameters) throws {
    for subdir in parms.requiredSubdirectories() {
        try mkdir(parms.tmpdir, subdir)
    }

    let yaml = try YAML(parameters: parms)
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
    let parms: BuildParameters
    var filePointer: UnsafeMutablePointer<FILE>
    let filename: String

    
    /**
      The 'swiftc' executable path to use.
    */
    let swiftcPath: String

    /**
      The selected sysroot, if in use.
    */
    let sysroot: String?
    
    init(parameters: BuildParameters) throws {
        parms = parameters
        let path = Path.join(parameters.tmpdir, "llbuild.yaml")
        filename = path
        do {
            filePointer = try fopen(path, mode: "w")
        } catch {
            filePointer = nil
            throw error
        }

        // Compute the 'swiftc' to use.
        swiftcPath = getenv("SWIFTC") ?? Resources.findExecutable("swiftc")

        // Compute the '--sysroot' to use.
        //
        // On OS X, we automatically infer this using xcrun for the time being,
        // to support users directly invoking the tools from a downloadable
        // toolchain.
        if let sysroot = getenv("SYSROOT") {
            self.sysroot = sysroot
        } else {
#if os(OSX)
            self.sysroot = (try? popen(["xcrun", "--sdk", "macosx", "--show-sdk-path"]))?.chuzzle()
#endif
        }
    }

    deinit {
        if filePointer != nil {
            fclose(filePointer)
        }
    }

    func targetsString() -> String { return parms.targets.map{$0.targetNode}.joinWithSeparator(", ") }

    func print(s: String = "") throws {
        try fputs(s, filePointer)
        try fputs("\n", filePointer)
    }

    func write() throws {
        try print("client:")
        try print("  name: swift-build")
        try print()

        try print("tools: {}")
        try print()

        try print("targets:")
        try print("  \"\": [\(targetsString())]")
        for target in parms.targets {
            try print("  \(target.productName): [\(target.targetNode)]")
        }
        try print()

        try print("commands:")

        if parms.targets.isEmpty {
            try print("  {}")
        } else {
            for target in parms.targets {
                try writeCompileNode(target)
                try writeLinkNode(target)
            }
        }

        fclose(filePointer)
        filePointer = nil
    }


    func ofiles(target: Target) -> [String] {
        return target.sources.map { srcfile -> String in
            let tip = Path(srcfile).relative(to: parms.srcroot)
            return Path.join(parms.tmpdir, "\(tip).o")
        }
    }

    func writeCompileNode(target: Target) throws {
        let importPaths = [parms.prefix]
        let prodpath = Path.join(parms.tmpdir, target.productName)
        let modulepath = Path.join(parms.prefix, "\(target.moduleName).swiftmodule")
        let sources = target.sources.chuzzle()?.joinWithSeparator(" ") ?? "\"\""
        let objects = ofiles(target).chuzzle()?.joinWithSeparator(" ") ?? "\"\""
        let inputs = (target.dependencies.map{"<\($0.productName)>"} + target.sources.map(quote)).joinWithSeparator(", ")
        let outputs = (["<\(target.productName)-swiftc>", modulepath] + ofiles(target).map(quote)).joinWithSeparator(", ")

        func args() -> String {
            var args = "-j8" //FIXME

            switch parms.conf {
            case .Debug:
                args += " -Onone -g"
            case .Release:
                args += " -Ounchecked"
            }

          #if os(OSX)
            args += " -target x86_64-apple-macosx10.10"
          #endif
            if target.type == .Library && parms.conf == .Debug {
                args += " -enable-testing"
            }
            if sysroot != nil {
                args += " -sdk \(quote(sysroot!))"
            }

            for pkg in parms.dependencies where pkg.type == .ModuleMap {
                let path = Path.join(pkg.path, "module.modulemap")
                args += " -Xcc -F-module-map=\(path) -I\(pkg.path)"
            }

            // Swift doesn’t include /usr/local by default
            args += " -I/usr/local/include "

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
        let productPath = Path.join(parms.prefix, target.productFilename)

        func args() throws -> String {
            switch target.type {
            case .Library:
                return "rm -f \(quote(productPath)); ar cr \(quote(productPath)) \(objectargs)"
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
                    args += "-Xlinker -rpath -Xlinker \"\(rpathValue)\" "
                }

                if sysroot != nil {
                    args += "-sdk \(quote(sysroot!)) "
                }

                let libsInOtherPackages = try parms.dependencies.flatMap { pkg -> [String] in
                    return try pkg.targets()
                        .filter{ $0.type == .Library }
                        .map{ $0.productFilename }
                        .map{ Path.join(self.parms.prefix, $0) }
                }

                let libsInThisPackage = target.dependencies
                    .filter{ $0.type == .Library }
                    .map{ $0.productFilename }
                    .map{ Path.join(parms.prefix, $0) }

                // Add the static libraries of our dependencies.
                //
                // We currently pass this with -Xlinker because the 'swift-autolink-extract' tool does not understand how to work with archives (<rdar://problem/23045632>).
                args += (libsInThisPackage + libsInOtherPackages).flatMap{ ["-Xlinker", quote($0)] }.joinWithSeparator(" ")

                // Swift doesn’t include /usr/local by default
                //TODO we only want to do this if a module map wants to do this
                args += " -L/usr/local/lib "

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
