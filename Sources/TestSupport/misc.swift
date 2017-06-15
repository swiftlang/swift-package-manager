/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail
import class Foundation.NSDate

import Basic
import PackageDescription
import PackageDescription4
import PackageGraph
import PackageModel
import POSIX
import SourceControl
import Utility
import Workspace

#if os(macOS)
import class Foundation.Bundle
#endif

/// Test-helper function that runs a block of code on a copy of a test fixture
/// package.  The copy is made into a temporary directory, and the block is
/// given a path to that directory.  The block is permitted to modify the copy.
/// The temporary copy is deleted after the block returns.  The fixture name may
/// contain `/` characters, which are treated as path separators, exactly as if
/// the name were a relative path.
public func fixture(
    name: String,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) throws -> Void
) {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let fixtureSubpath = RelativePath(name)
        let copyName = fixtureSubpath.components.joined(separator: "_")

        // Create a temporary directory for the duration of the block.
        let tmpDir = try TemporaryDirectory(prefix: copyName)

        defer {
            // Unblock and remove the tmp dir on deinit.
            try? localFileSystem.chmod(.userWritable, path: tmpDir.path, options: [.recursive])
            try? localFileSystem.removeFileTree(tmpDir.path)
        }

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
            // Copy each of the package directories and construct a git repo in it.
            for fileName in try! localFileSystem.getDirectoryContents(fixtureDir).sorted() {
                let srcDir = fixtureDir.appending(component: fileName)
                guard isDirectory(srcDir) else { continue }
                let dstDir = tmpDir.path.appending(component: fileName)
                try systemQuietly("cp", "-R", "-H", srcDir.asString, dstDir.asString)
                initGitRepo(dstDir, tag: "1.2.3", addFile: false)
            }

            // Invoke the block, passing it the path of the copied fixture.
            try body(tmpDir.path)
        }
    } catch SwiftPMProductError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        XCTFail("\(error)", file: file, line: line)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

/// Test-helper function that creates a new Git repository in a directory.  The new repository will contain
/// exactly one empty file unless `addFile` is `false`, and if a tag name is provided, a tag with that name will be
/// created.
public func initGitRepo(
    _ dir: AbsolutePath,
    tag: String? = nil,
    addFile: Bool = true,
    file: StaticString = #file,
    line: UInt = #line
) {
    initGitRepo(dir, tags: tag.flatMap({ [$0] }) ?? [], addFile: addFile, file: file, line: line)
}

public func initGitRepo(
    _ dir: AbsolutePath,
    tags: [String],
    addFile: Bool = true,
    file: StaticString = #file,
    line: UInt = #line
) {
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
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

public enum Configuration {
    case Debug
    case Release
}

private var globalSymbolInMainBinary = 0

@discardableResult
public func executeSwiftBuild(
    _ packagePath: AbsolutePath,
    configuration: Configuration = .Debug,
    printIfError: Bool = false,
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: [String: String]? = nil
) throws -> String {
    var args = ["--configuration"]
    switch configuration {
    case .Debug:
        args.append("debug")
    case .Release:
        args.append("release")
    }
    args += Xcc.flatMap({ ["-Xcc", $0] })
    args += Xld.flatMap({ ["-Xlinker", $0] })
    args += Xswiftc.flatMap({ ["-Xswiftc", $0] })

    return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath, env: env, printIfError: printIfError)
}

/// Test helper utility for executing a block with a temporary directory.
public func mktmpdir(
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) throws -> Void
) {
    do {
        let cleanedFunction = function.description
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
        let tmpDir = try TemporaryDirectory(prefix: "spm-tests-\(cleanedFunction)")
        defer {
            // Unblock and remove the tmp dir on deinit.
            try? localFileSystem.chmod(.userWritable, path: tmpDir.path, options: [.recursive])
            try? localFileSystem.removeFileTree(tmpDir.path)
        }
        try body(tmpDir.path)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

public func systemQuietly(_ args: [String]) throws {
    // Discard the output, by default.
    //
    // FIXME: Find a better default behavior here.
    try Process.checkNonZeroExit(arguments: args)
}

public func systemQuietly(_ args: String...) throws {
    try systemQuietly(args)
}

/// Loads a mock package graph based on package packageMap dictionary provided where key is path to a package.
public func loadMockPackageGraph(
    _ packageMap: [String: PackageDescription.Package],
    root: String,
    diagnostics: DiagnosticsEngine = DiagnosticsEngine(),
    in fs: FileSystem
) -> PackageGraph {
    var externalManifests = [Manifest]()
    var rootManifest: Manifest!
    for (url, package) in packageMap {
        let manifest = Manifest(
            path: AbsolutePath(url).appending(component: Manifest.filename),
            url: url,
            package: .v3(package),
            version: "1.0.0"
        )
        if url == root {
            rootManifest = manifest
        } else {
            externalManifests.append(manifest)
        }
    }
    let root = PackageGraphRoot(manifests: [rootManifest])
    return PackageGraphLoader().load(root: root, externalManifests: externalManifests, diagnostics: diagnostics, fileSystem: fs)
}

public func loadMockPackageGraph4(
    _ packageMap: [String: PackageDescription4.Package],
    root: String,
    diagnostics: DiagnosticsEngine = DiagnosticsEngine(),
    in fs: FileSystem
) -> PackageGraph {
    var externalManifests = [Manifest]()
    var rootManifest: Manifest!
    for (url, package) in packageMap {
        let manifest = Manifest(
            path: AbsolutePath(url).appending(component: Manifest.filename),
            url: url,
            package: .v4(package),
            version: "1.0.0"
        )
        if url == root {
            rootManifest = manifest
        } else {
            externalManifests.append(manifest)
        }
    }
    let root = PackageGraphRoot(manifests: [rootManifest])
    return PackageGraphLoader().load(root: root, externalManifests: externalManifests, diagnostics: diagnostics, fileSystem: fs)
}

/// Temporary override environment variables
///
/// WARNING! This method is not thread-safe. POSIX environments are shared 
/// between threads. This means that when this method is called simultaneously 
/// from different threads, the environment will neither be setup nor restored
/// correctly.
///
/// - throws: errors thrown in `body`, POSIX.SystemError.setenv and 
///           POSIX.SystemError.unsetenv
public func withCustomEnv(_ env: [String: String], body: () throws -> Void) throws {
    let state = Array(env.keys).map({ ($0, getenv($0)) })
    let restore = {
        for (key, value) in state {
            if let value = value {
                try setenv(key, value: value)
            } else {
                try unsetenv(key)
            }
        }
    }
    do {
        for (key, value) in env {
            try setenv(key, value: value)
        }
        try body()
    } catch {
        try? restore()
        throw error
    }
    try restore()
}

/// Waits for a file to appear for around 1 second.
/// Returns true if found, false otherwise.
public func waitForFile(_ path: AbsolutePath) -> Bool {
    let endTime = NSDate().timeIntervalSince1970 + 2
    while NSDate().timeIntervalSince1970 < endTime {
        // Sleep for a bit so we don't burn a lot of CPU.
        try? usleep(microSeconds: 10000)
        if localFileSystem.exists(path) {
            return true
        }
    }
    return false
}

extension Process {
    /// If the given pid is running or not.
    ///
    /// - Parameters:
    ///   - pid: The pid to check.
    ///   - orDefunct: If set to true, the method will also check if pid is defunct and return false.
    /// - Returns: True if the given pid is running.
    public static func running(_ pid: ProcessID, orDefunct: Bool = false) throws -> Bool {
        // Shell out to `ps -s` instead of using getpgid() as that is more deterministic on linux.
        let result = try Process.popen(arguments: ["ps", "-p", String(pid)])
        // If ps -p exited with return code 1, it means there is no entry for the process.
        var exited = result.exitStatus == .terminated(code: 1)
        if orDefunct {
            // Check if the process became defunct.
            exited = try exited || result.utf8Output().contains("defunct")
        }
        return !exited
    }
}
