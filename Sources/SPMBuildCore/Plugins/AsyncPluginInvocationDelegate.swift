//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct Basics.Diagnostic
import typealias Basics.EnvironmentVariables
import struct Foundation.Data

public protocol AsyncPluginInvocationDelegate {
    /// Called before a plugin is compiled. This call is always followed by a `pluginCompilationEnded()`, but is
    /// mutually exclusive with `pluginCompilationWasSkipped()` (which is called if the plugin didn't need to be
    /// recompiled).
    func pluginCompilationStarted(commandLine: [String], environment: EnvironmentVariables)

    /// Called after a plugin is compiled. This call always follows a `pluginCompilationStarted()`, but is mutually
    /// exclusive with `pluginCompilationWasSkipped()` (which is called if the plugin didn't need to be recompiled).
    func pluginCompilationEnded(result: PluginCompilationResult)

    /// Called if a plugin didn't need to be recompiled. This call is always mutually exclusive with
    /// `pluginCompilationStarted()` and `pluginCompilationEnded()`.
    func pluginCompilationWasSkipped(cachedResult: PluginCompilationResult)

    /// Called for each piece of textual output data emitted by the plugin. Note that there is no guarantee that the
    /// data begins and ends on a UTF-8 byte sequence boundary (much less on a line boundary) so the delegate should
    /// buffer partial data as appropriate.
    func pluginEmittedOutput(_: Data)

    /// Called when a plugin emits a diagnostic through the PackagePlugin APIs.
    func pluginEmittedDiagnostic(_: Basics.Diagnostic)

    /// Called when a plugin emits a progress message through the PackagePlugin APIs.
    func pluginEmittedProgress(_: String)

    /// Called when a plugin defines a build command through the PackagePlugin APIs.
    func pluginDefinedBuildCommand(
        displayName: String?,
        executable: AbsolutePath,
        arguments: [String],
        environment: [String: String],
        workingDirectory: AbsolutePath?,
        inputFiles: [AbsolutePath],
        outputFiles: [AbsolutePath]
    )

    /// Called when a plugin defines a prebuild command through the PackagePlugin APIs.
    func pluginDefinedPrebuildCommand(
        displayName: String?,
        executable: AbsolutePath,
        arguments: [String],
        environment: [String: String],
        workingDirectory: AbsolutePath?,
        outputFilesDirectory: AbsolutePath
    ) -> Bool

    /// Called when a plugin requests a build operation through the PackagePlugin APIs.
    func pluginRequestedBuildOperation(
        subset: PluginInvocationBuildSubset,
        parameters: PluginInvocationBuildParameters
    ) async throws -> PluginInvocationBuildResult

    /// Called when a plugin requests a test operation through the PackagePlugin APIs.
    func pluginRequestedTestOperation(
        subset: PluginInvocationTestSubset,
        parameters: PluginInvocationTestParameters
    ) async throws -> PluginInvocationTestResult

    /// Called when a plugin requests that the host computes and returns symbol graph information for a particular target.
    func pluginRequestedSymbolGraph(
        forTarget name: String,
        options: PluginInvocationSymbolGraphOptions
    ) async throws -> PluginInvocationSymbolGraphResult
}


public extension AsyncPluginInvocationDelegate {
    func pluginDefinedBuildCommand(
        displayName: String?,
        executable: AbsolutePath,
        arguments: [String],
        environment: [String : String],
        workingDirectory: AbsolutePath?,
        inputFiles: [AbsolutePath],
        outputFiles: [AbsolutePath]
    ) {
    }

    func pluginDefinedPrebuildCommand(
        displayName: String?,
        executable: AbsolutePath,
        arguments: [String],
        environment: [String : String],
        workingDirectory: AbsolutePath?,
        outputFilesDirectory: AbsolutePath
    ) -> Bool {
        return true
    }
}
