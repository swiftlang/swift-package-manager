//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import class Foundation.ProcessInfo

package protocol ToolProtocol: Codable {
    /// The name of the tool.
    static var name: String { get }

    /// Whether or not the tool should run on every build instead of using dependency tracking.
    var alwaysOutOfDate: Bool { get }

    /// The list of inputs to declare.
    var inputs: [Node] { get }

    /// The list of outputs to declare.
    var outputs: [Node] { get }

    /// Write a description of the tool to the given output `stream`.
    func write(to stream: inout ManifestToolStream)
}

extension ToolProtocol {
    package var alwaysOutOfDate: Bool { return false }

    package func write(to stream: inout ManifestToolStream) {}
}

package struct PhonyTool: ToolProtocol {
    package static let name: String = "phony"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

package struct TestDiscoveryTool: ToolProtocol {
    package static let name: String = "test-discovery-tool"
    package static let mainFileName: String = "all-discovered-tests.swift"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

package struct TestEntryPointTool: ToolProtocol {
    package static let name: String = "test-entry-point-tool"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

package struct CopyTool: ToolProtocol {
    package static let name: String = "copy-tool"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    package func write(to stream: inout ManifestToolStream) {
        stream["description"] = "Copying \(inputs[0].name)"
    }
}

/// Package structure tool is used to determine if the package has changed in some way
/// that requires regenerating the build manifest file. This allows us to skip a lot of
/// redundant work (package graph loading, build planning, manifest generation) during
/// incremental builds.
package struct PackageStructureTool: ToolProtocol {
    package static let name: String = "package-structure-tool"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    package func write(to stream: inout ManifestToolStream) {
        stream["description"] = "Planning build"
        stream["allow-missing-inputs"] = true
    }
}

package struct ShellTool: ToolProtocol {
    package static let name: String = "shell"

    package var description: String
    package var inputs: [Node]
    package var outputs: [Node]
    package var arguments: [String]
    package var environment: EnvironmentVariables
    package var workingDirectory: String?
    package var allowMissingInputs: Bool

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

    package func write(to stream: inout ManifestToolStream) {
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

package struct WriteAuxiliaryFile: Equatable, ToolProtocol {
    package static let name: String = "write-auxiliary-file"

    package let inputs: [Node]
    private let outputFilePath: AbsolutePath
    package let alwaysOutOfDate: Bool

    package init(inputs: [Node], outputFilePath: AbsolutePath, alwaysOutOfDate: Bool = false) {
        self.inputs = inputs
        self.outputFilePath = outputFilePath
        self.alwaysOutOfDate = alwaysOutOfDate
    }

    package var outputs: [Node] {
        return [.file(outputFilePath)]
    }

    package func write(to stream: inout ManifestToolStream) {
        stream["description"] = "Write auxiliary file \(outputFilePath.pathString)"
    }
}

package struct ClangTool: ToolProtocol {
    package static let name: String = "clang"

    package var description: String
    package var inputs: [Node]
    package var outputs: [Node]
    package var arguments: [String]
    package var dependencies: String?

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

    package func write(to stream: inout ManifestToolStream) {
        stream["description"] = description
        stream["args"] = arguments
        if let dependencies {
            stream["deps"] = dependencies
        }
    }
}

package struct ArchiveTool: ToolProtocol {
    package static let name: String = "archive"

    package var inputs: [Node]
    package var outputs: [Node]

    init(inputs: [Node], outputs: [Node]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

/// Swift frontend tool, which maps down to a shell tool.
package struct SwiftFrontendTool: ToolProtocol {
    package static let name: String = "shell"

    package let moduleName: String
    package var description: String
    package var inputs: [Node]
    package var outputs: [Node]
    package var arguments: [String]

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

    package func write(to stream: inout ManifestToolStream) {
      ShellTool(description: description, inputs: inputs, outputs: outputs, arguments: arguments).write(to: &stream)
    }
}

/// Swift compiler llbuild tool.
package struct SwiftCompilerTool: ToolProtocol {
    package static let name: String = "shell"

    package static let numThreads: Int = ProcessInfo.processInfo.activeProcessorCount

    package var inputs: [Node]
    package var outputs: [Node]

    package var executable: AbsolutePath
    package var moduleName: String
    package var moduleAliases: [String: String]?
    package var moduleOutputPath: AbsolutePath
    package var importPath: AbsolutePath
    package var tempsPath: AbsolutePath
    package var objects: [AbsolutePath]
    package var otherArguments: [String]
    package var sources: [AbsolutePath]
    package var fileList: AbsolutePath
    package var isLibrary: Bool
    package var wholeModuleOptimization: Bool
    package var outputFileMapPath: AbsolutePath

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
        fileList: AbsolutePath,
        isLibrary: Bool,
        wholeModuleOptimization: Bool,
        outputFileMapPath: AbsolutePath
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
        self.fileList = fileList
        self.isLibrary = isLibrary
        self.wholeModuleOptimization = wholeModuleOptimization
        self.outputFileMapPath = outputFileMapPath
    }

    var description: String {
        return "Compiling Swift Module '\(moduleName)' (\(sources.count) sources)"
    }

    var arguments: [String] {
        var arguments = [
            executable.pathString,
            "-module-name", moduleName,
        ]
        if let moduleAliases = moduleAliases {
            for (original, alias) in moduleAliases {
                arguments += ["-module-alias", "\(original)=\(alias)"]
            }
        }
        arguments += [
            "-emit-dependencies",
            "-emit-module",
            "-emit-module-path", moduleOutputPath.pathString,
            "-output-file-map", outputFileMapPath.pathString,
        ]
        if isLibrary {
            arguments += ["-parse-as-library"]
        }
        if wholeModuleOptimization {
            arguments += ["-whole-module-optimization", "-num-threads", "\(Self.numThreads)"]
        } else {
            arguments += ["-incremental"]
        }
        arguments += ["-c", "@\(self.fileList.pathString)"]
        arguments += ["-I", importPath.pathString]
        arguments += otherArguments
        return arguments
    }

    package func write(to stream: inout ManifestToolStream) {
        ShellTool(description: description, inputs: inputs, outputs: outputs, arguments: arguments).write(to: &stream)
    }
}
