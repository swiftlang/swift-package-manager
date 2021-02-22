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

public struct ArtifactsArchiveMetadata: Equatable {
    public let schemaVersion: String
    public let artifacts: [String: Artifact]

    public init(schemaVersion: String, artifacts: [String: Artifact]) {
        self.schemaVersion = schemaVersion
        self.artifacts = artifacts
    }

    public struct Artifact: Equatable {
        let type: ArtifactType
        let version: String
        let variants: [Variant]

        public init(type: ArtifactsArchiveMetadata.ArtifactType, version: String, variants: [Variant]) {
            self.type = type
            self.version = version
            self.variants = variants
        }
    }

    // In the future we are likely to extend the ArtifactsArchive file format to carry other types of artifacts beyond executables.
    // Additional fields may be required to support these new artifact types e.g. headers path for libraries.
    // This can also support resource-only artifacts as well. For example, 3d models along with associated textures, or fonts, etc.
    public enum ArtifactType: String, RawRepresentable, Decodable {
        case executable
    }

    public struct Variant: Equatable {
        let path: String
        let supportedTriples: [Triple]

        public init(path: String, supportedTriples: [Triple]) {
            self.path = path
            self.supportedTriples = supportedTriples
        }
    }
}

extension ArtifactsArchiveMetadata {
    public static func parse(fileSystem: FileSystem, rootPath: AbsolutePath) throws -> ArtifactsArchiveMetadata {
        let path = rootPath.appending(component: "info.json")
        guard fileSystem.exists(path) else {
            throw StringError("ArtifactsArchive info.json not found at '\(rootPath)'")
        }

        do {
            let bytes = try fileSystem.readFileContents(path)
            return try bytes.withData { data in
                let decoder = JSONDecoder.makeWithDefaults()
                return try decoder.decode(ArtifactsArchiveMetadata.self, from: data)
            }
        } catch {
            throw StringError("failed parsing ArtifactsArchive info.json at '\(path)': \(error)")
        }
    }
}

extension ArtifactsArchiveMetadata: Decodable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case artifacts
    }
}

extension ArtifactsArchiveMetadata.Artifact: Decodable {
    enum CodingKeys: String, CodingKey {
        case type
        case version
        case variants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(ArtifactsArchiveMetadata.ArtifactType.self, forKey: .type)
        self.version = try container.decode(String.self, forKey: .version)
        self.variants = try container.decode([ArtifactsArchiveMetadata.Variant].self, forKey: .variants)
    }
}

extension ArtifactsArchiveMetadata.Variant: Decodable {
    enum CodingKeys: String, CodingKey {
        case path
        case supportedTriples
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.supportedTriples = try container.decode([String].self, forKey: .supportedTriples).map { try Triple($0) }
        self.path = try container.decode(String.self, forKey: .path)
    }
}
