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
import struct TSCBasic.AbsolutePath

public protocol AuxiliaryFileType {
    static var name: String { get }

    static func getFileContents(inputs: [Node]) throws -> String
}

public enum WriteAuxiliary {
    public static let fileTypes: [AuxiliaryFileType.Type] = [LinkFileList.self]

    public struct LinkFileList: AuxiliaryFileType {
        public static let name = "link-file-list"

        // FIXME: We should extend the `InProcessTool` support to allow us to specify these in a typed way, but today we have to flatten all the inputs into a generic `Node` array (rdar://109844243).
        public static func computeInputs(objects: [AbsolutePath]) -> [Node] {
            return [.virtual(Self.name)] + objects.map { Node.file($0) }
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            let objects = inputs.compactMap {
                if $0.kind == .file {
                    return $0.name
                } else {
                    return nil
                }
            }

            var content = objects
                .map { $0.spm_shellEscaped() }
                .joined(separator: "\n")

            // not sure this is needed, added here for backward compatibility
            if !content.isEmpty {
                content.append("\n")
            }

            return content
        }
    }
}

public struct BuildManifest {
    public typealias TargetName = String
    public typealias CmdName = String

    /// The targets in the manifest.
    public private(set) var targets: [TargetName: Target] = [:]

    /// The commands in the manifest.
    public private(set) var commands: [CmdName: Command] = [:]

    /// The default target to build.
    public var defaultTarget: String = ""

    public init() {
    }

    public func getCmdToolMap<T: ToolProtocol>(kind: T.Type) -> [CmdName: T] {
        var result = [CmdName: T]()
        for (cmdName, cmd) in commands {
            if let tool = cmd.tool as? T {
                result[cmdName] = tool
            }
        }
        return result
    }

    public mutating func createTarget(_ name: TargetName) {
        guard !targets.keys.contains(name) else { return }
        targets[name] = Target(name: name, nodes: [])
    }

    public mutating func addNode(_ node: Node, toTarget target: TargetName) {
        targets[target, default: Target(name: target, nodes: [])].nodes.append(node)
    }

    public mutating func addPhonyCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = PhonyTool(inputs: inputs, outputs: outputs)
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addTestDiscoveryCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = TestDiscoveryTool(inputs: inputs, outputs: outputs)
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addTestEntryPointCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = TestEntryPointTool(inputs: inputs, outputs: outputs)
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addCopyCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = CopyTool(inputs: inputs, outputs: outputs)
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addWriteLinkFileListCommand(
        objects: [AbsolutePath],
        linkFileListPath: AbsolutePath
    ) {
        let inputs = WriteAuxiliary.LinkFileList.computeInputs(objects: objects)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: linkFileListPath)
        let name = linkFileListPath.pathString
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addPkgStructureCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = PackageStructureTool(inputs: inputs, outputs: outputs)
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addShellCmd(
        name: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        environment: EnvironmentVariables = .empty(),
        workingDirectory: String? = nil,
        allowMissingInputs: Bool = false
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = ShellTool(
            description: description,
            inputs: inputs,
            outputs: outputs,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            allowMissingInputs: allowMissingInputs
        )
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addSwiftFrontendCmd(
        name: String,
        moduleName: String,
        packageName: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String]
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = SwiftFrontendTool(
                moduleName: moduleName,
                description: description,
                inputs: inputs,
                outputs: outputs,
                arguments: arguments
        )
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addClangCmd(
        name: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        dependencies: String? = nil
    ) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = ClangTool(
            description: description,
            inputs: inputs,
            outputs: outputs,
            arguments: arguments,
            dependencies: dependencies
        )
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addSwiftCmd(
        name: String,
        inputs: [Node],
        outputs: [Node],
        executable: AbsolutePath,
        packageName: String,
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
        assert(commands[name] == nil, "already had a command named '\(name)'")
        let tool = SwiftCompilerTool(
            inputs: inputs,
            outputs: outputs,
            executable: executable,
            moduleName: moduleName,
            moduleAliases: moduleAliases,
            moduleOutputPath: moduleOutputPath,
            importPath: importPath,
            tempsPath: tempsPath,
            objects: objects,
            otherArguments: otherArguments,
            sources: sources,
            isLibrary: isLibrary,
            wholeModuleOptimization: wholeModuleOptimization
        )
        commands[name] = Command(name: name, tool: tool)
    }
}
