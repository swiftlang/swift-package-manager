//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
import TSCBasic

public enum RegistryReleaseMetadataStorage {
    public static let fileName = ".registry-metadata"

    private static let encoder = JSONEncoder.makeWithDefaults()
    private static let decoder = JSONDecoder.makeWithDefaults()

    public static func save(_ metadata: RegistryReleaseMetadata, to path: Basics.AbsolutePath, fileSystem: FileSystem) throws {
        let codableMetadata = CodableRegistryReleaseMetadata(metadata)
        let data = try Self.encoder.encode(codableMetadata)
        try fileSystem.writeFileContents(path, data: data)
    }

    public static func load(from path: Basics.AbsolutePath, fileSystem: FileSystem) throws -> RegistryReleaseMetadata {
        let codableMetadata = try Self.decoder.decode(
            path: path,
            fileSystem: fileSystem,
            as: CodableRegistryReleaseMetadata.self
        )
        return try RegistryReleaseMetadata(codableMetadata)
    }
}

private struct CodableRegistryReleaseMetadata: Codable {
    public let registry: URL
    public let signature: Signature?
    public let author: Author?
    public let description: String?
    public let licenseURL: URL?
    public let readmeURL: URL?
    public let scmRepositoryURLs: [SourceControlURL]?

    init(_ seed: RegistryReleaseMetadata) {
        switch seed.source {
        case .registry(let url):
            self.registry = url
        }
        self.signature = seed.signature.map { signature in
            .init(
                signedBy: signature.signedBy.flatMap {
                    switch $0 {
                    case .recognized(let type, let commonName, let organization, let identity):
                        return .recognized(
                            type: type,
                            commonName: commonName,
                            organization: organization,
                            identity: identity
                        )
                    case .unrecognized(let commonName, let organization):
                        return .unrecognized(commonName: commonName, organization: organization)
                    }
                },
                format: signature.format,
                base64: Data(signature.value).base64EncodedString()
            )
        }
        self.author = seed.metadata.author.map {
            .init(
                name: $0.name,
                emailAddress: $0.emailAddress,
                description: $0.description,
                url: $0.url,
                organization: $0.organization.map {
                    .init(
                        name: $0.name,
                        emailAddress: $0.emailAddress,
                        description: $0.description,
                        url: $0.url
                    )
                }
            )
        }
        self.description = seed.metadata.description
        self.licenseURL = seed.metadata.licenseURL
        self.readmeURL = seed.metadata.readmeURL
        self.scmRepositoryURLs = seed.metadata.scmRepositoryURLs
    }

    public struct Signature: Codable {
        let signedBy: SigningEntity?
        let format: String
        let base64: String
    }

    public enum SigningEntity: Codable {
        case recognized(type: String, commonName: String?, organization: String?, identity: String?)
        case unrecognized(commonName: String?, organization: String?)
    }

    public struct Author: Codable {
        let name: String
        let emailAddress: String?
        let description: String?
        let url: URL?
        let organization: Organization?
    }

    struct Organization: Codable {
        let name: String
        let emailAddress: String?
        let description: String?
        let url: URL?
    }
}

extension RegistryReleaseMetadata {
    fileprivate init(_ seed: CodableRegistryReleaseMetadata) throws {
        self.init(
            source: .registry(seed.registry),
            metadata: .init(
                author: seed.author.flatMap {
                    .init(
                        name: $0.name,
                        emailAddress: $0.emailAddress,
                        description: $0.description,
                        url: $0.url,
                        organization: $0.organization.flatMap {
                            .init(
                                name: $0.name,
                                emailAddress: $0.emailAddress,
                                description: $0.description,
                                url: $0.url
                            )
                        }
                    )
                },
                description: seed.description,
                licenseURL: seed.licenseURL,
                readmeURL: seed.readmeURL,
                scmRepositoryURLs: seed.scmRepositoryURLs
            ),
            signature: try seed.signature.flatMap { signature in
                guard let signatureData = Data(base64Encoded: signature.base64) else {
                    throw StringError("invalid base64 signature")
                }
                return .init(
                    signedBy: signature.signedBy.flatMap {
                        switch $0 {
                        case .recognized(let type, let commonName, let organization, let identity):
                            return .recognized(
                                type: type,
                                commonName: commonName,
                                organization: organization,
                                identity: identity
                            )
                        case .unrecognized(let commonName, let organization):
                            return .unrecognized(commonName: commonName, organization: organization)
                        }
                    },
                    format: signature.format,
                    value: Array(signatureData)
                )
            }
        )
    }
}
