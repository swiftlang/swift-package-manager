/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import Testing
import TSCBasic
import TSCTestSupport
import enum TSCUtility.Git

public let sdkRoot: AbsolutePath? = {
    if let environmentPath = ProcessInfo.processInfo.environment["SDK_ROOT"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    #if os(macOS)
    let result = try! Process.popen(arguments: ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    let sdkRoot = try! AbsolutePath(validating: result.utf8Output().spm_chomp())
    return sdkRoot
    #else
    return nil
    #endif
}()

public let toolchainPath: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["TOOLCHAIN_PATH"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    #if os(macOS)
    let swiftcPath = try! AbsolutePath(
        validating: sh("xcrun", "--find", "swift").stdout.spm_chomp()
    )
    #elseif os(Windows)
    let swiftcPath = try! AbsolutePath(validating: sh("where.exe", "swift.exe").stdout.spm_chomp())
    #else
    let swiftcPath = try! AbsolutePath(validating: sh("which", "swift").stdout.spm_chomp())
    #endif
    let toolchainPath = swiftcPath.parentDirectory.parentDirectory.parentDirectory
    return toolchainPath
}()

public let clang: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["CLANG_PATH"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    let clangPath = toolchainPath.appending(components: "usr", "bin", "clang")
    return clangPath
}()

public let xcodebuild: AbsolutePath = {
    #if os(macOS)
    let xcodebuildPath = try! AbsolutePath(
        validating: sh("xcrun", "--find", "xcodebuild").stdout.spm_chomp()
    )
    return xcodebuildPath
    #else
    fatalError("should not be used on other platforms than macOS")
    #endif
}()

public let swift: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFT_PATH"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    let swiftPath = toolchainPath.appending(components: "usr", "bin", "swift")
    return swiftPath
}()

public let swiftc: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFTC_PATH"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    let swiftcPath = toolchainPath.appending(components: "usr", "bin", "swiftc")
    return swiftcPath
}()

public let lldb: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["LLDB_PATH"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    // We check if it exists because lldb doesn't exist in Xcode's default toolchain.
    let toolchainLLDBPath = toolchainPath.appending(components: "usr", "bin", "lldb")
    if localFileSystem.exists(toolchainLLDBPath) {
        return toolchainLLDBPath
    }

    #if os(macOS)
    let lldbPath = try! AbsolutePath(
        validating: sh("xcrun", "--find", "lldb").stdout.spm_chomp()
    )
    return lldbPath
    #else
    fatalError("LLDB_PATH environment variable required")
    #endif
}()

public let swiftpmBinaryDirectory: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFTPM_CUSTOM_BIN_DIR"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    return swift.parentDirectory
}()

public let swiftBuild: AbsolutePath = swiftpmBinaryDirectory.appending(component: "swift-build")

public let swiftPackage: AbsolutePath = swiftpmBinaryDirectory.appending(component: "swift-package")

public let swiftTest: AbsolutePath = swiftpmBinaryDirectory.appending(component: "swift-test")

public let swiftRun: AbsolutePath = swiftpmBinaryDirectory.appending(component: "swift-run")

public let isSelfHosted: Bool = {
    ProcessInfo.processInfo.environment["SWIFTCI_IS_SELF_HOSTED"] != nil
}()

@discardableResult
public func sh(
    _ arguments: CustomStringConvertible...,
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> (stdout: String, stderr: String) {
    let result = try _sh(arguments, env: env, file: file, line: line)
    let stdout = try result.utf8Output()
    let stderr = try result.utf8stderrOutput()

    if result.exitStatus != .terminated(code: 0) {
        Issue
            .record(
                Comment(
                    "Command failed with exit code: \(result.exitStatus) - \(result.integrationTests_debugDescription)"
                )
            )
    }

    return (stdout, stderr)
}

@discardableResult
public func shFails(
    _ arguments: CustomStringConvertible...,
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> (stdout: String, stderr: String) {
    let result = try _sh(arguments, env: env, file: file, line: line)
    let stdout = try result.utf8Output()
    let stderr = try result.utf8stderrOutput()

    if result.exitStatus == .terminated(code: 0) {
        Issue
            .record(
                Comment(
                    "Command unexpectedly succeeded with exit code: \(result.exitStatus) - \(result.integrationTests_debugDescription)"
                )
            )
    }

    return (stdout, stderr)
}

@discardableResult
public func _sh(
    _ arguments: [CustomStringConvertible],
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> ProcessResult {
    var environment = ProcessInfo.processInfo.environment

    if let sdkRoot {
        environment["SDKROOT"] = sdkRoot.pathString
    }

    environment.merge(env, uniquingKeysWith: { $1 })

    let result = try Process.popen(
        arguments: arguments.map(\.description), environment: environment
    )
    return result
}

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
        let fixtureSubpath = try RelativePath(validating: name)
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
            let fixtureDir = try AbsolutePath(
                validating: "../../../Fixtures/\(name)",
                relativeTo: AbsolutePath(validating: #file)
            )

            // Check that the fixture is really there.
            guard localFileSystem.isDirectory(fixtureDir) else {
                Issue.record(Comment("No such fixture: \(fixtureDir)"))
                return
            }

            // The fixture contains either a checkout or just a Git directory.
            if localFileSystem.isFile(fixtureDir.appending(component: "Package.swift")) {
                // It's a single package, so copy the whole directory as-is.
                let dstDir = tmpDirPath.appending(component: copyName)
                #if os(Windows)
                try localFileSystem.copy(from: fixtureDir, to: dstDir)
                #else
                try systemQuietly("cp", "-R", "-H", fixtureDir.pathString, dstDir.pathString)
                #endif

                // Invoke the block, passing it the path of the copied fixture.
                try body(dstDir)
            } else {
                // Copy each of the package directories and construct a git repo in it.
                for fileName in try! localFileSystem.getDirectoryContents(fixtureDir).sorted() {
                    let srcDir = fixtureDir.appending(component: fileName)
                    guard localFileSystem.isDirectory(srcDir) else { continue }
                    let dstDir = tmpDirPath.appending(component: fileName)
                    #if os(Windows)
                    try localFileSystem.copy(from: srcDir, to: dstDir)
                    #else
                    try systemQuietly("cp", "-R", "-H", srcDir.pathString, dstDir.pathString)
                    #endif
                    initGitRepo(dstDir, tag: "1.2.3", addFile: false)
                }

                // Invoke the block, passing it the path of the copied fixture.
                try body(tmpDirPath)
            }
        }
    } catch {
        Issue.record(error)
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
            let file = dir.appending(component: "file.swift")
            try localFileSystem.writeFileContents(file, bytes: "")
        }

        try systemQuietly([Git.tool, "-C", dir.pathString, "init"])
        try systemQuietly([
            Git.tool, "-C", dir.pathString, "config", "user.email", "example@example.com",
        ])
        try systemQuietly([
            Git.tool, "-C", dir.pathString, "config", "user.name", "Example Example",
        ])
        try systemQuietly([Git.tool, "-C", dir.pathString, "config", "commit.gpgsign", "false"])
        try systemQuietly([Git.tool, "-C", dir.pathString, "add", "."])
        try systemQuietly([Git.tool, "-C", dir.pathString, "commit", "-m", "Add some files."])

        for tag in tags {
            try systemQuietly([Git.tool, "-C", dir.pathString, "tag", tag])
        }
    } catch {
        Issue.record(error)
    }
}

public func binaryTargetsFixture(_ closure: (AbsolutePath) throws -> Void) throws {
    fixture(name: "BinaryTargets") { fixturePath in
        let inputsPath = fixturePath.appending(component: "Inputs")
        let packagePath = fixturePath.appending(component: "TestBinary")

        // Generating StaticLibrary.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "StaticLibrary")
            let sourcePath = subpath.appending(component: "StaticLibrary.m")
            let headersPath = subpath.appending(component: "include")
            let libraryPath = tmpDir.appending(component: "libStaticLibrary.a")
            try sh(
                clang, "-c", sourcePath, "-I", headersPath, "-fobjc-arc", "-fmodules", "-o",
                libraryPath
            )
            let xcframeworkPath = packagePath.appending(component: "StaticLibrary.xcframework")
            try sh(
                xcodebuild, "-create-xcframework", "-library", libraryPath, "-headers", headersPath,
                "-output", xcframeworkPath
            )
        }

        // Generating DynamicLibrary.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "DynamicLibrary")
            let sourcePath = subpath.appending(component: "DynamicLibrary.m")
            let headersPath = subpath.appending(component: "include")
            let libraryPath = tmpDir.appending(component: "libDynamicLibrary.dylib")
            try sh(
                clang, sourcePath, "-I", headersPath, "-fobjc-arc", "-fmodules", "-dynamiclib",
                "-o", libraryPath
            )
            let xcframeworkPath = packagePath.appending(component: "DynamicLibrary.xcframework")
            try sh(
                xcodebuild, "-create-xcframework", "-library", libraryPath, "-headers", headersPath,
                "-output", xcframeworkPath
            )
        }

        // Generating SwiftFramework.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "SwiftFramework")
            let projectPath = subpath.appending(component: "SwiftFramework.xcodeproj")
            try sh(
                xcodebuild, "-project", projectPath, "-scheme", "SwiftFramework",
                "-derivedDataPath", tmpDir, "COMPILER_INDEX_STORE_ENABLE=NO"
            )
            let frameworkPath = try AbsolutePath(
                validating: "Build/Products/Debug/SwiftFramework.framework",
                relativeTo: tmpDir
            )
            let xcframeworkPath = packagePath.appending(component: "SwiftFramework.xcframework")
            try sh(
                xcodebuild, "-create-xcframework", "-framework", frameworkPath, "-output",
                xcframeworkPath
            )
        }

        try closure(packagePath)
    }
}

extension ProcessResult {
    var integrationTests_debugDescription: String {
        """
        command: \(arguments.map(\.description).joined(separator: " "))

        stdout:
        \((try? utf8Output()) ?? "")

        stderr:
        \((try? utf8stderrOutput()) ?? "")
        """
    }
}
