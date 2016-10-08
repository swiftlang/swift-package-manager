/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import Basic
import PackageDescription
import PackageGraph
import PackageModel
import POSIX
import SourceControl
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
                initGitRepo(dstDir, tag: popVersion(), addFile: false)
            }

            // Invoke the block, passing it the path of the copied fixture.
            try body(tmpDir.path)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

/// Test-helper function that creates a new Git repository in a directory.  The new repository will contain
/// exactly one empty file unless `addFile` is `false`, and if a tag name is provided, a tag with that name will be created.
public func initGitRepo(_ dir: AbsolutePath, tag: String? = nil, addFile: Bool = true, file: StaticString = #file, line: UInt = #line) {
    initGitRepo(dir, tags: tag.flatMap{ [$0] } ?? [], addFile: addFile, file: file, line: line)
}

public func initGitRepo(_ dir: AbsolutePath, tags: [String], addFile: Bool = true, file: StaticString = #file, line: UInt = #line) {
    do {
        if addFile {
            let file = dir.appending(component: "file.swift")
            try systemQuietly(["touch", file.asString])
        }

        try systemQuietly([Git.tool, "-C", dir.asString, "init"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.email", "example@example.com"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "user.name", "Example Example"])
        try systemQuietly([Git.tool, "-C", dir.asString, "config", "commit.gpgsign", "false"])
        let repo = GitRepository(path: dir)
        try repo.stageEverything()
        try repo.commit(message: "msg")
        for tag in tags {
            try repo.tag(name: tag)
        }
    }
    catch {
        XCTFail("\(error)", file: file, line: line)
    }
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

/// Loads a mock package graph based on package packageMap dictionary provided where key is path to a package.
public func loadMockPackageGraph(_ packageMap: [String: PackageDescription.Package], root: String, in fs: FileSystem) throws -> PackageGraph {
    var externalManifests = [Manifest]()
    var rootManifest: Manifest!
    for (url, package) in packageMap {
        let manifest = Manifest(
            path: AbsolutePath(url).appending(component: Manifest.filename),
            url: url,
            package: package,
            products: [],
            version: "1.0.0"
        )
        if url == root {
            rootManifest = manifest
        } else {
            externalManifests.append(manifest)
        }
    }
    return try PackageGraphLoader().load(rootManifest: rootManifest, externalManifests: externalManifests, fileSystem: fs)
}
