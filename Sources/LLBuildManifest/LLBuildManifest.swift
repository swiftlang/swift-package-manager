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
import Foundation
import TSCBasic
import TSCUtility

import class Basics.AsyncProcess

public protocol AuxiliaryFileType {
    static var name: String { get }

    static func getFileContents(inputs: [Node]) throws -> String
}

public enum WriteAuxiliary {
    public static let fileTypes: [AuxiliaryFileType.Type] = [
        EntitlementPlist.self,
        LinkFileList.self,
        SourcesFileList.self,
        SwiftGetVersion.self,
        XCTestInfoPlist.self,
        EmbeddedResources.self,
    ]

    public struct EntitlementPlist: AuxiliaryFileType {
        public static let name = "entitlement-plist"

        public static func computeInputs(entitlement: String) -> [Node] {
            [.virtual(Self.name), .virtual(entitlement)]
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            guard let entitlementName = inputs.last?.extractedVirtualNodeName else {
                throw Error.undefinedEntitlementName
            }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let result = try encoder.encode([entitlementName: true])

            let contents = String(decoding: result, as: UTF8.self)
            return contents
        }

        private enum Error: Swift.Error {
            case undefinedEntitlementName
        }
    }

    public struct LinkFileList: AuxiliaryFileType {
        public static let name = "link-file-list"

        // FIXME: We should extend the `InProcessTool` support to allow us to specify these in a typed way, but today we have to flatten all the inputs into a generic `Node` array (rdar://109844243).
        public static func computeInputs(objects: [Basics.AbsolutePath]) -> [Node] {
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

    public struct SourcesFileList: AuxiliaryFileType {
        public static let name = "sources-file-list"

        public static func computeInputs(sources: [Basics.AbsolutePath]) -> [Node] {
            return [.virtual(Self.name)] + sources.map { Node.file($0) }
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            let sources = inputs.compactMap {
                if $0.kind == .file {
                    return $0.name
                } else {
                    return nil
                }
            }

            guard sources.count > 0 else { return "" }

            var contents = sources
                .map { $0.spm_shellEscaped() }
                .joined(separator: "\n")
            contents.append("\n")
            return contents
        }
    }

    public struct SwiftGetVersion: AuxiliaryFileType {
        public static let name = "swift-get-version"

        public static func computeInputs(swiftCompilerPath: Basics.AbsolutePath) -> [Node] {
            return [.virtual(Self.name), .file(swiftCompilerPath)]
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            guard let swiftCompilerPathString = inputs.first(where: { $0.kind == .file })?.name else {
                throw Error.unknownSwiftCompilerPath
            }
            let swiftCompilerPath = try Basics.AbsolutePath(validating: swiftCompilerPathString)
            return try AsyncProcess.checkNonZeroExit(args: swiftCompilerPath.pathString, "-version")
        }

        private enum Error: Swift.Error {
            case unknownSwiftCompilerPath
        }
    }

    public struct XCTestInfoPlist: AuxiliaryFileType {
        public static let name = "xctest-info-plist"

        public static func computeInputs(principalClass: String) -> [Node] {
            return [.virtual(Self.name), .virtual(principalClass)]
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            guard let principalClass = inputs.last?.extractedVirtualNodeName else {
                throw Error.undefinedPrincipalClass
            }

            let plist = InfoPlist(NSPrincipalClass: String(principalClass))
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let result = try encoder.encode(plist)

            let contents = String(decoding: result, as: UTF8.self)
            return contents
        }

        private struct InfoPlist: Codable {
            let NSPrincipalClass: String
        }

        private enum Error: Swift.Error {
            case undefinedPrincipalClass
        }
    }

    public struct EmbeddedResources: AuxiliaryFileType {
        public static let name = "embedded-resources"

        private static let byteArrayMarker = "embedded-resource-byte-array"
        private static let objectMarkerPrefix = "embedded-resource-object:"

        public static func computeInputs(
            byteArrayResources: [Basics.AbsolutePath],
            objectResources: [(path: Basics.AbsolutePath, dataSymbol: String, byteCount: UInt64)]
        ) -> [Node] {
            var inputs: [Node] = [.virtual(Self.name)]
            for path in byteArrayResources {
                inputs.append(.virtual(byteArrayMarker))
                inputs.append(.file(path))
            }
            for resource in objectResources {
                inputs.append(.virtual(
                    objectMarkerPrefix + resource.dataSymbol + ":" + String(resource.byteCount)
                ))
                inputs.append(.file(resource.path))
            }
            return inputs
        }

        public static func getFileContents(inputs: [Node]) throws -> String {
            enum Representation {
                case byteArray
                case object(dataSymbol: String, byteCount: UInt64)
            }

            var representation: Representation?
            var declarations = ""
            var properties = ""

            for input in inputs {
                if input.kind == .virtual {
                    let marker = input.extractedVirtualNodeName
                    if marker == byteArrayMarker {
                        representation = .byteArray
                    } else if marker.hasPrefix(objectMarkerPrefix) {
                        let value = marker.dropFirst(objectMarkerPrefix.count)
                        guard
                            let separator = value.lastIndex(of: ":"),
                            let byteCount = UInt64(value[value.index(after: separator)...])
                        else {
                            throw Error.invalidObjectResourceMarker(marker)
                        }
                        representation = .object(
                            dataSymbol: String(value[..<separator]),
                            byteCount: byteCount
                        )
                    }
                    continue
                }

                guard input.kind == .file, let representation else { continue }
                let resourcePath = try Basics.AbsolutePath(validating: input.name)
                let variableName = resourcePath.basename.spm_mangledToC99ExtendedIdentifier()

                switch representation {
                case .byteArray:
                    // FIXME: This stores the entire contents and its decimal
                    // source representation in memory. Prefer object-file
                    // embedding for large resources.
                    let fileContent = try Data(contentsOf: URL(fileURLWithPath: resourcePath.pathString))
                        .map { String($0) }
                        .joined(separator: ",")
                    properties += "static let \(variableName): [UInt8] = [\(fileContent)]\n"

                case .object(let dataSymbol, let byteCount):
                    let swiftDataName = "_\(dataSymbol)"
                    declarations +=
                        """
                        @_silgen_name("\(dataSymbol)")
                        nonisolated(unsafe) private var \(swiftDataName): UInt8

                        """
                    properties +=
                        """
                        static var \(variableName): Span<UInt8> {
                            @_lifetime(immortal)
                            get {
                                let start = withUnsafePointer(to: &\(swiftDataName)) { $0 }
                                let span = unsafe Span(_unsafeStart: start, count: \(byteCount))
                                return unsafe _overrideLifetime(span, copying: ())
                            }
                        }
                        """
                    properties += "\n"
                }
            }

            return
                """
                \(declarations)struct PackageResources {
                \(properties)}
                """
        }

        private enum Error: Swift.Error {
            case invalidObjectResourceMarker(String)
        }
    }
}

public struct LLBuildManifest {
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

    private mutating func addCommand(name: String, tool: ToolProtocol) {
        assert(commands[name] == nil, "already had a command named '\(name)'")
        commands[name] = Command(name: name, tool: tool)
    }

    public mutating func addPhonyCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        let tool = PhonyTool(inputs: inputs, outputs: outputs)
        addCommand(name: name, tool: tool)
    }

    public mutating func addTestDiscoveryCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        let tool = TestDiscoveryTool(inputs: inputs, outputs: outputs)
        addCommand(name: name, tool: tool)
    }

    public mutating func addTestEntryPointCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        let tool = TestEntryPointTool(inputs: inputs, outputs: outputs)
        addCommand(name: name, tool: tool)
    }

    public mutating func addCopyCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        let tool = CopyTool(inputs: inputs, outputs: outputs)
        addCommand(name: name, tool: tool)
    }

    public mutating func addEntitlementPlistCommand(entitlement: String, outputPath: Basics.AbsolutePath) {
        let inputs = WriteAuxiliary.EntitlementPlist.computeInputs(entitlement: entitlement)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: outputPath)
        let name = outputPath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addWriteLinkFileListCommand(
        objects: [Basics.AbsolutePath],
        linkFileListPath: Basics.AbsolutePath
    ) {
        let inputs = WriteAuxiliary.LinkFileList.computeInputs(objects: objects)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: linkFileListPath)
        let name = linkFileListPath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addWriteSourcesFileListCommand(
        sources: [Basics.AbsolutePath],
        sourcesFileListPath: Basics.AbsolutePath
    ) {
        let inputs = WriteAuxiliary.SourcesFileList.computeInputs(sources: sources)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: sourcesFileListPath)
        let name = sourcesFileListPath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addSwiftGetVersionCommand(
        swiftCompilerPath: Basics.AbsolutePath,
        swiftVersionFilePath: Basics.AbsolutePath
    ) {
        let inputs = WriteAuxiliary.SwiftGetVersion.computeInputs(swiftCompilerPath: swiftCompilerPath)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: swiftVersionFilePath, alwaysOutOfDate: true)
        let name = swiftVersionFilePath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addWriteInfoPlistCommand(principalClass: String, outputPath: Basics.AbsolutePath) {
        let inputs = WriteAuxiliary.XCTestInfoPlist.computeInputs(principalClass: principalClass)
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: outputPath)
        let name = outputPath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addWriteEmbeddedResourcesCommand(
        byteArrayResources: [Basics.AbsolutePath],
        objectResources: [(path: Basics.AbsolutePath, dataSymbol: String, byteCount: UInt64)],
        outputPath: Basics.AbsolutePath
    ) {
        let inputs = WriteAuxiliary.EmbeddedResources.computeInputs(
            byteArrayResources: byteArrayResources,
            objectResources: objectResources
        )
        let tool = WriteAuxiliaryFile(inputs: inputs, outputFilePath: outputPath)
        let name = outputPath.pathString
        addCommand(name: name, tool: tool)
    }

    public mutating func addPkgStructureCmd(
        name: String,
        inputs: [Node],
        outputs: [Node]
    ) {
        let tool = PackageStructureTool(inputs: inputs, outputs: outputs)
        addCommand(name: name, tool: tool)
    }

    public mutating func addShellCmd(
        name: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        environment: Environment = [:],
        workingDirectory: String? = nil,
        allowMissingInputs: Bool = false
    ) {
        let tool = ShellTool(
            description: description,
            inputs: inputs,
            outputs: outputs,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            allowMissingInputs: allowMissingInputs
        )
        addCommand(name: name, tool: tool)
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
        let tool = SwiftFrontendTool(
                moduleName: moduleName,
                description: description,
                inputs: inputs,
                outputs: outputs,
                arguments: arguments
        )
        addCommand(name: name, tool: tool)
    }

    public mutating func addClangCmd(
        name: String,
        description: String,
        inputs: [Node],
        outputs: [Node],
        arguments: [String],
        dependencies: String? = nil
    ) {
        let tool = ClangTool(
            description: description,
            inputs: inputs,
            outputs: outputs,
            arguments: arguments,
            dependencies: dependencies
        )
        addCommand(name: name, tool: tool)
    }

    public mutating func addSwiftCmd(
        name: String,
        inputs: [Node],
        outputs: [Node],
        executable: Basics.AbsolutePath,
        moduleName: String,
        moduleAliases: [String: String]?,
        moduleOutputPath: Basics.AbsolutePath,
        importPath: Basics.AbsolutePath,
        tempsPath: Basics.AbsolutePath,
        objects: [Basics.AbsolutePath],
        otherArguments: [String],
        sources: [Basics.AbsolutePath],
        fileList: Basics.AbsolutePath,
        isLibrary: Bool,
        wholeModuleOptimization: Bool,
        outputFileMapPath: Basics.AbsolutePath,
        prepareForIndexing: Bool
    ) {
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
            fileList: fileList,
            isLibrary: isLibrary,
            wholeModuleOptimization: wholeModuleOptimization,
            outputFileMapPath: outputFileMapPath,
            prepareForIndexing: prepareForIndexing
        )
        addCommand(name: name, tool: tool)
    }
}
