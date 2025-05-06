//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import CoreCommands
import Workspace

extension SwiftPackageCommand {
    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            try swiftCommandState.getActiveWorkspace().clean(observabilityScope: swiftCommandState.observabilityScope)
        }
    }

    struct PurgeCache: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Purge the global repository cache.")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            try swiftCommandState.getActiveWorkspace().purgeCache(observabilityScope: swiftCommandState.observabilityScope)
        }
    }

    struct Reset: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache/build directory")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try await swiftCommandState.getActiveWorkspace().reset(observabilityScope: swiftCommandState.observabilityScope)
        }
    }
}
