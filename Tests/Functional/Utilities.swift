/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import Basic
import POSIX
import Utility

#if os(OSX)
import class Foundation.Bundle
#endif


func fixture(name fixtureName: String, tags: [String] = [], file: StaticString = #file, line: UInt = #line, body: @noescape(String) throws -> Void) {

    func gsub(_ input: String) -> String {
        return input.characters.split(separator: "/").map(String.init).joined(separator: "_")
    }

    do {
        try POSIX.mkdtemp(gsub(fixtureName)) { prefix in
            defer { _ = try? Utility.removeFileTree(prefix) }

            let rootd = Path.join(#file, "../../../Fixtures", fixtureName).normpath

            guard rootd.isDirectory else {
                XCTFail("No such fixture: \(rootd)", file: file, line: line)
                return
            }

            if Path.join(rootd, "Package.swift").isFile {
                let dstdir = Path.join(prefix, rootd.basename).normpath
                try systemQuietly("cp", "-R", rootd, dstdir)
                try body(dstdir)
            } else {
                var versions = tags
                func popVersion() -> String {
                    if versions.isEmpty {
                        return "1.2.3"
                    } else if versions.count == 1 {
                        return versions.first!
                    } else {
                        return versions.removeFirst()
                    }
                }

                for name in try! localFS.getDirectoryContents(rootd).sorted() {
                    let d = Path.join(rootd, name)
                    guard d.isDirectory else { continue }
                    let dstdir = Path.join(prefix, d.basename).normpath
                    try systemQuietly("cp", "-R", try realpath(d), dstdir)
                    try systemQuietly(["git", "-C", dstdir, "init"])
                    try systemQuietly(["git", "-C", dstdir, "config", "user.email", "example@example.com"])
                    try systemQuietly(["git", "-C", dstdir, "config", "user.name", "Example Example"])
                    try systemQuietly(["git", "-C", dstdir, "add", "."])
                    try systemQuietly(["git", "-C", dstdir, "commit", "-m", "msg"])
                    try systemQuietly(["git", "-C", dstdir, "tag", popVersion()])
                }
                try body(prefix)
            }
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func initGitRepo(_ dstdir: String, tag: String? = nil, file: StaticString = #file, line: UInt = #line) {
    do {
        let file = Path.join(dstdir, "file.swift")
        try systemQuietly(["touch", file])
        try systemQuietly(["git", "-C", dstdir, "init"])
        try systemQuietly(["git", "-C", dstdir, "config", "user.email", "example@example.com"])
        try systemQuietly(["git", "-C", dstdir, "config", "user.name", "Example Example"])
        try systemQuietly(["git", "-C", dstdir, "add", "."])
        try systemQuietly(["git", "-C", dstdir, "commit", "-m", "msg"])
        if let tag = tag {
            try systemQuietly(["git", "-C", dstdir, "tag", tag])
        }
    }
    catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

enum Configuration {
    case Debug
    case Release
}

private var globalSymbolInMainBinary = 0

/// Defines the executables used by SwiftPM.
/// Contains path to the currently built executable and
/// helper method to execute them.
enum SwiftPMProduct {
    case SwiftBuild
    case SwiftPackage
    case SwiftTest
    case XCTestHelper

    /// Path to currently built binary.
    var path: String {
      #if os(OSX)
        for bundle in Bundle.allBundles() where bundle.bundlePath.hasSuffix(".xctest") {
            return Path.join(bundle.bundlePath.parentDirectory, exec)
        }
        fatalError()
      #else
        return Path.join(Process.arguments.first!.abspath.parentDirectory, exec)
      #endif
    }

    /// Executable name.
    var exec: String {
        switch self {
        case SwiftBuild:
            return "swift-build"
        case SwiftPackage:
            return "swift-package"
        case SwiftTest:
            return "swift-test"
        case XCTestHelper:
            return "swiftpm-xctest-helper"
        }
    }
}

extension SwiftPMProduct {
    /// Executes the product with specified arguments.
    ///
    /// - Parameters:
    ///         - args: The arguments to pass.
    ///         - env: Enviroment variables to pass. Enviroment will never be inherited.
    ///         - chdir: Adds argument `--chdir <path>` if not nil.
    ///         - printIfError: Print the output on non-zero exit.
    ///
    /// - Returns: The output of the process.
    func execute(_ args: [String], chdir: String? = nil, env: [String: String], printIfError: Bool = false) throws -> String {
        var out = ""
        do {
            var theArgs = [path]
            if let chdir = chdir {
                theArgs += ["--chdir", chdir]
            }
            try POSIX.popen(theArgs + args, redirectStandardError: true, environment: env) {
                out += $0
            }
            return out
        } catch {
            if printIfError {
                print("output:", out)
                print("SWIFT_EXEC:", env["SWIFT_EXEC"] ?? "nil")
                print(exec + ":", path)
            }
            throw error
        }
    }
}

@discardableResult
func executeSwiftBuild(_ chdir: String, configuration: Configuration = .Debug, printIfError: Bool = false, Xld: [String] = [], env: [String: String] = [:]) throws -> String {
    var args = ["--configuration"]
    switch configuration {
    case .Debug:
        args.append("debug")
    case .Release:
        args.append("release")
    }
    args += Xld.flatMap{ ["-Xlinker", $0] }

    let swiftBuild = SwiftPMProduct.SwiftBuild
    var env = env

    // FIXME: We use this private environment variable hack to be able to
    // create special conditions in swift-build for swiftpm tests.
    env["IS_SWIFTPM_TEST"] = "1"
    return try swiftBuild.execute(args, chdir: chdir, env: env, printIfError: printIfError)
}

func mktmpdir(_ file: StaticString = #file, line: UInt = #line, body: @noescape(String) throws -> Void) {
    do {
        try POSIX.mkdtemp("spm-tests") { dir in
            defer { _ = try? Utility.removeFileTree(dir) }
            try body(dir)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func XCTAssertBuilds(_ paths: String..., configurations: Set<Configuration> = [.Debug, .Release], file: StaticString = #file, line: UInt = #line, Xld: [String] = [], env: [String: String] = [:]) {
    let prefix = Path.join(paths)

    for conf in configurations {
        do {
            print("    Building \(conf)")
            _ = try executeSwiftBuild(prefix, configuration: conf, printIfError: true, Xld: Xld, env: env)
        } catch {
            XCTFail("`swift build -c \(conf)' failed:\n\n\(error)\n", file: file, line: line)
        }
    }
}

func XCTAssertSwiftTest(_ paths: String..., file: StaticString = #file, line: UInt = #line, env: [String: String] = [:]) {
    let prefix = Path.join(paths)
    do {
        _ = try SwiftPMProduct.SwiftTest.execute([], chdir: prefix, env: env, printIfError: true)
    } catch {
        XCTFail("`swift test' failed:\n\n\(error)\n", file: file, line: line)
    }
}

func XCTAssertBuildFails(_ paths: String..., file: StaticString = #file, line: UInt = #line) {
    let prefix = Path.join(paths)
    do {
        _ = try executeSwiftBuild(prefix)

        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)

    } catch POSIX.Error.exitStatus(let status, _) where status == 1{
        // noop
    } catch {
        XCTFail("`swift build' failed in an unexpected manner")
    }
}

func XCTAssertFileExists(_ paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if !path.isFile {
        XCTFail("Expected file doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertDirectoryExists(_ paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if !path.isDirectory {
        XCTFail("Expected directory doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertNoSuchPath(_ paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if path.exists {
        XCTFail("path exists but should not: \(path)", file: file, line: line)
    }
}
    
func systemQuietly(_ args: [String]) throws {
    // Discard the output, by default.
    //
    // FIXME: Find a better default behavior here.
    let _ = try POSIX.popen(args, redirectStandardError: true)
}

func systemQuietly(_ args: String...) throws {
    try systemQuietly(args)
}
