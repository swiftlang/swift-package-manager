//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
import PackageLoading
import PackageGraph
import TSCBasic
import struct TSCUtility.Triple

/// Implements the mechanics of running and communicating with a plugin (implemented as a set of Swift source files). In most environments this is done by compiling the code to an executable, invoking it as a sandboxed subprocess, and communicating with it using pipes. Specific implementations are free to implement things differently, however.
public protocol PluginScriptRunner {
    
    /// Public protocol function that starts compiling the plugin script to an exectutable. The name is used as the basename for the executable and auxiliary files. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not of the target to which it is being applied). This function returns immediately and then calls the completion handler on the callbackq queue when compilation ends.
    func compilePluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    )

    /// Implements the mechanics of running a plugin script implemented as a set of Swift source files, for use
    /// by the package graph when it is evaluating package plugins.
    ///
    /// The `sources` refer to the Swift source files and are accessible in the provided `fileSystem`. The input is
    /// a PluginScriptRunnerInput structure.
    ///
    /// The text output callback handler will receive free-form output from the script as it's running. Structured
    /// diagnostics emitted by the plugin will be added to the observability scope.
    ///
    /// Every concrete implementation should cache any intermediates as necessary to avoid redundant work.
    func runPluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptRunnerDelegate,
        completion: @escaping (Result<Int32, Error>) -> Void
    )

    /// Returns the Triple that represents the host for which plugin script tools should be built, or for which binary
    /// tools should be selected.
    var hostTriple: Triple { get }
}

/// Protocol by which `PluginScriptRunner.runPluginScript()` communicates back to the caller.
public protocol PluginScriptRunnerDelegate {
    /// Called for each piece of textual output data emitted by the plugin. Note that there is no guarantee that the data begins and ends on a UTF-8 byte sequence boundary (much less on a line boundary) so the delegate should buffer partial data as appropriate.
    func handleOutput(data: Data)
    
    /// Called for each length-delimited message received from the plugin. The `responder` is closure that can be used to send one or more messages in reply.
    func handleMessage(data: Data, responder: @escaping (Data) -> Void) throws
}


/// The result of compiling a plugin. The executable path will only be present if the compilation succeeds, while the other properties are present in all cases.
public struct PluginCompilationResult {
    /// Whether compilation succeeded.
    public var succeeded: Bool
    
    /// Complete compiler command line.
    public var commandLine: [String]
    
    /// Path of the compiled executable.
    public var executableFile: AbsolutePath

    /// Path of the libClang diagnostics file emitted by the compiler.
    public var diagnosticsFile: AbsolutePath
    
    /// Any output emitted by the compiler (stdout and stderr combined).
    public var compilerOutput: String
    
    /// Whether the compilation result came from the cache (false means that the compiler did run).
    public var cached: Bool
    
    public init(
        succeeded: Bool,
        commandLine: [String],
        executableFile: AbsolutePath,
        diagnosticsFile: AbsolutePath,
        compilerOutput: String,
        cached: Bool
    ) {
        self.succeeded = succeeded
        self.commandLine = commandLine
        self.executableFile = executableFile
        self.diagnosticsFile = diagnosticsFile
        self.compilerOutput = compilerOutput
        self.cached = cached
    }
}

extension PluginCompilationResult: CustomStringConvertible {
    public var description: String {
        let output = compilerOutput.spm_chomp()
        return output + (output.isEmpty || output.hasSuffix("\n") ? "" : "\n")
    }
}

extension PluginCompilationResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
            <PluginCompilationResult(
                succeeded: \(succeeded),
                commandLine: \(commandLine.map{ $0.spm_shellEscaped() }.joined(separator: " ")),
                executable: \(executableFile.prettyPath())
                diagnostics: \(diagnosticsFile.prettyPath())
                compilerOutput: \(compilerOutput.spm_shellEscaped())
            )>
            """
    }
}
