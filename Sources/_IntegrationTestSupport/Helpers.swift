/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import Testing
import _InternalTestSupport
import enum TSCUtility.Git
import Basics

package typealias ShReturnType = (stdout: String, stderr: String, returnCode: AsyncProcessResult.ExitStatus)

public let sdkRoot: AbsolutePath? = {
    if let environmentPath = ProcessInfo.processInfo.environment["SDK_ROOT"] {
        return try! AbsolutePath(validating: environmentPath)
    }

    #if os(macOS)
    let result = try! AsyncProcess.popen(arguments: ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
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

@discardableResult
package func sh(
    _ arguments: CustomStringConvertible...,
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> ShReturnType {
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

    return (stdout, stderr, result.exitStatus)
}

@discardableResult
package func _sh(
    _ arguments: [CustomStringConvertible],
    env: [String: String] = [:],
    file: StaticString = #file,
    line: UInt = #line
) throws -> AsyncProcessResult {
    var environment = Environment()

    if let sdkRoot {
        environment["SDKROOT"] = sdkRoot.pathString
    }

    for (varName, value) in env {
        environment[EnvironmentKey(varName)] = value
    }

    let result = try AsyncProcess.popen(
        arguments: arguments.map(\.description), environment: environment
    )
    return result
}

public func binaryTargetsFixture(_ closure: (AbsolutePath) async throws -> Void) async throws {
    try await fixture(name: "BinaryTargets") { fixturePath in
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

        try await closure(packagePath)
    }
}

extension AsyncProcessResult {
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