//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import _Concurrency
import Build
import CoreCommands
import Dispatch

@_spi(SwiftPMInternal)
import DriverSupport

import Foundation
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import XCBuildSupport

import struct TSCBasic.KeyedPair
import var TSCBasic.stdoutStream
import enum TSCBasic.GraphError
import struct TSCBasic.OrderedSet
import enum TSCUtility.Diagnostics
import struct TSCUtility.Version

@main
struct SwiftBootstrapCommand: AsyncSwiftCommand {
    /// If the test should be built.
    @Flag(help: "Build both source and test targets")
    var buildTests: Bool = false

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    var workspaceLoaderProvider: CoreCommands.WorkspaceLoaderProvider {
        { _, _ in EmptyWorkspaceLoader() }
    }

    static let configuration = CommandConfiguration(
        commandName: "swift-bootstrap",
        abstract: "Bootstrapping build tool, only use in the context of bootstrapping SwiftPM itself",
        shouldDisplay: false
    )

    public init() {}

    public func run(_ swiftCommandState: SwiftCommandState) async throws {
        let buildSystem = try await swiftCommandState.createBuildSystem(traitConfiguration: .init())
        try await buildSystem.build(subset: self.buildTests ? .allIncludingTests : .allExcludingTests)
    }
}

private struct EmptyWorkspaceLoader: WorkspaceLoader {
    func load(workspace: AbsolutePath) throws -> [AbsolutePath] {
        []
    }
}
