/*
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic
import XCTest

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
    let swiftcPath = try! AbsolutePath(sh("xcrun", "--find", "swift").stdout)
    let toolchainPath = swiftcPath.parentDirectory.parentDirectory.parentDirectory
    return toolchainPath
  #else
    fatalError("TOOLCHAIN_PATH environment variable required")
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
    let lldbPath = try! AbsolutePath(sh("xcrun", "--find", "lldb").stdout)
    return lldbPath
  #else
    fatalError("LLDB_PATH environment variable required")
  #endif
}()

let swiftpmBinaryDirectory: AbsolutePath = {
    if let environmentPath = ProcessInfo.processInfo.environment["SWIFTPM_BUILD_DIR"] {
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
func sh(_ arguments: CustomStringConvertible..., file: StaticString = #file, line: UInt = #line) throws
    -> (stdout: String, stderr: String)
{
    var environment = ProcessInfo.processInfo.environment

    if let sdkRoot = sdkRoot {
        environment["SDKROOT"] = sdkRoot.pathString
    }

    let result = try Process.popen(arguments: arguments.map({ $0.description }), environment: environment)
    let stdout = try result.utf8Output()
    let stderr = try result.utf8stderrOutput()
    XCTAssertEqual(result.exitStatus, .terminated(code: 0), stderr, file: file, line: line)
    return (stdout, stderr)
}
