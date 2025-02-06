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

import struct TSCBasic.StringError
import struct TSCUtility.Version

/// A set of paths and flags for tools used for building Swift packages. This type unifies pre-existing assorted ways
/// to specify these properties across SwiftPM codebase.
public struct Toolset: Equatable {
    /// Tools currently known and used by SwiftPM.
    public enum KnownTool: String, Hashable, CaseIterable {
        case swiftCompiler
        case cCompiler
        case cxxCompiler
        case linker
        case librarian
        case debugger
        case testRunner
        case xcbuild
    }

    /// Properties of a known tool in a ``Toolset``.
    public struct ToolProperties: Equatable {
        /// Absolute path to the tool on the filesystem. If absent, implies a default tool is used.
        public fileprivate(set) var path: AbsolutePath?

        /// Command-line options to be passed to the tool when it's invoked.
        public internal(set) var extraCLIOptions: [String]
    }

    /// A dictionary of known tools in this toolset.
    public internal(set) var knownTools: [KnownTool: ToolProperties] = [:]

    /// An array of paths specified as `rootPath` in toolset files from which this toolset was formed. May be used
    /// for locating tools that aren't currently listed in ``Toolset/KnownTool``.
    public internal(set) var rootPaths: [AbsolutePath] = []
}

extension Toolset.ToolProperties {
    init(path: AbsolutePath) {
        self.init(path: path, extraCLIOptions: [])
    }
}

extension Toolset {
    /// Initialize a toolset from an encoded file on a file system.
    /// - Parameters:
    ///   - path: absolute path on the `fileSystem`.
    ///   - fileSystem: file system from which the toolset should be read.
    ///   - observabilityScope: an instance of `ObservabilityScope` to log warnings about unknown or invalid tools.
    public init(
        from toolsetPath: AbsolutePath,
        at fileSystem: FileSystem,
        _ observabilityScope: ObservabilityScope
    ) throws {
        let decoder = JSONDecoder()

        let decoded: DecodedToolset
        do {
            decoded = try decoder.decode(path: toolsetPath, fileSystem: fileSystem, as: DecodedToolset.self)
        } catch {
            // Throw a more detailed warning that includes the location of the toolset file we couldn't parse.
            throw StringError("Couldn't parse toolset configuration at `\(toolsetPath)`: \(error.interpolationDescription)")
        }

        guard decoded.schemaVersion == Version(1, 0, 0) else {
            throw StringError(
                "Unsupported `schemaVersion` \(decoded.schemaVersion) in toolset configuration at `\(toolsetPath)`"
            )
        }

        let rootPaths = try decoded.rootPath.map {
            [try AbsolutePath(validating: $0, relativeTo: toolsetPath.parentDirectory)]
        } ?? []

        var knownTools = [KnownTool: ToolProperties]()
        var hasEmptyToolConfiguration = false
        for (tool, properties) in decoded.tools {
            guard let knownTool = KnownTool(rawValue: tool) else {
                observabilityScope.emit(warning: "Unknown tool `\(tool)` in toolset configuration at `\(toolsetPath)`")
                continue
            }

            let toolPath: AbsolutePath?
            if let path = properties.path {
                if let absolutePath = try? AbsolutePath(validating: path) {
                    toolPath = absolutePath
                } else {
                    let rootPath = rootPaths.first ?? toolsetPath.parentDirectory
                    toolPath = rootPath.appending(path)
                }
            } else {
                toolPath = nil
            }

            guard toolPath != nil || !(properties.extraCLIOptions?.isEmpty ?? true) else {
                // don't keep track of a tool with no path and CLI options specified.
                observabilityScope.emit(
                    error:
                    """
                    Tool `\(knownTool.rawValue) in toolset configuration at `\(toolsetPath)` has neither `path` nor \
                    `extraCLIOptions` properties specified with valid values, skipping it.
                    """
                )
                hasEmptyToolConfiguration = true
                continue
            }

            knownTools[knownTool] = ToolProperties(
                path: toolPath,
                extraCLIOptions: properties.extraCLIOptions ?? []
            )
        }

        guard !hasEmptyToolConfiguration else {
            throw StringError("Toolset configuration at `\(toolsetPath)` has at least one tool with no properties.")
        }

        self.init(knownTools: knownTools, rootPaths: rootPaths)
    }

    /// Merges toolsets together into a single configuration. Tools passed in a new toolset will shadow tools with
    /// same names from previous toolsets. When no `path` is specified for a new tool, its `extraCLIOptions` are
    /// appended to `extraCLIOptions` of a tool from a previous toolset, which allows augmenting existing tools instead
    /// of replacing them.
    /// - Parameter newToolset: new toolset to merge into the existing `self` toolset.
    public mutating func merge(with newToolset: Toolset) {
        self.rootPaths.insert(contentsOf: newToolset.rootPaths, at: 0)

        for (newTool, newProperties) in newToolset.knownTools {
            if newProperties.path != nil {
                // if `newTool` has `path` specified, it overrides the existing tool completely.
                knownTools[newTool] = newProperties
            } else if !newProperties.extraCLIOptions.isEmpty {
                // if `newTool` has no `path` specified, `newExtraCLIOptions` are appended to the existing tool.
                if var existingTool = knownTools[newTool] {
                    // either update the existing tool and store it back...
                    existingTool.extraCLIOptions.append(contentsOf: newProperties.extraCLIOptions)
                    knownTools[newTool] = existingTool
                } else {
                    // ...or store a new tool if no existing tool is found.
                    knownTools[newTool] = newProperties
                }
            }
        }
    }

    /// Initialize a new ad-hoc toolset that wasn't previously serialized, but created in memory.
    /// - Parameters:
    ///   - toolchainBinDir: absolute path to the toolchain binaries directory, which are used in this toolset.
    ///   - buildFlags: flags provided to each tool as CLI options.
    public init(toolchainBinDir: AbsolutePath, buildFlags: BuildFlags = .init()) {
        self.rootPaths = [toolchainBinDir]
        self.knownTools = [
            .cCompiler: .init(extraCLIOptions: buildFlags.cCompilerFlags),
            .cxxCompiler: .init(extraCLIOptions: buildFlags.cxxCompilerFlags),
            .swiftCompiler: .init(extraCLIOptions: buildFlags.swiftCompilerFlags),
            .linker: .init(extraCLIOptions: buildFlags.linkerFlags),
            .xcbuild: .init(extraCLIOptions: buildFlags.xcbuildFlags ?? []),
        ]
    }
}

/// A raw decoding of toolset configuration stored on disk.
private struct DecodedToolset {
    /// Version of a toolset schema used for decoding a toolset file.
    let schemaVersion: Version

    /// Root path of the toolset, if present. When filling in ``Toolset.ToolProperties/path``, if a raw path string in
    /// ``DecodedToolset`` is inferred to be relative, it's resolved as absolute path relatively to `rootPath`.
    let rootPath: String?

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
        self.rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath)

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

/// Custom `CodingKey` implementation for `DecodedToolset`, which allows us to resiliently decode unknown tools and emit
/// multiple diagnostic messages about them separately from the decoding process, instead of emitting a single error
/// that will disrupt whole decoding at once.
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
