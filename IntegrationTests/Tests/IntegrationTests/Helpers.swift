/*
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest
import TSCBasic
import TSCUtility
import TSCTestSupport

let sdkRoot: AbsolutePath? = {
    if let environmentPath = ProcessInfo.processInfo.environment["SDK_ROOT"] {
        return AbsolutePath(environmentPath)
    }

  #if os(macOS)
    let result = try! Process.popen(arguments: ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    let sdkRoot = try! AbsolutePath(result.utf8Output().spm_chomp())
    return sdkRoot
  #else
    return nil
  #endif
}()

let toolchainPath: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["TOOLCHAIN_PATH"] {
        return AbsolutePath(environmentPath)
    }

  #if os(macOS)
    let swiftcPath = try! AbsolutePath(sh("xcrun", "--find", "swift").stdout.spm_chomp())
    let toolchainPath = swiftcPath.parentDirectory.parentDirectory.parentDirectory
    return toolchainPath
  #else
    fatalError("TOOLCHAIN_PATH environment variable required")
  #endif
}()

let clang: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["CLANG_PATH"] {
        return AbsolutePath(environmentPath)
    }

    let clangPath = toolchainPath.appending(components: "usr", "bin", "clang")
    return clangPath
}()

let xcodebuild: AbsolutePath = {
    #if os(macOS)
      let xcodebuildPath = try! AbsolutePath(sh("xcrun", "--find", "xcodebuild").stdout.spm_chomp())
      return xcodebuildPath
    #else
      fatalError("should not be used on other platforms than macOS")
    #endif
}()

let swift: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFT_PATH"] {
        return AbsolutePath(environmentPath)
    }

    let swiftPath = toolchainPath.appending(components: "usr", "bin", "swift")
    return swiftPath
}()

let swiftc: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFTC_PATH"] {
        return AbsolutePath(environmentPath)
    }

    let swiftcPath = toolchainPath.appending(components: "usr", "bin", "swiftc")
    return swiftcPath
}()

let lldb: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["LLDB_PATH"] {
        return AbsolutePath(environmentPath)
    }

    // We check if it exists because lldb doesn't exist in Xcode's default toolchain.
    let toolchainLLDBPath = toolchainPath.appending(components: "usr", "bin", "lldb")
    if localFileSystem.exists(toolchainLLDBPath) {
        return toolchainLLDBPath
    }

    #if os(macOS)
    let lldbPath = try! AbsolutePath(sh("xcrun", "--find", "lldb").stdout.spm_chomp())
    return lldbPath
  #else
    fatalError("LLDB_PATH environment variable required")
  #endif
}()

let swiftpmBinaryDirectory: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFTPM_BIN_DIR"] {
        return AbsolutePath(environmentPath)
    }

    return swift.parentDirectory
}()

let swiftBuild: AbsolutePath = {
    return swiftpmBinaryDirectory.appending(component: "swift-build")
}()

let swiftPackage: AbsolutePath = {
    return swiftpmBinaryDirectory.appending(component: "swift-package")
}()

let swiftTest: AbsolutePath = {
    return swiftpmBinaryDirectory.appending(component: "swift-test")
}()

let swiftRun: AbsolutePath = {
    return swiftpmBinaryDirectory.appending(component: "swift-run")
}()

@discardableResult
func sh(
    _ arguments: CustomStringConvertible...,
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> (stdout: String, stderr: String) {
    let result = try _sh(arguments, env: env, file: file, line: line)
    let stdout = try result.utf8Output()
    let stderr = try result.utf8stderrOutput()
    XCTAssertEqual(result.exitStatus, .terminated(code: 0), stderr, file: file, line: line)
    return (stdout, stderr)
}

@discardableResult
func shFails(
    _ arguments: CustomStringConvertible...,
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> (stdout: String, stderr: String) {
    let result = try _sh(arguments, env: env, file: file, line: line)
    let stdout = try result.utf8Output()
    let stderr = try result.utf8stderrOutput()
    XCTAssertNotEqual(result.exitStatus, .terminated(code: 0), stderr, file: file, line: line)
    return (stdout, stderr)
}

@discardableResult
func _sh(
    _ arguments: [CustomStringConvertible],
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> ProcessResult {
    var environment = ProcessInfo.processInfo.environment

    if let sdkRoot = sdkRoot {
        environment["SDKROOT"] = sdkRoot.pathString
    }

    environment.merge(env, uniquingKeysWith: { $1 })

    let result = try Process.popen(arguments: arguments.map { $0.description }, environment: environment)
    return result
}

/// Test-helper function that runs a block of code on a copy of a test fixture
/// package.  The copy is made into a temporary directory, and the block is
/// given a path to that directory.  The block is permitted to modify the copy.
/// The temporary copy is deleted after the block returns.  The fixture name may
/// contain `/` characters, which are treated as path separators, exactly as if
/// the name were a relative path.
func fixture(
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
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

/// Test-helper function that creates a new Git repository in a directory.  The new repository will contain
/// exactly one empty file unless `addFile` is `false`, and if a tag name is provided, a tag with that name will be
/// created.
func initGitRepo(
    _ dir: AbsolutePath,
    tag: String? = nil,
    addFile: Bool = true,
    file: StaticString = #file,
    line: UInt = #line
) {
    initGitRepo(dir, tags: tag.flatMap({ [$0] }) ?? [], addFile: addFile, file: file, line: line)
}

func initGitRepo(
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
        try systemQuietly([Git.tool, "-C", dir.pathString, "add", "."])
        try systemQuietly([Git.tool, "-C", dir.pathString, "commit", "-m", "Add some files."])

        for tag in tags {
            try systemQuietly([Git.tool, "-C", dir.pathString, "tag", tag])
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func binaryTargetsFixture(_ closure: (AbsolutePath) throws -> Void) throws {
    fixture(name: "BinaryTargets") { prefix in
        let inputsPath = prefix.appending(component: "Inputs")
        let packagePath = prefix.appending(component: "TestBinary")

        // Generating StaticLibrary.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "StaticLibrary")
            let sourcePath = subpath.appending(component: "StaticLibrary.m")
            let headersPath = subpath.appending(component: "include")
            let libraryPath = tmpDir.appending(component: "libStaticLibrary.a")
            try sh(clang, "-c", sourcePath, "-I", headersPath, "-fobjc-arc", "-fmodules", "-o", libraryPath)
            let xcframeworkPath = packagePath.appending(component: "StaticLibrary.xcframework")
            try sh(xcodebuild, "-create-xcframework", "-library", libraryPath, "-headers", headersPath, "-output", xcframeworkPath)
        }

        // Generating DynamicLibrary.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "DynamicLibrary")
            let sourcePath = subpath.appending(component: "DynamicLibrary.m")
            let headersPath = subpath.appending(component: "include")
            let libraryPath = tmpDir.appending(component: "libDynamicLibrary.dylib")
            try sh(clang, sourcePath, "-I", headersPath, "-fobjc-arc", "-fmodules", "-dynamiclib", "-o", libraryPath)
            let xcframeworkPath = packagePath.appending(component: "DynamicLibrary.xcframework")
            try sh(xcodebuild, "-create-xcframework", "-library", libraryPath, "-headers", headersPath, "-output", xcframeworkPath)
        }

        // Generating SwiftFramework.xcframework.
        try withTemporaryDirectory { tmpDir in
            let subpath = inputsPath.appending(component: "SwiftFramework")
            let projectPath = subpath.appending(component: "SwiftFramework.xcodeproj")
            try sh(xcodebuild, "-project", projectPath, "-scheme", "SwiftFramework", "-derivedDataPath", tmpDir, "COMPILER_INDEX_STORE_ENABLE=NO")
            let frameworkPath = tmpDir.appending(RelativePath("Build/Products/Debug/SwiftFramework.framework"))
            let xcframeworkPath = packagePath.appending(component: "SwiftFramework.xcframework")
            try sh(xcodebuild, "-create-xcframework", "-framework", frameworkPath, "-output", xcframeworkPath)
        }

        try closure(packagePath)
    }
}

func XCTSkip() throws {
    throw XCTSkip()
}
