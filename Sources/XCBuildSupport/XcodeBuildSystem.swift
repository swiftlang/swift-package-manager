/*
This source file is part of the Swift.org open source project

Copyright (c) 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import PackageModel
import PackageGraph
import SPMBuildCore

public final class XcodeBuildSystem: BuildSystem {
    private let buildParameters: BuildParameters
    private let packageGraphLoader: () throws -> PackageGraph
    private let isVerbose: Bool
    private let diagnostics: DiagnosticsEngine
    private let xcbuildPath: AbsolutePath
    private var packageGraph: PackageGraph?
    private var pifBuilder: PIFBuilder?

    /// The stdout stream for the build delegate.
    let stdoutStream: OutputByteStream

    public var builtTestProducts: [BuiltTestProduct] {
        guard let graph = try? getPackageGraph() else {
            return []
        }

        var builtProducts: [BuiltTestProduct] = []

        for package in graph.rootPackages {
            for product in package.products where product.type == .test {
                let binaryPath = buildParameters.binaryPath(for: product)
                builtProducts.append(BuiltTestProduct(
                    packageName: package.name,
                    productName: product.name,
                    binaryPath: binaryPath
                ))
            }
        }

        return builtProducts
    }

    public init(
        buildParameters: BuildParameters,
        packageGraphLoader: @escaping () throws -> PackageGraph,
        isVerbose: Bool,
        diagnostics: DiagnosticsEngine,
        stdoutStream: OutputByteStream
    ) throws {
        self.buildParameters = buildParameters
        self.packageGraphLoader = packageGraphLoader
        self.isVerbose = isVerbose
        self.diagnostics = diagnostics
        self.stdoutStream = stdoutStream

        if let xcbuildTool = ProcessEnv.vars["XCBUILD_TOOL"] {
            xcbuildPath = try AbsolutePath(validating: xcbuildTool)
        } else {
            let xcodeSelectOutput = try Process.popen(args: "xcode-select", "-p").utf8Output().spm_chomp()
            let xcodeDirectory = try AbsolutePath(validating: xcodeSelectOutput)
            xcbuildPath = xcodeDirectory.appending(RelativePath("../SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"))
        }

        guard localFileSystem.exists(xcbuildPath) else {
            throw StringError("xcbuild executable at '\(xcbuildPath)' does not exist or is not executable")
        }
    }

    public func build(subset: BuildSubset) throws {
        let pifBuilder = try getPIFBuilder()
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
        ] + buildParameters.xcbuildFlags

        let delegate = createBuildDelegate()
        let redirection: Process.OutputRedirection = .stream(stdout: delegate.parse(bytes:), stderr: { bytes in
            self.diagnostics.emit(StringError(String(bytes: bytes, encoding: .utf8)!))
        })

        let process = Process(arguments: arguments, outputRedirection: redirection)
        try process.launch()
        let result = try process.waitUntilExit()

        guard result.exitStatus == .terminated(code: 0) else {
            throw Diagnostics.fatalError
        }
    }

    public func cancel() {
    }

    /// Returns a new instance of `XCBuildDelegate` for a build operation.
    private func createBuildDelegate() -> XCBuildDelegate {
        let progressAnimation: ProgressAnimationProtocol = isVerbose
            ? VerboseProgressAnimation(stream: stdoutStream)
            : MultiLinePercentProgressAnimation(stream: stdoutStream, header: "")
        let delegate = XCBuildDelegate(
            diagnostics: diagnostics,
            outputStream: stdoutStream,
            progressAnimation: progressAnimation)
        delegate.isVerbose = isVerbose
        return delegate
    }

    private func getPIFBuilder() throws -> PIFBuilder {
        try memoize(to: &pifBuilder) {
            let graph = try getPackageGraph()
            let pifBuilder = PIFBuilder(graph: graph, parameters: .init(buildParameters), diagnostics: diagnostics)
            return pifBuilder
        }
    }

    /// Returns the package graph using the graph loader closure.
    ///
    /// First access will cache the graph.
    public func getPackageGraph() throws -> PackageGraph {
        try memoize(to: &packageGraph) {
            try packageGraphLoader()
        }
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
    public init(_ buildParameters: BuildParameters) {
        self.init(
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
