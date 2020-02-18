/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import PackageModel
import PackageGraph
import Build
import XCBuildSupport

/// A protocol that represents a build system used by SwiftPM for all build operations. This allows factoring out the
/// implementation details between SwiftPM's `BuildOperation` and the XCBuild backed `XCBuildSystem`.
public protocol BuildSystem {

    /// Builds a subset of the package graph.
    /// - Parameters:
    ///   - subset: The subset of the package graph to build.
    func build(subset: BuildSubset) throws

    /// Cancels the currently running operation, if possible.
    func cancel()
}

extension BuildOperation: BuildSystem {}

public final class XcodeBuildSystem: BuildSystem {
    private let buildParameters: BuildParameters
    private let packageGraphLoader: () throws -> PackageGraph
    private let diagnostics: DiagnosticsEngine
    private let xcbuildPath: AbsolutePath
    private var packageGraph: PackageGraph?

    /// The stdout stream for the build delegate.
    let stdoutStream: OutputByteStream

    public init(
        buildParameters: BuildParameters,
        packageGraphLoader: @escaping () throws -> PackageGraph,
        diagnostics: DiagnosticsEngine,
        stdoutStream: OutputByteStream
    ) throws {
        self.buildParameters = buildParameters
        self.diagnostics = diagnostics
        self.stdoutStream = stdoutStream
        self.packageGraphLoader = packageGraphLoader

        let xcodeSelectOutput = try Process.popen(args: "xcode-select", "-p").utf8Output().spm_chomp()
        let xcodeDirectory = try AbsolutePath(validating: xcodeSelectOutput)
        xcbuildPath = xcodeDirectory.appending(RelativePath("../SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"))

        guard localFileSystem.exists(xcbuildPath) else {
            throw StringError("xcbuild executable at '\(xcbuildPath)' does not exist or is not executable")
        }
    }

    public func build(subset: BuildSubset) throws {
        let graph = try getPackageGraph()
        let pifBuilder = PIFBuilder(graph: graph, parameters: .init(buildParameters), diagnostics: diagnostics)
        let pif = try pifBuilder.generatePIF()
        try localFileSystem.writeIfChanged(path: buildParameters.pifManifest, bytes: ByteString(encodingAsUTF8: pif))

        let arguments = [
            xcbuildPath.pathString,
            "build",
            buildParameters.pifManifest.pathString,
            "--configuration",
            buildParameters.configuration.xcbuildName,
            "--derivedDataPath",
            buildParameters.dataPath.pathString,
            "--target",
            subset.pifTargetName
        ]

        let delegate = createBuildDelegate()
        let redirection: Process.OutputRedirection = .stream(stdout: delegate.parse(bytes:), stderr: { bytes in
            self.diagnostics.emit(StringError(String(bytes: bytes, encoding: .utf8)!))
        })

        let process = Process(arguments: arguments, outputRedirection: redirection)
        try process.launch()
        let result = try process.waitUntilExit()

        guard result.exitStatus == .terminated(code: 0) else {
            throw StringError(try result.utf8Output().spm_chomp())
        }
    }

    public func cancel() {
    }

    /// Returns a new instance of `XCBuildDelegate` for a build operation.
    private func createBuildDelegate() -> XCBuildDelegate {
        let isVerbose = verbosity != .concise
        let progressAnimation: ProgressAnimationProtocol = isVerbose
            ? MultiLineNinjaProgressAnimation(stream: stdoutStream)
            : NinjaProgressAnimation(stream: stdoutStream)
        let delegate = XCBuildDelegate(
            diagnostics: diagnostics,
            outputStream: stdoutStream,
            progressAnimation: progressAnimation)
        delegate.isVerbose = isVerbose
        return delegate
    }

    /// Returns the package graph using the graph loader closure.
    ///
    /// First access will cache the graph.
    private func getPackageGraph() throws -> PackageGraph {
        if let packageGraph = packageGraph {
            return packageGraph
        }
        packageGraph = try packageGraphLoader()
        return packageGraph!
    }
}

extension BuildConfiguration {
    public var xcbuildName: String {
        switch self {
            case .debug: return "Debug"
            case .release: return "Release"
        }
    }
}

extension PIFBuilderParameters {
    init(_ buildParameters: BuildParameters) {
        self.init(
            buildEnvironment: buildParameters.buildEnvironment,
            shouldCreateDylibForDynamicProducts: buildParameters.shouldCreateDylibForDynamicProducts
        )
    }
}

extension BuildSubset {
    var pifTargetName: String {
        switch self {
        case .target(let name), .product(let name):
            return name
        case .allExcludingTests:
            return PIFBuilder.allExcludingTestsTargetName
        case .allIncludingTests:
            return PIFBuilder.allIncludingTestsTargetName
        }
    }
}
