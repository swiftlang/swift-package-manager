//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import struct Foundation.URL
#if os(macOS)
import class Foundation.Bundle
#endif
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import struct SPMBuildCore.BuildParameters
import TSCTestSupport
import Workspace
import func XCTest.XCTFail

import struct TSCBasic.ByteString
import struct TSCBasic.ProcessResult

import enum TSCUtility.Git

@_exported import func TSCTestSupport.systemQuietly
@_exported import enum TSCTestSupport.StringPattern

/// Test helper utility for executing a block with a temporary directory.
public func testWithTemporaryDirectory(
    function: StaticString = #function,
    body: (AbsolutePath) throws -> Void
) throws {
    let body2 = { (path: TSCAbsolutePath) in
        try body(AbsolutePath(path))
    }

    try TSCTestSupport.testWithTemporaryDirectory(
        function: function,
        body: body2
    )
}

public func testWithTemporaryDirectory(
    function: StaticString = #function,
    body: (AbsolutePath) async throws -> Void
) async throws {
    let cleanedFunction = function.description
        .replacingOccurrences(of: "(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: ":", with: "_")
    try await withTemporaryDirectory(prefix: "spm-tests-\(cleanedFunction)") { tmpDirPath in
        defer {
            // Unblock and remove the tmp dir on deinit.
            try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
            try? localFileSystem.removeFileTree(tmpDirPath)
        }
        try await body(tmpDirPath)
    }
}

/// Test-helper function that runs a block of code on a copy of a test fixture
/// package.  The copy is made into a temporary directory, and the block is
/// given a path to that directory.  The block is permitted to modify the copy.
/// The temporary copy is deleted after the block returns.  The fixture name may
/// contain `/` characters, which are treated as path separators, exactly as if
/// the name were a relative path.
@discardableResult public func fixture<T>(
    name: String,
    createGitRepo: Bool = true,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) throws -> T
) throws -> T {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let fixtureSubpath = try RelativePath(validating: name)
        let copyName = fixtureSubpath.components.joined(separator: "_")

        // Create a temporary directory for the duration of the block.
        return try withTemporaryDirectory(prefix: copyName) { tmpDirPath in

            defer {
                // Unblock and remove the tmp dir on deinit.
                try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                try? localFileSystem.removeFileTree(tmpDirPath)
            }

            // Construct the expected path of the fixture.
            // FIXME: This seems quite hacky; we should provide some control over where fixtures are found.
            let fixtureDir = AbsolutePath("../../../Fixtures", relativeTo: #file)
                .appending(fixtureSubpath)

            // Check that the fixture is really there.
            guard localFileSystem.isDirectory(fixtureDir) else {
                XCTFail("No such fixture: \(fixtureDir)", file: file, line: line)
                throw SwiftPMError.packagePathNotFound
            }

            // The fixture contains either a checkout or just a Git directory.
            if localFileSystem.isFile(fixtureDir.appending("Package.swift")) {
                // It's a single package, so copy the whole directory as-is.
                let dstDir = tmpDirPath.appending(component: copyName)
#if os(Windows)
                try localFileSystem.copy(from: fixtureDir, to: dstDir)
#else
                try systemQuietly("cp", "-R", "-H", fixtureDir.pathString, dstDir.pathString)
#endif

                // Invoke the block, passing it the path of the copied fixture.
                return try body(dstDir)
            } else {
                // Copy each of the package directories and construct a git repo in it.
                for fileName in try localFileSystem.getDirectoryContents(fixtureDir).sorted() {
                    let srcDir = fixtureDir.appending(component: fileName)
                    guard localFileSystem.isDirectory(srcDir) else { continue }
                    let dstDir = tmpDirPath.appending(component: fileName)
#if os(Windows)
                    try localFileSystem.copy(from: srcDir, to: dstDir)
#else
                    try systemQuietly("cp", "-R", "-H", srcDir.pathString, dstDir.pathString)
#endif
                    if createGitRepo {
                        initGitRepo(dstDir, tag: "1.2.3", addFile: false)
                    }
                }

                // Invoke the block, passing it the path of the copied fixture.
                return try body(tmpDirPath)
            }
        }
    } catch SwiftPMError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        throw error
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
    initGitRepo(dir, tags: tag.flatMap { [$0] } ?? [], addFile: addFile, file: file, line: line)
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
            let file = dir.appending("file.swift")
            try localFileSystem.writeFileContents(file, bytes: "")
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
        try systemQuietly([Git.tool, "-C", dir.pathString, "branch", "-m", "main"])
    } catch {
        XCTFail("\(error.interpolationDescription)", file: file, line: line)
    }
}

@discardableResult
public func executeSwiftBuild(
    _ packagePath: AbsolutePath,
    configuration: Configuration = .Debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: EnvironmentVariables? = nil
) throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    return try SwiftPM.Build.execute(args, packagePath: packagePath, env: env)
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
    env: EnvironmentVariables? = nil
) throws -> (stdout: String, stderr: String) {
    var args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    args.append(executable)
    return try SwiftPM.Run.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftPackage(
    _ packagePath: AbsolutePath,
    configuration: Configuration = .Debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: EnvironmentVariables? = nil
) throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    return try SwiftPM.Package.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftTest(
    _ packagePath: AbsolutePath,
    configuration: Configuration = .Debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: EnvironmentVariables? = nil
) throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(configuration: configuration, extraArgs: extraArgs, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    return try SwiftPM.Test.execute(args, packagePath: packagePath, env: env)
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
    args += Xcc.flatMap { ["-Xcc", $0] }
    args += Xld.flatMap { ["-Xlinker", $0] }
    args += Xswiftc.flatMap { ["-Xswiftc", $0] }
    return args
}

public func loadPackageGraph(
    identityResolver: IdentityResolver = DefaultIdentityResolver(),
    fileSystem: FileSystem,
    manifests: [Manifest],
    binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]] = [:],
    explicitProduct: String? = .none,
    shouldCreateMultipleTestProducts: Bool = false,
    createREPLProduct: Bool = false,
    useXCBuildFileRules: Bool = false,
    customXCTestMinimumDeploymentTargets: [PackageModel.Platform: PlatformVersion]? = .none,
    observabilityScope: ObservabilityScope
) throws -> PackageGraph {
    let rootManifests = manifests.filter(\.packageKind.isRoot).spm_createDictionary { ($0.path, $0) }
    let externalManifests = try manifests.filter { !$0.packageKind.isRoot }
        .reduce(
            into: OrderedCollections
                .OrderedDictionary<PackageIdentity, (manifest: Manifest, fs: FileSystem)>()
        ) { partial, item in
            partial[try identityResolver.resolveIdentity(for: item.packageKind)] = (item, fileSystem)
        }

    let packages = Array(rootManifests.keys)
    let input = PackageGraphRootInput(packages: packages)
    let graphRoot = PackageGraphRoot(
        input: input,
        manifests: rootManifests,
        explicitProduct: explicitProduct,
        observabilityScope: observabilityScope
    )

    return try PackageGraph.load(
        root: graphRoot,
        identityResolver: identityResolver,
        additionalFileRules: useXCBuildFileRules ? FileRuleDescription.xcbuildFileTypes : FileRuleDescription
            .swiftpmFileTypes,
        externalManifests: externalManifests,
        binaryArtifacts: binaryArtifacts,
        shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
        createREPLProduct: createREPLProduct,
        customXCTestMinimumDeploymentTargets: customXCTestMinimumDeploymentTargets,
        fileSystem: fileSystem,
        observabilityScope: observabilityScope
    )
}

public let emptyZipFile = ByteString([0x80, 0x75, 0x05, 0x06] + [UInt8](repeating: 0x00, count: 18))

extension FileSystem {
    @_disfavoredOverload
    public func createEmptyFiles(at root: AbsolutePath, files: String...) {
        self.createEmptyFiles(at: TSCAbsolutePath(root), files: files)
    }

    @_disfavoredOverload
    public func createEmptyFiles(at root: AbsolutePath, files: [String]) {
        self.createEmptyFiles(at: TSCAbsolutePath(root), files: files)
    }
}

extension URL: ExpressibleByStringLiteral {
    public init(_ value: StringLiteralType) {
        self.init(string: value)!
    }
}

extension URL: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(string: value)!
    }
}

extension PackageIdentity: ExpressibleByStringLiteral {}

extension PackageIdentity: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = Self.plain(value)
    }
}

extension PackageIdentity {
    public static func registry(_ value: String) -> RegistryIdentity {
        Self.plain(value).registry!
    }
}

extension AbsolutePath: ExpressibleByStringLiteral {
    public init(_ value: StringLiteralType) {
        try! self.init(validating: value)
    }
}

extension AbsolutePath: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        try! self.init(validating: value)
    }
}

extension AbsolutePath {
    public init(_ path: StringLiteralType, relativeTo basePath: AbsolutePath) {
        try! self.init(validating: path, relativeTo: basePath)
    }
}

extension RelativePath {
    @available(*, deprecated, message: "use direct string instead")
    public init(static path: StaticString) {
        let pathString = path.withUTF8Buffer {
            String(decoding: $0, as: UTF8.self)
        }
        try! self.init(validating: pathString)
    }
}

extension RelativePath: ExpressibleByStringLiteral {
    public init(_ value: StringLiteralType) {
        try! self.init(validating: value)
    }
}

extension RelativePath: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        try! self.init(validating: value)
    }
}

extension InitPackage {
    public convenience init(
        name: String,
        packageType: PackageType,
        destinationPath: AbsolutePath,
        fileSystem: FileSystem
    ) throws {
        try self.init(
            name: name,
            options: InitPackageOptions(packageType: packageType),
            destinationPath: destinationPath,
            installedSwiftPMConfiguration: .default,
            fileSystem: fileSystem
        )
    }
}
