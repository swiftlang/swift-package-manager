/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import PackageModel
import SPMBuildCore
import TSCBasic
import TSCUtility

public struct ToolsArchiveMetadata: Equatable {
    public let schemaVersion: String
    public let tools: [String: [Support]]

    public init(schemaVersion: String, tools: [String: [ToolsArchiveMetadata.Support]]) {
        self.schemaVersion = schemaVersion
        self.tools = tools
    }

    public struct Support: Equatable {
        let path: String
        let supportedTriplets: [Triple]

        public init(path: String, supportedTriplets: [Triple]) {
            self.path = path
            self.supportedTriplets = supportedTriplets
        }
    }
}

extension ToolsArchiveMetadata {
    public static func parse(fileSystem: FileSystem, rootPath: AbsolutePath) throws -> ToolsArchiveMetadata {
        let path = rootPath.appending(component: "info.json")
        guard fileSystem.exists(path) else {
            throw StringError("ExecutablesArchive info.json not found at '\(rootPath)'")
        }

        do {
            let bytes = try fileSystem.readFileContents(path)
            return try bytes.withData { data in
                let decoder = JSONDecoder.makeWithDefaults()
                return try decoder.decode(ToolsArchiveMetadata.self, from: data)
            }
        } catch {
            throw StringError("failed parsing ExecutablesArchive info.json at '\(path)': \(error)")
        }
    }
}

extension ToolsArchiveMetadata: Decodable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tools = "availableTools"
    }
}

extension ToolsArchiveMetadata.Support: Decodable {
    enum CodingKeys: String, CodingKey {
        case path
        case supportedTriplets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.supportedTriplets = try container.decode([String].self, forKey: .supportedTriplets).map { try Triple($0) }
    }
}
