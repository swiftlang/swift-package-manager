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

#if os(macOS)
import class Foundation.Bundle
#endif


/// Test-helper function that runs a block of code on a copy of a test fixture package.  The copy is made into a temporary directory, and the block is given a path to that directory.  The block is permitted to modify the copy.  The temporary copy is deleted after the block returns.
func fixture(name fixtureSubpath: RelativePath, tags: [String] = [], file: StaticString = #file, line: UInt = #line, body: @noescape(AbsolutePath) throws -> Void) {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let copyName = fixtureSubpath.components.joined(separator: "_")
        
        // Create a temporary directory for the duration of the block.
        let tmpDir = try TemporaryDirectory(prefix: copyName, removeTreeOnDeinit: true)
            
        // Construct the expected path of the fixture.
        // FIXME: This seems quite hacky; we should provide some control over where fixtures are found.
        let fixtureDir = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory.appending("Fixtures").appending(fixtureSubpath)
        
        // Check that the fixture is really there.
        guard try isDirectory(fixtureDir) else {
            XCTFail("No such fixture: \(fixtureDir.asString)", file: file, line: line)
            return
        }
        
        // The fixture contains either a checkout or just a Git directory.
        if try isFile(fixtureDir.appending("Package.swift")) {
            // It's a single package, so copy the whole directory as-is.
            let dstDir = tmpDir.path.appending(component: copyName)
            try systemQuietly("cp", "-R", "-H", fixtureDir.asString, dstDir.asString)
            
            // Invoke the block, passing it the path of the copied fixture.
            try body(dstDir)
        } else {
            // Not a single package, so we expect it to be a directory of packages.
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
            
            // Copy each of the package directories and construct a git repo in it.
            for fileName in try! localFileSystem.getDirectoryContents(fixtureDir).sorted() {
                let srcDir = fixtureDir.appending(component: fileName)
                guard try isDirectory(srcDir) else { continue }
                let dstDir = tmpDir.path.appending(component: fileName)
                try systemQuietly("cp", "-R", "-H", srcDir.asString, dstDir.asString)
                try systemQuietly([Git.tool, "-C", dstDir.asString, "init"])
                try systemQuietly([Git.tool, "-C", dstDir.asString, "config", "user.email", "example@example.com"])
                try systemQuietly([Git.tool, "-C", dstDir.asString, "config", "user.name", "Example Example"])
                try systemQuietly([Git.tool, "-C", dstDir.asString, "add", "."])
                try systemQuietly([Git.tool, "-C", dstDir.asString, "commit", "-m", "msg"])
                try systemQuietly([Git.tool, "-C", dstDir.asString, "tag", popVersion()])
            }
            
            // Invoke the block, passing it the path of the copied fixture.
            try body(tmpDir.path)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

/// Test-helper function that creates a new Git repository in a directory.  The new repository will contain exactly one empty file, and if a tag name is provided, a tag with that name will be created.
func initGitRepo(_ dir: AbsolutePath, tag: String? = nil, file: StaticString = #file, line: UInt = #line) {
    do {
        let file = dir.appending(component: "file.swift")
        try systemQuietly(["touch", file.asString])
        try systemQuietly([Git.tool, "-C", dir.asString, "init"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.email", "example@example.com"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.name", "Example Example"])
        try systemQuietly([Git.tool, "-C", dir.asString, "add", "."])
        try systemQuietly([Git.tool, "-C", dir.asString, "commit", "-m", "msg"])
        if let tag = tag {
            try tagGitRepo(dir, tag: tag)
        }
    }
    catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func tagGitRepo(_ dir: AbsolutePath, tag: String) throws {
    try systemQuietly([Git.tool, "-C", dir.asString, "tag", tag])
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
    var path: AbsolutePath {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return AbsolutePath(bundle.bundlePath).parentDirectory.appending(self.exec)
        }
        fatalError()
      #else
        return AbsolutePath(Process.arguments.first!.abspath).parentDirectory.appending(self.exec)
      #endif
    }

    /// Executable name.
    var exec: RelativePath {
        switch self {
        case .SwiftBuild:
            return "swift-build"
        case .SwiftPackage:
            return "swift-package"
        case .SwiftTest:
            return "swift-test"
        case .XCTestHelper:
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
    func execute(_ args: [String], chdir: AbsolutePath? = nil, env: [String: String] = [:], printIfError: Bool = false) throws -> String {
        var out = ""
        var completeArgs = [path.asString]
        if let chdir = chdir {
            completeArgs += ["--chdir", chdir.asString]
        }
        completeArgs += args
        do {
            try POSIX.popen(completeArgs, redirectStandardError: true, environment: env) {
                out += $0
            }
            return out
        } catch {
            if printIfError {
                print("**** FAILURE EXECUTING SUBPROCESS ****")
                print("command: " + completeArgs.map{ $0.shellEscaped() }.joined(separator: " "))
                print("SWIFT_EXEC:", env["SWIFT_EXEC"] ?? "nil")
                print("output:", out)
            }
            throw error
        }
    }
}

@discardableResult
func executeSwiftBuild(_ chdir: AbsolutePath, configuration: Configuration = .Debug, printIfError: Bool = false, Xld: [String] = [], env: [String: String] = [:]) throws -> String {
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

/// Test helper utility for executing a block with a temporary directory.
func mktmpdir(function: StaticString = #function, file: StaticString = #file, line: UInt = #line, body: @noescape(AbsolutePath) throws -> Void) {
    do {
        let tmpDir = try TemporaryDirectory(prefix: "spm-tests-\(function)", removeTreeOnDeinit: true)
        try body(tmpDir.path)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func XCTAssertBuilds(_ path: AbsolutePath, configurations: Set<Configuration> = [.Debug, .Release], file: StaticString = #file, line: UInt = #line, Xld: [String] = [], env: [String: String] = [:]) {
    for conf in configurations {
        do {
            print("    Building \(conf)")
            _ = try executeSwiftBuild(path, configuration: conf, printIfError: true, Xld: Xld, env: env)
        } catch {
            XCTFail("`swift build -c \(conf)' failed:\n\n\(error)\n", file: file, line: line)
        }
    }
}

func XCTAssertSwiftTest(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line, env: [String: String] = [:]) {
    do {
        _ = try SwiftPMProduct.SwiftTest.execute([], chdir: path, env: env, printIfError: true)
    } catch {
        XCTFail("`swift test' failed:\n\n\(error)\n", file: file, line: line)
    }
}

func XCTAssertBuildFails(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try executeSwiftBuild(path)

        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)

    } catch POSIX.Error.exitStatus(let status, _) where status == 1{
        // noop
    } catch {
        XCTFail("`swift build' failed in an unexpected manner")
    }
}

func XCTAssertFileExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if try! !isFile(path) {
        XCTFail("Expected file doesn’t exist: \(path.asString)", file: file, line: line)
    }
}

func XCTAssertDirectoryExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if try! !isDirectory(path) {
        XCTFail("Expected directory doesn’t exist: \(path.asString)", file: file, line: line)
    }
}

func XCTAssertNoSuchPath(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if try! exists(path) {
        XCTFail("path exists but should not: \(path.asString)", file: file, line: line)
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
