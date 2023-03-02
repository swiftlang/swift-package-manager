//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SwiftDriver
import protocol TSCBasic.FileSystem
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import struct TSCBasic.ProcessResult

public class DriverSupport {
    private var flagsMap = ThreadSafeBox<[String: Set<String>]>()
    public init() {}

    // This checks _frontend_ supported flags, which are not necessarily supported in the driver.
    public func checkSupportedFrontendFlags(
        flags: Set<String>,
        toolchain: PackageModel.Toolchain,
        fileSystem: FileSystem
    ) -> Bool {
        let trimmedFlagSet = Set(flags.map { $0.trimmingCharacters(in: ["-"]) })
        let swiftcPathString = toolchain.swiftCompilerPath.pathString

        if let entry = flagsMap.get(), let cachedSupportedFlagSet = entry[swiftcPathString + "-frontend"] {
            return cachedSupportedFlagSet.intersection(trimmedFlagSet) == trimmedFlagSet
        }
        do {
            let executor = try SPMSwiftDriverExecutor(
                resolver: ArgsResolver(fileSystem: fileSystem),
                fileSystem: fileSystem,
                env: [:]
            )
            let driver = try Driver(
                args: ["swiftc"],
                executor: executor,
                compilerExecutableDir: toolchain.swiftCompilerPath.parentDirectory
            )
            let supportedFlagSet = Set(driver.supportedFrontendFlags.map { $0.trimmingCharacters(in: ["-"]) })
            flagsMap.put([swiftcPathString + "-frontend": supportedFlagSet])
            return supportedFlagSet.intersection(trimmedFlagSet) == trimmedFlagSet
        } catch {
            return false
        }
    }

    // This checks if given flags are supported in the built-in toolchain driver. Currently
    // there's no good way to get the supported flags from it, so run `swiftc -h` directly
    // to get the flags and cache the result.
    public func checkToolchainDriverFlags(
        flags: Set<String>,
        toolchain: PackageModel.Toolchain,
        fileSystem: FileSystem
    ) -> Bool {
        let trimmedFlagSet = Set(flags.map { $0.trimmingCharacters(in: ["-"]) })
        let swiftcPathString = toolchain.swiftCompilerPath.pathString

        if let entry = flagsMap.get(), let cachedSupportedFlagSet = entry[swiftcPathString + "-driver"] {
            return cachedSupportedFlagSet.intersection(trimmedFlagSet) == trimmedFlagSet
        }
        do {
            let helpJob = try Process.launchProcess(
                arguments: [swiftcPathString, "-h"],
                env: ProcessEnv.vars
            )
            let processResult = try helpJob.waitUntilExit()
            guard processResult.exitStatus == .terminated(code: 0) else {
                return false
            }
            let helpOutput = try processResult.utf8Output()
            let helpFlags = helpOutput.components(separatedBy: " ").map { $0.trimmingCharacters(in: ["-"]) }
            let supportedFlagSet = Set(helpFlags)
            flagsMap.put([swiftcPathString + "-driver": supportedFlagSet])
            return supportedFlagSet.intersection(trimmedFlagSet) == trimmedFlagSet
        } catch {
            return false
        }
    }
}
