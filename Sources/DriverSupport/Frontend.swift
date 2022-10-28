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

import protocol TSCBasic.FileSystem

public struct DriverSupport {
    public static func checkSupportedFrontendFlags(flags: Set<String>, fileSystem: FileSystem) -> Bool {
        do {
            let executor = try SPMSwiftDriverExecutor(resolver: ArgsResolver(fileSystem: fileSystem), fileSystem: fileSystem, env: [:])
            let driver = try Driver(args: ["swiftc"], executor: executor)
            return driver.supportedFrontendFlags.intersection(flags) == flags
        } catch {
            return false
        }
    }
}
