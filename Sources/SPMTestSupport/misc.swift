/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail
import class Foundation.NSDate
import class Foundation.Thread

import TSCBasic
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility
import Workspace
import Commands

@_exported import TSCTestSupport

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
        try withTemporaryDirectory(prefix: copyName) { tmpDirPath in

            defer {
                // Unblock and remove the tmp dir on deinit.
                try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                try? localFileSystem.removeFileTree(tmpDirPath)
            }

            // Construct the expected path of the fixture.
            // FIXME: This seems quite hacky; we should provide some control over where fixtures are found.
            let fixtureDir = AbsolutePath(#file).appending(RelativePath("../../../Fixtures")).appending(fixtureSubpath)

            // Check that the fixture is really there.
            guard localFileSystem.isDirectory(fixtureDir) else {
                XCTFail("No such fixture: \(fixtureDir)", file: file, line: line)
                return
            }

            // The fixture contains either a checkout or just a Git directory.
            if localFileSystem.isFile(fixtureDir.appending(component: "Package.swift")) {
                // It's a single package, so copy the whole directory as-is.
                let dstDir = tmpDirPath.appending(component: copyName)
                try systemQuietly("cp", "-R", "-H", fixtureDir.pathString, dstDir.pathString)

                // Invoke the block, passing it the path of the copied fixture.
                try body(dstDir)
            } else {
                // Copy each of the package directories and construct a git repo in it.
                for fileName in try! localFileSystem.getDirectoryContents(fixtureDir).sorted() {
                    let srcDir = fixtureDir.appending(component: fileName)
                    guard localFileSystem.isDirectory(srcDir) else { continue }
                    let dstDir = tmpDirPath.appending(component: fileName)
                    try systemQuietly("cp", "-R", "-H", srcDir.pathString, dstDir.pathString)
                    initGitRepo(dstDir, tag: "1.2.3", addFile: false)
                }

                // Invoke the block, passing it the path of the copied fixture.
                try body(tmpDirPath)
            }
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
            try systemQuietly(["touch", file.pathString])
        }
        
        try systemQuietly([Git.tool, "-C", dir.pathString, "init"])
        try systemQuietly([Git.tool, "-C", dir.pathString, "config", "user.email", "example@example.com"])
        try systemQuietly([Git.tool, "-C", dir.pathString, "config", "user.name", "Example Example"])
        try systemQuietly([Git.tool, "-C", dir.pathString, "config", "commit.gpgsign", "false"])
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

private var globalSymbolInMainBinary = 0

@discardableResult
public func executeSwiftBuild(
    _ packagePath: AbsolutePath,
    configuration: Configuration = .Debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: [String: String]? = nil
) throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftRun(
    _ packagePath: AbsolutePath,
    _ executable: String,
    configuration: Configuration = .Debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: [String: String]? = nil
) throws -> (stdout: String, stderr: String) {
    var args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    args.append(executable)
    return try SwiftPMProduct.SwiftRun.execute(args, packagePath: packagePath, env: env)
}

private func swiftArgs(
    configuration: Configuration,
    extraArgs: [String],
    Xcc: [String],
    Xld: [String],
    Xswiftc: [String]
) -> [String] {
    var args = ["--configuration"]
    switch configuration {
    case .Debug:
        args.append("debug")
    case .Release:
        args.append("release")
    }

    args += extraArgs
    args += Xcc.flatMap({ ["-Xcc", $0] })
    args += Xld.flatMap({ ["-Xlinker", $0] })
    args += Xswiftc.flatMap({ ["-Xswiftc", $0] })
    return args
}

public func loadPackageGraph(
    fs: FileSystem,
    diagnostics: DiagnosticsEngine = DiagnosticsEngine(),
    manifests: [Manifest],
    explicitProduct: String? = nil,
    shouldCreateMultipleTestProducts: Bool = false,
    createREPLProduct: Bool = false
) -> PackageGraph {
    let rootManifests = manifests.filter({ $0.packageKind == .root })
    let externalManifests = manifests.filter({ $0.packageKind != .root })
    let packages = rootManifests.map({ $0.path })
    let input = PackageGraphRootInput(packages: packages)
    let graphRoot = PackageGraphRoot(input: input, manifests: rootManifests, explicitProduct: explicitProduct)

    return PackageGraphLoader().load(
        root: graphRoot,
        externalManifests: externalManifests,
        diagnostics: diagnostics,
        fileSystem: fs,
        shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
        createREPLProduct: createREPLProduct
    )
}

extension Destination {
    public static let host = try! hostDestination()
}
