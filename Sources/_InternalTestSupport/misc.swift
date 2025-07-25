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

import Foundation
import Basics
import struct Foundation.URL
#if os(macOS)
import class Foundation.Bundle
#endif
import OrderedCollections

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

import PackageLoading
import PackageModel
import SourceControl
import SPMBuildCore
import struct SPMBuildCore.BuildParameters
import TSCTestSupport
import Workspace
import Testing
import func XCTest.XCTFail
import struct XCTest.XCTSkip

import struct TSCBasic.ByteString
import struct Basics.AsyncProcessResult

import enum TSCUtility.Git

@_exported import func TSCTestSupport.systemQuietly
@_exported import enum TSCTestSupport.StringPattern

@available(*, deprecated, message: "Use CiEnvironment.runningInSmokeTestPipeline")
public let isInCiEnvironment = CiEnvironment.runningInSmokeTestPipeline

@available(*, deprecated, message: "Use CiEnvironment.isSelfHostedCiEnvironment")
public let isSelfHostedCiEnvironment = CiEnvironment.runningInSelfHostedPipeline

public struct CiEnvironmentStruct {
    public let runningInSmokeTestPipeline = ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] != nil
    public let runningInSelfHostedPipeline = ProcessInfo.processInfo.environment["SWIFTCI_IS_SELF_HOSTED"] != nil
}

public let CiEnvironment = CiEnvironmentStruct()

public let isRealSigningIdentyEcLabelEnvVarSet =
    ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_EC_LABEL"] != nil

public let isRealSigningIdentitTestDefined = {
    #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        return true
    #else
        return false
    #endif
}()

public let duplicateSymbolRegex: Regex<AnyRegexOutput>? = {
    do {
        return try Regex(".*One of the duplicates must be removed or renamed.")
    } catch {
        return nil
    }
}()

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

@discardableResult
public func testWithTemporaryDirectory<Result>(
    function: StaticString = #function,
    body: (AbsolutePath) async throws -> Result
) async throws -> Result {
    let cleanedFunction = function.description
        .replacing("(", with: "")
        .replacing(")", with: "")
        .replacing(".", with: "")
        .replacing(":", with: "_")
    return try await withTemporaryDirectory(prefix: "spm-tests-\(cleanedFunction)") { tmpDirPath in
        defer {
            // Unblock and remove the tmp dir on deinit.
            try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
            try? localFileSystem.removeFileTree(tmpDirPath)
        }
        return try await body(tmpDirPath)
    }
}

/// Test-helper function that runs a block of code on a copy of a test fixture
/// package.  The copy is made into a temporary directory, and the block is
/// given a path to that directory.  The block is permitted to modify the copy.
/// The temporary copy is deleted after the block returns.  The fixture name may
/// contain `/` characters, which are treated as path separators, exactly as if
/// the name were a relative path.
@available(*, deprecated, message: "Migrate test to Swift Testing and use 'fixture' instead")
@discardableResult public func fixtureXCTest<T>(
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

            let fixtureDir = try verifyFixtureExistsXCTest(at: fixtureSubpath, file: file, line: line)
            let preparedFixture = try setup(
                fixtureDir: fixtureDir,
                in: tmpDirPath,
                copyName: copyName,
                createGitRepo:createGitRepo
            )
            return try body(preparedFixture)
        }
    } catch SwiftPMError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        throw error
    }
}

@discardableResult public func fixture<T>(
    name: String,
    createGitRepo: Bool = true,
    sourceLocation: SourceLocation = #_sourceLocation,
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

            let fixtureDir = try verifyFixtureExists(at: fixtureSubpath, sourceLocation: sourceLocation)
            let preparedFixture = try setup(
                fixtureDir: fixtureDir,
                in: tmpDirPath,
                copyName: copyName,
                createGitRepo:createGitRepo
            )
            return try body(preparedFixture)
        }
    } catch SwiftPMError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        throw error
    }
}

public enum TestError: Error {
    case platformNotSupported
}

@available(*, deprecated, message: "Migrate test to Swift Testing and use 'fixture' instead")
@discardableResult public func fixtureXCTest<T>(
    name: String,
    createGitRepo: Bool = true,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) async throws -> T
) async throws -> T {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let fixtureSubpath = try RelativePath(validating: name)
        let copyName = fixtureSubpath.components.joined(separator: "_")

        // Create a temporary directory for the duration of the block.
        return try await withTemporaryDirectory(prefix: copyName) { tmpDirPath in

            defer {
                // Unblock and remove the tmp dir on deinit.
                try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                try? localFileSystem.removeFileTree(tmpDirPath)
            }

            let fixtureDir = try verifyFixtureExistsXCTest(at: fixtureSubpath, file: file, line: line)
            let preparedFixture = try setup(
                fixtureDir: fixtureDir,
                in: tmpDirPath,
                copyName: copyName,
                createGitRepo:createGitRepo
            )
            return try await body(preparedFixture)
        }
    } catch SwiftPMError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        throw error
    }
}

@discardableResult public func fixture<T>(
    name: String,
    createGitRepo: Bool = true,
    sourceLocation: SourceLocation = #_sourceLocation,
    body: (AbsolutePath) async throws -> T
) async throws -> T {
    do {
        // Make a suitable test directory name from the fixture subpath.
        let fixtureSubpath = try RelativePath(validating: name)
        let copyName = fixtureSubpath.components.joined(separator: "_")

        // Create a temporary directory for the duration of the block.
        return try await withTemporaryDirectory(prefix: copyName) { tmpDirPath in

            defer {
                // Unblock and remove the tmp dir on deinit.
                try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                try? localFileSystem.removeFileTree(tmpDirPath)
            }

            let fixtureDir = try verifyFixtureExists(at: fixtureSubpath, sourceLocation: sourceLocation)
            let preparedFixture = try setup(
                fixtureDir: fixtureDir,
                in: tmpDirPath,
                copyName: copyName,
                createGitRepo:createGitRepo
            )
            return try await body(preparedFixture)
        }
    } catch SwiftPMError.executionFailure(let error, let output, let stderr) {
        print("**** FAILURE EXECUTING SUBPROCESS ****")
        print("output:", output)
        print("stderr:", stderr)
        throw error
    }
}

fileprivate func verifyFixtureExistsXCTest(at fixtureSubpath: RelativePath, file: StaticString = #file, line: UInt = #line) throws -> AbsolutePath {
    let fixtureDir = AbsolutePath("../../../Fixtures", relativeTo: #file)
        .appending(fixtureSubpath)

    // Check that the fixture is really there.
    guard localFileSystem.isDirectory(fixtureDir) else {
        XCTFail("No such fixture: \(fixtureDir)", file: file, line: line)
        throw SwiftPMError.packagePathNotFound
    }

    return fixtureDir
}

fileprivate func verifyFixtureExists(at fixtureSubpath: RelativePath, sourceLocation: SourceLocation = #_sourceLocation) throws -> AbsolutePath {
    let fixtureDir = AbsolutePath("../../../Fixtures", relativeTo: #file)
        .appending(fixtureSubpath)

    // Check that the fixture is really there.
    guard localFileSystem.isDirectory(fixtureDir) else {
        Issue.record("No such fixture: \(fixtureDir)", sourceLocation: sourceLocation)
        throw SwiftPMError.packagePathNotFound
    }

    return fixtureDir
}

fileprivate func setup(
    fixtureDir: AbsolutePath,
    in tmpDirPath: AbsolutePath,
    copyName: String,
    createGitRepo: Bool = true
) throws -> AbsolutePath {
    func copy(from srcDir: AbsolutePath, to dstDir: AbsolutePath) throws {
        #if os(Windows)
        try localFileSystem.copy(from: srcDir, to: dstDir)
        #else
        try systemQuietly("cp", "-R", "-H", srcDir.pathString, dstDir.pathString)
        #endif
        
        // Ensure we get a clean test fixture.
        try localFileSystem.removeFileTree(dstDir.appending(component: ".build"))
        try localFileSystem.removeFileTree(dstDir.appending(component: ".swiftpm"))
    }

    // The fixture contains either a checkout or just a Git directory.
    if localFileSystem.isFile(fixtureDir.appending("Package.swift")) {
        // It's a single package, so copy the whole directory as-is.
        let dstDir = tmpDirPath.appending(component: copyName)
        try copy(from: fixtureDir, to: dstDir)
        // Invoke the block, passing it the path of the copied fixture.
        return dstDir
    }
    // Copy each of the package directories and construct a git repo in it.
    for fileName in try localFileSystem.getDirectoryContents(fixtureDir).sorted() {
        let srcDir = fixtureDir.appending(component: fileName)
        guard localFileSystem.isDirectory(srcDir) else { continue }
        let dstDir = tmpDirPath.appending(component: fileName)

        try copy(from: srcDir, to: dstDir)
        if createGitRepo {
            initGitRepo(dstDir, tag: "1.2.3", addFile: false)
        }
    }
    return tmpDirPath
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

public func getBuildSystemArgs(for buildSystem: BuildSystemProvider.Kind?) -> [String] {
    guard let system = buildSystem else { return [] }

    return [
        "--build-system",
        "\(system)"
    ]
}

@discardableResult
public func executeSwiftBuild(
    _ packagePath: AbsolutePath?,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    buildSystem: BuildSystemProvider.Kind = .native,
    throwIfCommandFails: Bool = true,
) async throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(
        configuration: configuration,
        extraArgs: extraArgs,
        Xcc: Xcc,
        Xld: Xld,
        Xswiftc: Xswiftc,
        buildSystem: buildSystem
    )
    return try await SwiftPM.Build.execute(args, packagePath: packagePath, env: env, throwIfCommandFails: throwIfCommandFails)
}

@discardableResult
public func executeSwiftRun(
    _ packagePath: AbsolutePath?,
    _ executable: String?,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    buildSystem: BuildSystemProvider.Kind
) async throws -> (stdout: String, stderr: String) {
    var args = swiftArgs(
        configuration: configuration,
        extraArgs: extraArgs,
        Xcc: Xcc,
        Xld: Xld,
        Xswiftc: Xswiftc,
        buildSystem: buildSystem
    )
    if let executable {
        args.append(executable)
    }
    return try await SwiftPM.Run.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftPackage(
    _ packagePath: AbsolutePath?,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    buildSystem: BuildSystemProvider.Kind = .native
) async throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(
        configuration: configuration,
        extraArgs: extraArgs,
        Xcc: Xcc,
        Xld: Xld,
        Xswiftc: Xswiftc,
        buildSystem: buildSystem
    )
    return try await SwiftPM.Package.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftPackageRegistry(
    _ packagePath: AbsolutePath?,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    buildSystem: BuildSystemProvider.Kind = .native
) async throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(
        configuration: configuration,
        extraArgs: extraArgs,
        Xcc: Xcc,
        Xld: Xld,
        Xswiftc: Xswiftc,
        buildSystem: buildSystem
    )
    return try await SwiftPM.Registry.execute(args, packagePath: packagePath, env: env)
}

@discardableResult
public func executeSwiftTest(
    _ packagePath: AbsolutePath?,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    throwIfCommandFails: Bool = false,
    buildSystem: BuildSystemProvider.Kind = .native
) async throws -> (stdout: String, stderr: String) {
    let args = swiftArgs(
        configuration: configuration,
        extraArgs: extraArgs,
        Xcc: Xcc,
        Xld: Xld,
        Xswiftc: Xswiftc,
        buildSystem: buildSystem
    )
    return try await SwiftPM.Test.execute(args, packagePath: packagePath, env: env, throwIfCommandFails: throwIfCommandFails)
}

private func swiftArgs(
    configuration: BuildConfiguration,
    extraArgs: [String],
    Xcc: [String],
    Xld: [String],
    Xswiftc: [String],
    buildSystem: BuildSystemProvider.Kind?
) -> [String] {
    var args = ["--configuration"]
    switch configuration {
    case .debug:
        args.append("debug")
    case .release:
        args.append("release")
    }

    args += Xcc.flatMap { ["-Xcc", $0] }
    args += Xld.flatMap { ["-Xlinker", $0] }
    args += Xswiftc.flatMap { ["-Xswiftc", $0] }
    args += getBuildSystemArgs(for: buildSystem)
    args += extraArgs
    return args
}

@available(*, 
    deprecated,
    renamed: "loadModulesGraph",
    message: "Rename for consistency: the type of this functions return value is named `ModulesGraph`."
)
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
    observabilityScope: ObservabilityScope,
    traitConfiguration: TraitConfiguration = .default
) throws -> ModulesGraph {
    try loadModulesGraph(
        identityResolver: identityResolver,
        fileSystem: fileSystem,
        manifests: manifests,
        binaryArtifacts: binaryArtifacts,
        explicitProduct: explicitProduct,
        shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
        createREPLProduct: createREPLProduct,
        useXCBuildFileRules: useXCBuildFileRules,
        customXCTestMinimumDeploymentTargets: customXCTestMinimumDeploymentTargets,
        observabilityScope: observabilityScope,
        traitConfiguration: traitConfiguration
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

extension URL {
    public init(_ value: StringLiteralType) {
        self.init(string: value)!
    }
}

extension URL {
    public init(stringLiteral value: String) {
        self.init(string: value)!
    }
}

extension PackageIdentity {
    public init(stringLiteral value: String) {
        self = Self.plain(value)
    }
}

extension PackageIdentity {
    public static func registry(_ value: String) -> RegistryIdentity {
        Self.plain(value).registry!
    }
}

extension AbsolutePath {
    public init(_ value: StringLiteralType) {
        try! self.init(validating: value)
    }
}

extension AbsolutePath {
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

extension RelativePath {
    public init(_ value: StringLiteralType) {
        try! self.init(validating: value)
    }
}

extension RelativePath {
    public init(stringLiteral value: String) {
        try! self.init(validating: value)
    }
}

extension InitPackage {
    public convenience init(
        name: String,
        packageType: PackageType,
        supportedTestingLibraries: Set<TestingLibrary> = [.swiftTesting],
        destinationPath: AbsolutePath,
        fileSystem: FileSystem
    ) throws {
        try self.init(
            name: name,
            options: InitPackageOptions(packageType: packageType, supportedTestingLibraries: supportedTestingLibraries),
            destinationPath: destinationPath,
            installedSwiftPMConfiguration: .default,
            fileSystem: fileSystem
        )
    }
}

extension RelativePath: ExpressibleByStringLiteral {}
extension RelativePath: ExpressibleByStringInterpolation {}
extension URL: @retroactive ExpressibleByStringLiteral {}
extension URL: @retroactive ExpressibleByStringInterpolation {}
extension PackageIdentity: ExpressibleByStringLiteral {}
extension PackageIdentity: ExpressibleByStringInterpolation {}
extension AbsolutePath: ExpressibleByStringLiteral {}
extension AbsolutePath: ExpressibleByStringInterpolation {}

public func getNumberOfMatches(of match: String, in value: String) -> Int {
    guard match.count != 0 else { return 0 }
    return value.ranges(of: match).count
}

public extension String {
    var withSwiftLineEnding: String {   
        return replacingOccurrences(of: "\r\n", with: "\n")
    }
}

public func executableName(_ name: String) -> String {
#if os(Windows)
  if name.count > 4, name.suffix(from: name.index(name.endIndex, offsetBy: -4)) == ProcessInfo.exeSuffix {
    return name
  }
  return "\(name)\(ProcessInfo.exeSuffix)"
#else
  return name
#endif
}