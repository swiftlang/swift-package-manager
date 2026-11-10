//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
@testable import SPMBuildCore

public struct MockPluginScriptRunner: PluginScriptRunner {
    let genMessages: (
        _ initialMessage: HostToPluginMessage
    ) -> [PluginToHostMessage]

    public init(genMessages: @escaping (_: HostToPluginMessage) -> [PluginToHostMessage]) {
        self.genMessages = genMessages
    }

    public func compilePluginScript(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        toolsVersion: PackageModel.ToolsVersion,
        workers: UInt32,
        observabilityScope: Basics.ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: any SPMBuildCore.PluginScriptCompilerDelegate,
        completion: @escaping (Result<SPMBuildCore.PluginCompilationResult, any Error>) -> Void)
    {
        callbackQueue.sync {
            completion(.failure(StringError("unimplemented")))
        }
    }

    public func buildCommandLine(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope?
    ) -> (commandLine: [String], execName: String, execFilePath: Basics.AbsolutePath, diagFilePath: Basics.AbsolutePath) {
        fatalError("Not implemented")
    }

    public func runPluginScript(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: PackageModel.ToolsVersion,
        workingDirectory: Basics.AbsolutePath,
        writableDirectories: [Basics.AbsolutePath],
        readOnlyDirectories: [Basics.AbsolutePath],
        allowNetworkConnections: [Basics.SandboxNetworkPermission],
        workers: UInt32,
        fileSystem: any Basics.FileSystem,
        observabilityScope: Basics.ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: any SPMBuildCore.PluginScriptCompilerDelegate & SPMBuildCore.PluginScriptRunnerDelegate
    ) async throws -> Int32 {
        let decoder = JSONDecoder.makeWithDefaults()
        let encoder = JSONEncoder(outputFormatting: .prettyPrinted)

        let initial = try decoder.decode(HostToPluginMessage.self, from: initialMessage)

        for message in genMessages(initial) {
            let data = try encoder.encode(message)
            _ = try await delegate.handleMessage(data: data)
        }
        return 0
    }

    public var hostTriple: Triple {
        get throws {
            return try UserToolchain.default.targetTriple
        }
    }
}

extension HostToPluginMessage.InputContext {
    public func path(for id: WireInput.URL.Id) -> Basics.AbsolutePath {
        // Compose a path based on an optional base path and a subpath.
        let wirePath = paths[id]
        let basePath = paths[id].baseURLId.map{ self.path(for: $0) }
        let path: Basics.AbsolutePath
        if let basePath {
            path = basePath.appending(wirePath.subpath)
        } else {
            path = AbsolutePath.root.appending(wirePath.subpath)
        }
        return path
    }

    public func path(for file: File) -> Basics.AbsolutePath {
        let dir = path(for: file.basePathId)
        return dir.appending(file.name)
    }
}
