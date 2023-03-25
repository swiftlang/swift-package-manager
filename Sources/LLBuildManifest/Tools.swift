//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
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
    public static let mainFileName: String = "all-discovered-tests.swift"

    public var inputs: [Node]
    public var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct TestEntryPointTool: ToolProtocol {
    public static let name: String = "test-entry-point-tool"
    public static let mainFileName: String = "runner.swift"

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

/// Package structure tool is used to determine if the package has changed in some way
/// that requires regenerating the build manifest file. This allows us to skip a lot of
/// redundant work (package graph loading, build planning, manifest generation) during
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
    public var arguments: [String]
    public var environment: EnvironmentVariables
    public var workingDirectory: String?
    public var allowMissingInputs: Bool

    init(
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        environment: EnvironmentVariables = .empty(),
        workingDirectory: String? = nil,
        allowMissingInputs: Bool = false
    ) {
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.allowMissingInputs = allowMissingInputs
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = description
        stream["args"] = arguments
        if !environment.isEmpty {
            stream["env"] = environment
        }
        if let workingDirectory {
            stream["working-directory"] = workingDirectory
        }
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
    public var arguments: [String]
    public var dependencies: String?

    init(
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        dependencies: String? = nil
    ) {
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.arguments = arguments
        self.dependencies = dependencies
    }

    public func write(to stream: ManifestToolStream) {
        stream["description"] = description
        stream["args"] = arguments
        if let dependencies {
            stream["deps"] = dependencies
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
    public var arguments: [String]

    init(
        moduleName: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String]
    ) {
        self.moduleName = moduleName
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.arguments = arguments
    }

    public func write(to stream: ManifestToolStream) {
      ShellTool(description: description, inputs: inputs, outputs: outputs, arguments: arguments)
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
    public var moduleAliases: [String: String]?
    public var moduleOutputPath: AbsolutePath
    public var importPath: AbsolutePath
    public var tempsPath: AbsolutePath
    public var objects: [AbsolutePath]
    public var otherArguments: [String]
    public var sources: [AbsolutePath]
    public var isLibrary: Bool
    public var wholeModuleOptimization: Bool

    init(
        inputs: [Node],
        outputs: [Node],
        executable: AbsolutePath,
        moduleName: String,
        moduleAliases: [String: String]?,
        moduleOutputPath: AbsolutePath,
        importPath: AbsolutePath,
        tempsPath: AbsolutePath,
        objects: [AbsolutePath],
        otherArguments: [String],
        sources: [AbsolutePath],
        isLibrary: Bool,
        wholeModuleOptimization: Bool
    ) {
        self.inputs = inputs
        self.outputs = outputs
        self.executable = executable
        self.moduleName = moduleName
        self.moduleAliases = moduleAliases
        self.moduleOutputPath = moduleOutputPath
        self.importPath = importPath
        self.tempsPath = tempsPath
        self.objects = objects
        self.otherArguments = otherArguments
        self.sources = sources
        self.isLibrary = isLibrary
        self.wholeModuleOptimization = wholeModuleOptimization
    }

    public func write(to stream: ManifestToolStream) {
        stream["executable"] = executable
        stream["module-name"] = moduleName
        if let moduleAliases {
            // Format the key and value to pass to -module-alias flag
            let formatted = moduleAliases.map {$0.key + "=" + $0.value}
            stream["module-aliases"] = formatted
        }
        stream["module-output-path"] = moduleOutputPath
        stream["import-paths"] = [importPath]
        stream["temps-path"] = tempsPath
        stream["objects"] = objects
        stream["other-args"] = otherArguments
        stream["sources"] = sources
        stream["is-library"] = isLibrary
        stream["enable-whole-module-optimization"] = wholeModuleOptimization
        stream["num-threads"] = Self.numThreads
     }
}
