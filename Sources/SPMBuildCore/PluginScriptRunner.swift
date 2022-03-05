/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import PackageModel
import PackageLoading
import PackageGraph
import TSCBasic
import struct TSCUtility.Triple

/// Implements the mechanics of running and communicating with a plugin (implemented as a set of Swift source files). In most environments this is done by compiling the code to an executable, invoking it as a sandboxed subprocess, and communicating with it using pipes. Specific implementations are free to implement things differently, however.
public protocol PluginScriptRunner {
    
    /// Public protocol function that starts compiling the plugin script to an exectutable. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not of the target to which it is being applied). This function returns immediately and then calls the completion handler on the callbackq queue when compilation ends.
    func compilePluginScript(
        sources: Sources,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) throws -> PluginCompilationResult

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
        sources: Sources,
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
    /// Process result of invoking the Swift compiler to produce the executable (contains command line, environment, exit status, and any output).
    public var compilerResult: ProcessResult?
    
    /// Path of the libClang diagnostics file emitted by the compiler (even if compilation succeded, it might contain warnings).
    public var diagnosticsFile: AbsolutePath
    
    /// Path of the compiled executable.
    public var compiledExecutable: AbsolutePath

    /// Whether the compilation result was cached.
    public var wasCached: Bool

    public init(compilerResult: ProcessResult?, diagnosticsFile: AbsolutePath, compiledExecutable: AbsolutePath, wasCached: Bool) {
        self.compilerResult = compilerResult
        self.diagnosticsFile = diagnosticsFile
        self.compiledExecutable = compiledExecutable
        self.wasCached = wasCached
    }
    
    /// Returns true if and only if the compilation succeeded or was cached
    public var succeeded: Bool {
        return self.wasCached || self.compilerResult?.exitStatus == .terminated(code: 0)
    }
}

extension PluginCompilationResult: CustomStringConvertible {
    public var description: String {
        let stdout = (try? compilerResult?.utf8Output()) ?? ""
        let stderr = (try? compilerResult?.utf8stderrOutput()) ?? ""
        let output = (stdout + stderr).spm_chomp()
        return output + (output.isEmpty || output.hasSuffix("\n") ? "" : "\n")
    }
}

extension PluginCompilationResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
            <PluginCompilationResult(
                exitStatus: \(compilerResult.map{ "\($0.exitStatus)" } ?? "-"),
                stdout: \((try? compilerResult?.utf8Output()) ?? ""),
                stderr: \((try? compilerResult?.utf8stderrOutput()) ?? ""),
                executable: \(compiledExecutable.prettyPath())
            )>
            """
    }
}
