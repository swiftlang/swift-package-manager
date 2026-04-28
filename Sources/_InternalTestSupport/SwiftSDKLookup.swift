//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel

import class Basics.AsyncProcess

/// Returns the compiler tag reported by `swiftc -print-target-info`, used as the prefix of
/// installed Swift SDK artifact IDs (e.g. `swift-6.2-DEVELOPMENT-SNAPSHOT-2025-XX-XX-a`).
package func swiftCompilerTag(compilerPath: AbsolutePath) async -> String? {
    guard let result = try? await AsyncProcess.popen(args: compilerPath.pathString, "-print-target-info") else {
        return nil
    }
    guard result.exitStatus == .terminated(code: 0) else {
        return nil
    }
    struct SwiftPrintTargetInfo: Decodable {
        var swiftCompilerTag: String
    }
    return try? JSONDecoder().decode(SwiftPrintTargetInfo.self, from: result.utf8Output()).swiftCompilerTag
}

/// Returns the path to the single toolchain installed under `/github/home/.swift-toolchains`
/// when running inside the standard Swift GitHub Actions runner, or nil otherwise.
package func githubActionsToolchain() -> AbsolutePath? {
    let userToolchainsDir = AbsolutePath("/github/home/.swift-toolchains")
    let userToolchains = try? FileManager.default.contentsOfDirectory(atPath: userToolchainsDir.pathString)
    guard let userToolchains, userToolchains.count == 1 else {
        return nil
    }
    return userToolchainsDir.appending(component: userToolchains[0])
}

/// Looks up an installed Swift SDK by running `swift sdk list` and returning the first artifact ID
/// whose suffix (following the compiler tag prefix) satisfies `predicate`.
package func findSwiftSDK(
    compilerPath: AbsolutePath,
    where predicate: (_ suffix: String) -> Bool
) async -> String? {
    guard let compilerTag = await swiftCompilerTag(compilerPath: compilerPath) else {
        return nil
    }
    let prefix = "\(compilerTag)_"
    guard let result = try? await SwiftPM.sdk.execute(["list"]) else {
        return nil
    }
    let sdks = result.stdout.components(separatedBy: "\n")
        .map { $0.spm_chomp() }
        .filter { !$0.isEmpty }
    return sdks.first { sdk in
        guard sdk.hasPrefix(prefix) else { return false }
        return predicate(String(sdk.dropFirst(prefix.count)))
    }
}

package func findCompilerAndSDKIDForTesting(
    where predicate: (_ suffix: String) -> Bool
) async throws -> (AbsolutePath, String)? {
    let compilerPath: AbsolutePath
    if let githubActionsToolchain = githubActionsToolchain() {
        compilerPath = githubActionsToolchain.appending(components: ["usr", "bin", "swiftc\(ProcessInfo.exeSuffix)"])
    } else {
        compilerPath = try UserToolchain(swiftSDK: SwiftSDK.hostSwiftSDK()).swiftCompilerPath
    }

    guard let sdkID = await findSwiftSDK(compilerPath: compilerPath, where: predicate) else {
        return nil
    }

    return (compilerPath, sdkID)
}
