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
import func sys.system
import func sys.popen

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
        compilerExtraArgs = []
        linkerExtraArgs = []
    }

    public var srcroot: String
    public var targets: [Target]
    public var dependencies: [Package]

    public var prefix: String = ""
    public var tmpdir: String = ""

    public var conf: Configuration
    
    public var compilerExtraArgs: [String]
    public var linkerExtraArgs: [String]

    private func requiredSubdirectories() -> [String] {
        return targets.flatMap { target in
            return target.sources.map { Path(components: $0, "..").relative(to: self.srcroot) }
        } + [""]
    }
}

public func llbuild(srcroot srcroot: String, targets: [Target], dependencies: [Package], prefix: String, tmpdir: String, configuration: BuildParameters.Configuration, compilerExtraArgs: [String], linkerExtraArgs: [String]) throws -> BuildParameters {
    var parms = BuildParameters()
    parms.srcroot = srcroot
    parms.targets = targets
    parms.dependencies = dependencies
    parms.prefix = prefix
    parms.tmpdir = tmpdir
    parms.conf = configuration
    parms.compilerExtraArgs = compilerExtraArgs
    parms.linkerExtraArgs = linkerExtraArgs
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
        filename = Path.join(parameters.tmpdir, "llbuild.yaml")
        filePointer = try fopen(filename, mode: .Write)

        // Compute the 'swiftc' to use.
        swiftcPath = getenv("SWIFT_EXEC") ?? getenv("SWIFTC") ?? Resources.findExecutable("swiftc")

        func xcrun() -> String? {
        #if os(OSX)
            // On OS X, we automatically infer this using xcrun for the time being,
            // to support users directly invoking the tools from a downloadable
            // toolchain.
            return (try? popen(["xcrun", "--sdk", "macosx", "--show-sdk-path"]))?.chuzzle()
        #else
            return nil
        #endif
        }

        sysroot = getenv("SYSROOT") ?? xcrun()
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
        let objects = ofiles(target)
        let inputs = target.dependencies.map{"<\($0.productName)>"} + target.sources
        let outputs = ["<\(target.productName)-swiftc>", modulepath] + objects

        func args() -> [String] {
            var args = ["-j8"] //FIXME

            switch parms.conf {
            case .Debug:
                args += ["-Onone", "-g"]
            case .Release:
                args += ["-O"]
            }

            if sys.verbosity == .Debug {
                args.append("-v")
            }

          #if os(OSX)
            args += ["-target", "x86_64-apple-macosx10.10"]
          #endif
            if target.type == .Library && parms.conf == .Debug {
                args += ["-enable-testing"]
            }
            if let sysroot = sysroot {
                args += ["-sdk", sysroot]
            }

            for pkg in parms.dependencies where pkg.type == .ModuleMap {
                let path = Path.join(pkg.path, "module.modulemap")
                args += ["-Xcc", "-F-module-map=\(path)", "-I", pkg.path]
            }

            if "/usr/local/include".isDirectory {
                // Swift doesn’t include /usr/local by default
                args += ["-I", "/usr/local/include"]
            }

            args += parms.compilerExtraArgs
            
            return args
        }

        try print("  <\(target.productName)-swiftc>:")
        try print("    tool: swift-compiler")
        try print("    executable: \(toYAML(swiftcPath))")
        try print("    inputs: \(toYAML(inputs))")
        try print("    outputs: \(toYAML(outputs))")
        try print("    module-name: \(toYAML(target.moduleName))")
        try print("    module-output-path: \(toYAML(modulepath))")
        try print("    is-library: \(toYAML(target.type == .Library))")
        try print("    sources: \(toYAML(target.sources))")
        try print("    objects: \(toYAML(objects))")
        try print("    import-paths: \(toYAML(importPaths))")
        try print("    temps-path: \(toYAML(prodpath))")
        try print("    other-args: \(toYAML(args()))")
    }

    func writeLinkNode(target: Target) throws {
        let objects = ofiles(target)
        let inputs = ["<\(target.productName)-swiftc>"] + objects
        let productPath = Path.join(parms.prefix, target.productFilename)
        let outputs = [target.targetNode, productPath]

        func args() throws -> [String] {
            switch target.type {
            case .Library:
                let quotedObjects = objects.map({ "'\($0)'" }).joinWithSeparator(" ")
                return ["/bin/sh", "-c", "rm -f '\(productPath)'; ar cr '\(productPath)' \(quotedObjects)"]

            case .Executable:
                var args = [swiftcPath, "-o", productPath] + objects

#if os(OSX)
                args += ["-target", "x86_64-apple-macosx10.10"]
                
                // On OS X, we still require -all_load in order to properly load all libraries.
                args += ["-Xlinker", "-all_load"]
#endif

                // Ensure debugging flags are present, if appropriate.
                if case .Debug = parms.conf {
                    args += ["-g"]
                }

                // We support a custom override in conjunction with the
                // bootstrap script to allow embedding an appropriate RPATH for
                // the package manager tools themselves on Linux, so they can be
                // relocated with the Swift compiler.
                if let rpathValue = getenv("SWIFTPM_EMBED_RPATH") {
                    args += ["-Xlinker", "-rpath", "-Xlinker", rpathValue]
                }

                if let sysroot = sysroot {
                    args += ["-sdk", sysroot]
                }

                // The Linux linker requires that libraries are passed in a
                // reverse topographical sort, hence the reverse(). Specifically
                // it requires that first it finds it does not know about a
                // symbol and then later it finds the symbol.
                
                let libsInOtherPackages = try parms.dependencies.reverse().flatMap { pkg -> [String] in
                    return try pkg.targets()
                        .filter{ $0.type == .Library }
                        .map{ $0.productFilename }
                        .map{ Path.join(self.parms.prefix, $0) }
                }

                // Target dependencies are *already* reverse sorted.

                let libsInThisPackage = target.dependencies
                    .filter{ $0.type == .Library }
                    .map{ $0.productFilename }
                    .map{ Path.join(parms.prefix, $0) }

                // Add the static libraries of our dependencies.
                args += libsInThisPackage
                args += libsInOtherPackages

                if "/usr/local/lib".isDirectory {
                    // Swift doesn’t include /usr/local by default
                    //TODO we only want to do this if a module map wants to do this
                    args += ["-L/usr/local/lib"]
                }

                args += parms.linkerExtraArgs

                return args
            }
        }

        let relativeProductPath = Path(productPath).relative(to: (try? getcwd()) ?? "/")
        let description = "Linking \(target.type):  \(relativeProductPath)"

        try print("  \(target.targetNode):")
        try print("    tool: shell")
        try print("    inputs: \(toYAML(inputs))")
        try print("    outputs: \(toYAML(outputs))")
        try print("    args: \(toYAML(args()))")
        try print("    description: \(toYAML(description))")
    }
}

private func toYAML(arg: Bool) -> String {
    return arg ? "true" : "false"
}
private func toYAML(arg: String) -> String {
    return "\"\(arg)\""
}
private func toYAML(args: [String]) -> String {
    return "[\(args.map(toYAML).joinWithSeparator(","))]"
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
