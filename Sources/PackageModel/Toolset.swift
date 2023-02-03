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

import Foundation

import class Basics.ObservabilityScope
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.RelativePath
import struct TSCBasic.StringError
import struct TSCUtility.Version

/// A set of paths and flags for tools used for building Swift packages. This type unifies pre-existing assorted ways
/// to specify these properties across SwiftPM codebase.
public struct Toolset {
    public enum KnownTool: String, Hashable, CaseIterable {
        case swiftCompiler
        case cCompiler
        case cxxCompiler
        case linker
        case librarian
        case debugger
    }

    /// Properties of a known tool in a ``Toolset``.
    public struct ToolProperties: Equatable {
        /// Absolute path to the tool on the filesystem. If absent, implies a default tool is used.
        public fileprivate(set) var path: AbsolutePath?

        /// Command-line options to be passed to the tool when it's invoked.
        public fileprivate(set) var extraCLIOptions: [String]?
    }

    /// A dictionary of known tools in this toolset.
    public fileprivate(set) var knownTools: [KnownTool: ToolProperties]
}

extension Toolset {
    /// Initialize a toolset from an encoded file on a file system.
    /// - Parameters:
    ///   - path: absolute path on the `fileSystem`.
    ///   - fileSystem: file system from which the toolset should be read.
    ///   - observability: an instance of `ObservabilityScope` to log warnings about unknown tools.
    public init(from toolsetPath: AbsolutePath, at fileSystem: FileSystem, _ observability: ObservabilityScope) throws {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(path: toolsetPath, fileSystem: fileSystem, as: DecodedToolset.self)
        guard decoded.schemaVersion == Version(1, 0, 0) else {
            throw StringError(
                "Unsupported `schemaVersion` \(decoded.schemaVersion) in toolset configuration at \(toolsetPath)"
            )
        }

        var knownTools = [KnownTool: ToolProperties]()
        for (tool, properties) in decoded.tools {
            guard let knownTool = KnownTool(rawValue: tool) else {
                observability.emit(warning: "Unknown tool `\(tool)` in toolset configuration at `\(toolsetPath)`")
                continue
            }

            let toolPath: AbsolutePath?
            if let path = properties.path {
                if let absolutePath = try? AbsolutePath(validating: path) {
                    toolPath = absolutePath
                } else {
                    let rootPath = decoded.rootPath ?? toolsetPath.parentDirectory
                    toolPath = rootPath.appending(RelativePath(path))
                }
            } else {
                toolPath = nil
            }

            guard toolPath != nil || !(properties.extraCLIOptions?.isEmpty ?? true) else {
                // don't keep track of a tool with no path and CLI options specified.
                observability.emit(warning:
                    """
                    Tool `\(knownTool.rawValue) in toolset configuration at `\(toolsetPath)` has neither `path` nor \
                    `extraCLIOptions` properties specified with valid values, skipping it.
                    """)
                continue
            }

            knownTools[knownTool] = ToolProperties(
                path: toolPath,
                extraCLIOptions: properties.extraCLIOptions
            )
        }

        self.init(knownTools: knownTools)
    }

    /// Merges toolsets together into a single configuration. Tools passed in a new toolset will shadow tools with
    /// same names from previous toolsets. When no `path` is specified for a new tool, its `extraCLIOptions` are
    /// appended to `extraCLIOptions` of a tool from a previous toolset, which allows augmenting existing tools instead
    /// of replacing them.
    /// - Parameter newToolset: new toolset to merge into the existing `self` toolset.
    public mutating func merge(with newToolset: Toolset) {
        for (newTool, newProperties) in newToolset.knownTools {
            if newProperties.path != nil {
                // if `newTool` has `path` specified, it overrides the existing tool completely.
                knownTools[newTool] = newProperties
            } else if let newExtraCLIOptions = newProperties.extraCLIOptions, !newExtraCLIOptions.isEmpty {
                // if `newTool` has no `path` specified, `newExtraCLIOptions` are appended to the existing tool.
                if var existingTool = knownTools[newTool] {
                    // either update the existing tool and store it back...
                    if existingTool.extraCLIOptions == nil {
                        existingTool.extraCLIOptions = newExtraCLIOptions
                    } else {
                        existingTool.extraCLIOptions?.append(contentsOf: newExtraCLIOptions)
                    }
                    knownTools[newTool] = existingTool
                } else {
                    // ...or store a new tool if no existing tool is found.
                    knownTools[newTool] = newProperties
                }
            }
        }
    }
}

/// A raw decoding of toolset configuration stored on disk.
private struct DecodedToolset {
    /// Version of a toolset schema used for decoding a toolset file.
    let schemaVersion: Version

    /// Root path of the toolset, if present. When filling in ``Toolset.ToolProperties/path``, if a raw path string in
    /// ``DecodedToolset`` is inferred to be relative, it's resolved as absolute path relatively to `rootPath`.
    let rootPath: AbsolutePath?

    /// Dictionary of raw tools that haven't been validated yet to match ``Toolset.KnownTool``.
    var tools: [String: ToolProperties]

    /// Properties of a tool in a ``DecodedToolset``.
    public struct ToolProperties {
        /// Either a relative or an absolute path to the tool on the filesystem.
        let path: String?

        /// Command-line options to be passed to the tool when it's invoked.
        let extraCLIOptions: [String]?
    }
}

extension DecodedToolset.ToolProperties: Decodable {}

extension DecodedToolset: Decodable {
    /// Custom decoding keys that allow decoding tools with arbitrary names,
    enum CodingKeys: Equatable {
        case schemaVersion
        case rootPath
        case tool(String)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.schemaVersion = try Version(
            versionString: container.decode(String.self, forKey: .schemaVersion),
            usesLenientParsing: true
        )
        self.rootPath = try container.decodeIfPresent(AbsolutePath.self, forKey: .rootPath)

        self.tools = [String: DecodedToolset.ToolProperties]()
        for key in container.allKeys {
            switch key {
            case .rootPath, .schemaVersion:
                // These keys were already decoded before entering this loop, skipping.
                continue
            case .tool(let tool):
                self.tools[tool] = try container.decode(DecodedToolset.ToolProperties.self, forKey: key)
            }
        }
    }
}

extension DecodedToolset.CodingKeys: CodingKey {
    var stringValue: String {
        switch self {
        case .schemaVersion:
            return "schemaVersion"
        case .rootPath:
            return "rootPath"
        case .tool(let toolName):
            return toolName
        }
    }

    init?(stringValue: String) {
        switch stringValue {
        case "schemaVersion":
            self = .schemaVersion
        case "rootPath":
            self = .rootPath
        default:
            self = .tool(stringValue)
        }
    }

    var intValue: Int? { nil }

    init?(intValue: Int) {
        nil
    }
}
