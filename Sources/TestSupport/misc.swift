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


/// Test-helper function that runs a block of code on a copy of a test fixture package.  The copy is made into a temporary directory, and the block is given a path to that directory.  The block is permitted to modify the copy.  The temporary copy is deleted after the block returns.  The fixture name may contain `/` characters, which are treated as path separators, exactly as if the name were a relative path.
public func fixture(name: String, tags: [String] = [], file: StaticString = #file, line: UInt = #line, body: (AbsolutePath) throws -> Void) {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let fixtureSubpath = RelativePath(name)
        let copyName = fixtureSubpath.components.joined(separator: "_")
        
        // Create a temporary directory for the duration of the block.
        let tmpDir = try TemporaryDirectory(prefix: copyName, removeTreeOnDeinit: true)
            
        // Construct the expected path of the fixture.
        // FIXME: This seems quite hacky; we should provide some control over where fixtures are found.
        let fixtureDir = AbsolutePath(#file).appending(RelativePath("../../../Fixtures")).appending(fixtureSubpath)
        
        // Check that the fixture is really there.
        guard isDirectory(fixtureDir) else {
            XCTFail("No such fixture: \(fixtureDir.asString)", file: file, line: line)
            return
        }
        
        // The fixture contains either a checkout or just a Git directory.
        if isFile(fixtureDir.appending(component: "Package.swift")) {
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
                guard isDirectory(srcDir) else { continue }
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
public func initGitRepo(_ dir: AbsolutePath, tag: String? = nil, file: StaticString = #file, line: UInt = #line) {
    initGitRepo(dir, tags: tag.flatMap{ [$0] } ?? [], file: file, line: line)
}

public func initGitRepo(_ dir: AbsolutePath, tags: [String], file: StaticString = #file, line: UInt = #line) {
    do {
        let file = dir.appending(component: "file.swift")
        try systemQuietly(["touch", file.asString])
        try systemQuietly([Git.tool, "-C", dir.asString, "init"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.email", "example@example.com"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.name", "Example Example"])
        try systemQuietly([Git.tool, "-C", dir.asString, "add", "."])
        try systemQuietly([Git.tool, "-C", dir.asString, "commit", "-m", "msg"])
        for tag in tags {
            try tagGitRepo(dir, tag: tag)
        }
    }
    catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

public func tagGitRepo(_ dir: AbsolutePath, tag: String) throws {
    try systemQuietly([Git.tool, "-C", dir.asString, "tag", tag])
}

public func removeTagGitRepo(_ dir: AbsolutePath, tag: String) throws {
    try systemQuietly([Git.tool, "-C", dir.asString, "tag", "-d", tag])
}

public func addGitRepo(_ dir: AbsolutePath, file path: RelativePath) throws {
    try systemQuietly([Git.tool, "-C", dir.asString, "add", path.asString])
}

public func commitGitRepo(_ dir: AbsolutePath, message: String = "Test commit") throws {
    try systemQuietly([Git.tool, "-C", dir.asString, "commit", "-m", message])
}

public enum Configuration {
    case Debug
    case Release
}

private var globalSymbolInMainBinary = 0

@discardableResult
public func executeSwiftBuild(_ chdir: AbsolutePath, configuration: Configuration = .Debug, printIfError: Bool = false, Xcc: [String] = [], Xld: [String] = [], Xswiftc: [String] = [], env: [String: String] = [:]) throws -> String {
    var args = ["--configuration"]
    switch configuration {
    case .Debug:
        args.append("debug")
    case .Release:
        args.append("release")
    }
    args += Xcc.flatMap{ ["-Xcc", $0] }
    args += Xld.flatMap{ ["-Xlinker", $0] }
    args += Xswiftc.flatMap{ ["-Xswiftc", $0] }

    let swiftBuild = SwiftPMProduct.SwiftBuild
    var env = env

    // FIXME: We use this private environment variable hack to be able to
    // create special conditions in swift-build for swiftpm tests.
    env["IS_SWIFTPM_TEST"] = "1"
    return try swiftBuild.execute(args, chdir: chdir, env: env, printIfError: printIfError)
}

/// Test helper utility for executing a block with a temporary directory.
public func mktmpdir(function: StaticString = #function, file: StaticString = #file, line: UInt = #line, body: (AbsolutePath) throws -> Void) {
    do {
        let tmpDir = try TemporaryDirectory(prefix: "spm-tests-\(function)", removeTreeOnDeinit: true)
        try body(tmpDir.path)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

public func systemQuietly(_ args: [String]) throws {
    // Discard the output, by default.
    //
    // FIXME: Find a better default behavior here.
    let _ = try POSIX.popen(args, redirectStandardError: true)
}

public func systemQuietly(_ args: String...) throws {
    try systemQuietly(args)
}

public extension FileSystem {
    /// Write to a file from a stream producer.
    //
    // FIXME: This is copy-paste from Commands/init.swift, maybe it is reasonable to lift it to Basic?
    mutating func writeFileContents(_ path: AbsolutePath, body: (OutputByteStream) -> ()) throws {
        let contents = BufferedOutputByteStream()
        body(contents)
        try createDirectory(path.parentDirectory, recursive: true)
        try writeFileContents(path, bytes: contents.bytes)
    }
}

