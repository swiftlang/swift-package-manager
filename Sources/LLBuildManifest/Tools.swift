/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo
import TSCBasic

public protocol ToolProtocol: Codable {
    /// The name of the tool.
    static var name: String { get }

    /// The list of inputs to declare.
    var inputs: [Node] { get }

    /// The list of outputs to declare.
    var outputs: [Node] { get }

    /// Write a description of the tool to the given output `stream`.
    func write(to stream: ManifestToolStream)
}

extension ToolProtocol {
    public func write(to stream: ManifestToolStream) {}
}

public struct PhonyTool: ToolProtocol {
    public static let name: String = "phony"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct TestDiscoveryTool: ToolProtocol {
    public static let name: String = "test-discovery-tool"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct CopyTool: ToolProtocol {
    public static let name: String = "copy-tool"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = "Copying \(inputs[0].name)"
    }
}

/// Package strcuture tool is used to determine if the package has changed in some way
/// that requires regenerating the build manifest file. This allows us to skip a lot of
/// redundent work (package graph loading, build planning, manifest generation) during
/// incremental builds.
public struct PackageStructureTool: ToolProtocol {
    public static let name: String = "package-structure-tool"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = "Planning build"
        stream["allow-missing-inputs"] = true
    }
}

public struct ShellTool: ToolProtocol {
    public static let name: String = "shell"

    public var description: String
    public var inputs: [Node]
    public var outputs: [Node]
    public var args: [String]
    public var allowMissingInputs: Bool

    init(
        description: String,
        inputs: [Node],
        outputs: [Node],
        args: [String],
        allowMissingInputs: Bool = false
    ) {
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.args = args
        self.allowMissingInputs = allowMissingInputs
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = description
        stream["args"] = args
        if allowMissingInputs {
            stream["allow-missing-inputs"] = true
        }
    }
}

public struct ClangTool: ToolProtocol {
    public static let name: String = "clang"

    public var description: String
    public var inputs: [Node]
    public var outputs: [Node]
    public var args: [String]
    public var deps: String?

    init(
        description: String,
        inputs: [Node],
        outputs: [Node],
        args: [String],
        deps: String? = nil
    ) {
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.args = args
        self.deps = deps
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = description
        stream["args"] = args
        if let deps = deps {
            stream["deps"] = deps
        }
    }
}

public struct ArchiveTool: ToolProtocol {
    public static let name: String = "archive"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

/// Swift frontend tool, which maps down to a shell tool.
public struct SwiftFrontendTool: ToolProtocol {
    public static let name: String = "shell"

    public let moduleName: String
    public var description: String
    public var inputs: [Node]
    public var outputs: [Node]
    public var args: [String]

    init(
        moduleName: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        args: [String]
    ) {
        self.moduleName = moduleName
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.args = args
    }

    public func write(to stream: ManifestToolStream) {
      ShellTool(description: description, inputs: inputs, outputs: outputs, args: args)
        .write(to: stream)
    }
}

/// Swift compiler llbuild tool.
public struct SwiftCompilerTool: ToolProtocol {
    public static let name: String = "swift-compiler"

    public static let numThreads: Int = ProcessInfo.processInfo.activeProcessorCount

    public var inputs: [Node]
    public var outputs: [Node]

    public var executable: AbsolutePath
    public var moduleName: String
    public var moduleOutputPath: AbsolutePath
    public var importPath: AbsolutePath
    public var tempsPath: AbsolutePath
    public var objects: [AbsolutePath]
    public var otherArgs: [String]
    public var sources: [AbsolutePath]
    public var isLibrary: Bool
    public var WMO: Bool

    init(
        inputs: [Node],
        outputs: [Node],
        executable: AbsolutePath,
        moduleName: String,
        moduleOutputPath: AbsolutePath,
        importPath: AbsolutePath,
        tempsPath: AbsolutePath,
        objects: [AbsolutePath],
        otherArgs: [String],
        sources: [AbsolutePath],
        isLibrary: Bool,
        WMO: Bool
    ) {
        self.inputs = inputs
        self.outputs = outputs
        self.executable = executable
        self.moduleName = moduleName
        self.moduleOutputPath = moduleOutputPath
        self.importPath = importPath
        self.tempsPath = tempsPath
        self.objects = objects
        self.otherArgs = otherArgs
        self.sources = sources
        self.isLibrary = isLibrary
        self.WMO = WMO
    }

    public func write(to stream: ManifestToolStream) {
        stream["executable"] = executable
        stream["module-name"] = moduleName
        stream["module-output-path"] = moduleOutputPath
        stream["import-paths"] = [importPath]
        stream["temps-path"] = tempsPath
        stream["objects"] = objects
        stream["other-args"] = otherArgs
        stream["sources"] = sources
        stream["is-library"] = isLibrary
        stream["enable-whole-module-optimization"] = WMO
        stream["num-threads"] = Self.numThreads
     }
}
