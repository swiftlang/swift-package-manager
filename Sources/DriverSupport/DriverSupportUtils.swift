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

import SwiftDriver
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import struct TSCBasic.ProcessResult

import protocol TSCBasic.FileSystem

public class DriverSupport {
    var supportedDriverFlags: Set<String>?
    public init() {}

    // This checks supported _frontend_ flags, which are not necessarily supported in the driver.
    public static func checkSupportedFrontendFlags(flags: Set<String>, fileSystem: FileSystem) -> Bool {
        do {
            let executor = try SPMSwiftDriverExecutor(resolver: ArgsResolver(fileSystem: fileSystem), fileSystem: fileSystem, env: [:])
            let driver = try Driver(args: ["swiftc"], executor: executor)
            return driver.supportedFrontendFlags.intersection(flags) == flags
        } catch {
            return false
        }
    }

    // Currently there's no good way to get supported flags from the built-in toolchain driver, so call `swiftc -h` directly
    // and save the result so we don't spawn processes repeatedly.
    public func checkSupportedDriverFlags(flags: Set<String>) -> Bool {
        if let supported = supportedDriverFlags {
            let trimmedFlags = flags.map{$0.hasPrefix("-") ? String($0.dropFirst()) : $0}
            return supported.intersection(trimmedFlags).count == flags.count
        }

        do {
            let helpJob = try Process.launchProcess(arguments: ["swiftc", "-h"], env: ProcessEnv.vars)
            let processResult = try helpJob.waitUntilExit()
            guard processResult.exitStatus == .terminated(code: 0) else {
                return false
            }
            let helpOutput = try processResult.utf8Output()
            let helpFlags = helpOutput.components(separatedBy: " ").filter{$0.hasPrefix("-")}.map{String($0.dropFirst())}
            let helpFlagsSet = Set(helpFlags)
            supportedDriverFlags = helpFlagsSet
            let trimmedFlags = flags.map{$0.hasPrefix("-") ? String($0.dropFirst()) : $0}
            return helpFlagsSet.intersection(trimmedFlags).count == flags.count
        } catch {
            return false
        }
    }
}
