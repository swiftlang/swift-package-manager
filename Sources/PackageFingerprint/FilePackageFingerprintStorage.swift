//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import PackageModel
import TSCBasic

import struct TSCUtility.Version

public struct FilePackageFingerprintStorage: PackageFingerprintStorage {
    let fileSystem: FileSystem
    let directoryPath: Basics.AbsolutePath

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileSystem: FileSystem, directoryPath: Basics.AbsolutePath) {
        self.fileSystem = fileSystem
        self.directoryPath = directoryPath

        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    public func get(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope
    ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]] {
        try self.get(
            reference: package,
            version: version,
            observabilityScope: observabilityScope
        )
    }

    public func put(
        package: PackageIdentity,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.put(
            reference: package,
            version: version,
            fingerprint: fingerprint,
            observabilityScope: observabilityScope
        )
    }

    public func get(
        package: PackageReference,
        version: Version,
        observabilityScope: ObservabilityScope
    ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]] {
        try self.get(
            reference: package,
            version: version,
            observabilityScope: observabilityScope
        )
    }

    public func put(
        package: PackageReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.put(
            reference: package,
            version: version,
            fingerprint: fingerprint,
            observabilityScope: observabilityScope
        )
    }

    private func get(
        reference: FingerprintReference,
        version: Version,
        observabilityScope: ObservabilityScope
    ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]] {
        let packageFingerprints = try self.withLock {
            try self.loadFromDisk(reference: reference)
        }

        guard let fingerprints = packageFingerprints[version] else {
            throw PackageFingerprintStorageError.notFound
        }
        return fingerprints
    }

    private func put(
        reference: FingerprintReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.withLock {
            var packageFingerprints = try self.loadFromDisk(reference: reference)

            if let existing = packageFingerprints[version]?[fingerprint.origin.kind]?[fingerprint.contentType] {
                // Error if we try to write a different fingerprint
                guard fingerprint == existing else {
                    throw PackageFingerprintStorageError.conflict(given: fingerprint, existing: existing)
                }
                // Don't need to do anything if fingerprints are the same
                return
            }

            var fingerprintsForVersion = packageFingerprints.removeValue(forKey: version) ?? [:]
            var fingerprintsForKind = fingerprintsForVersion.removeValue(forKey: fingerprint.origin.kind) ?? [:]
            fingerprintsForKind[fingerprint.contentType] = fingerprint
            fingerprintsForVersion[fingerprint.origin.kind] = fingerprintsForKind
            packageFingerprints[version] = fingerprintsForVersion

            try self.saveToDisk(reference: reference, fingerprints: packageFingerprints)
        }
    }

    private func loadFromDisk(reference: FingerprintReference) throws -> PackageFingerprints {
        let path = try self.directoryPath.appending(component: reference.fingerprintsFilename)

        guard self.fileSystem.exists(path) else {
            return .init()
        }

        let data: Data = try fileSystem.readFileContents(path)
        guard data.count > 0 else {
            return .init()
        }

        return try StorageModel.decode(data: data, decoder: self.decoder)
    }

    private func saveToDisk(reference: FingerprintReference, fingerprints: PackageFingerprints) throws {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }

        let buffer = try StorageModel.encode(packageFingerprints: fingerprints, encoder: self.encoder)
        let path = try self.directoryPath.appending(component: reference.fingerprintsFilename)
        try self.fileSystem.writeFileContents(path, data: buffer)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.directoryPath, type: .exclusive, body)
    }

    private func makeAsync<T>(
        _ closure: @escaping (Result<T, Error>) -> Void,
        on queue: DispatchQueue
    ) -> (Result<T, Error>) -> Void {
        { result in queue.async { closure(result) } }
    }
}

private enum StorageModel {
    struct SchemaVersion: Codable {
        let version: Int?
    }

    enum Container {
        struct V1: Codable {
            let version: Int?
            // version -> fingerprint kind
            let versionFingerprints: [String: [String: StoredFingerprint]]

            struct StoredFingerprint: Codable {
                let origin: String
                let fingerprint: String
            }
        }

        struct V2: Codable {
            let version: Int
            // version -> fingerprint kind -> fingerprint content type
            let versionFingerprints: [String: [String: [String: StoredFingerprint]]]

            struct StoredFingerprint: Codable {
                let origin: String
                let fingerprint: String
                let contentType: ContentType

                enum ContentType: Codable {
                    case sourceCode
                    case manifest
                    case versionSpecificManifest(toolsVersion: ToolsVersion)

                    static func from(contentType: Fingerprint.ContentType) -> ContentType {
                        switch contentType {
                        case .sourceCode:
                            return .sourceCode
                        case .manifest(.none):
                            return .manifest
                        case .manifest(.some(let toolsVersion)):
                            return .versionSpecificManifest(toolsVersion: toolsVersion)
                        }
                    }
                }
            }

            init(versionFingerprints: [String: [String: [String: StoredFingerprint]]]) {
                self.version = 2
                self.versionFingerprints = versionFingerprints
            }

            func packageFingerprints() throws -> PackageFingerprints {
                try Dictionary(
                    throwingUniqueKeysWithValues: self.versionFingerprints.map { version, fingerprintsForVersion in
                        let fingerprintsByKind = try Dictionary(
                            throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprintsForKind in
                                guard let kind = Fingerprint.Kind(rawValue: kind) else {
                                    throw SerializationError.unknownKind(kind)
                                }

                                let fingerprintsByContentType = try Dictionary(
                                    throwingUniqueKeysWithValues: fingerprintsForKind.map { _, storedFingerprint in
                                        let origin: Fingerprint.Origin
                                        switch kind {
                                        case .sourceControl:
                                            origin = .sourceControl(SourceControlURL(storedFingerprint.origin))
                                        case .registry:
                                            guard let originURL = URL(string: storedFingerprint.origin) else {
                                                throw SerializationError.invalidURL(storedFingerprint.origin)
                                            }
                                            origin = .registry(originURL)
                                        }

                                        let contentType = Fingerprint.ContentType.from(storedFingerprint.contentType)
                                        let fingerprint = Fingerprint(
                                            origin: origin,
                                            value: storedFingerprint.fingerprint,
                                            contentType: contentType
                                        )
                                        return (contentType, fingerprint)
                                    }
                                )

                                return (kind, fingerprintsByContentType)
                            }
                        )
                        return (Version(stringLiteral: version), fingerprintsByKind)
                    }
                )
            }
        }
    }

    static func decode(data: Data, decoder: JSONDecoder) throws -> PackageFingerprints {
        let schemaVersion = try decoder.decode(SchemaVersion.self, from: data)
        switch schemaVersion.version {
        case .some(2):
            let container = try decoder.decode(Container.V2.self, from: data)
            return try container.packageFingerprints()
        case .some(1), .none: // v1
            let containerV1 = try decoder.decode(Container.V1.self, from: data)
            // Convert v1 to v2
            let containerV2 = Container.V2(versionFingerprints: try Dictionary(
                throwingUniqueKeysWithValues: containerV1.versionFingerprints.map { version, fingerprintsForVersion in
                    let fingerprintsByKind = try Dictionary(
                        throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprint in
                            // All v1 fingerprints are for source code
                            let contentType = Container.V2.StoredFingerprint.ContentType.sourceCode
                            let fingerprintV2 = Container.V2.StoredFingerprint(
                                origin: fingerprint.origin,
                                fingerprint: fingerprint.fingerprint,
                                contentType: contentType
                            )
                            return (
                                kind,
                                [Fingerprint.ContentType.from(contentType).description: fingerprintV2]
                            )
                        }
                    )
                    return (version, fingerprintsByKind)
                }
            ))
            return try containerV2.packageFingerprints()
        default:
            throw StringError(
                "unknown package fingerprint storage version '\(String(describing: schemaVersion.version))'"
            )
        }
    }

    static func encode(packageFingerprints: PackageFingerprints, encoder: JSONEncoder) throws -> Data {
        let container = Container.V2(versionFingerprints: try Dictionary(
            throwingUniqueKeysWithValues: packageFingerprints.map { version, fingerprintsForVersion in
                let fingerprintsByKind = try Dictionary(
                    throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprintsForKind in
                        let fingerprintsByContentType = try Dictionary(
                            throwingUniqueKeysWithValues: fingerprintsForKind.map { contentType, fingerprint in
                                let origin: String
                                switch fingerprint.origin {
                                case .sourceControl(let url):
                                    origin = url.absoluteString
                                case .registry(let url):
                                    origin = url.absoluteString
                                }

                                let storedFingerprint = Container.V2.StoredFingerprint(
                                    origin: origin,
                                    fingerprint: fingerprint.value,
                                    contentType: .from(contentType: contentType)
                                )
                                return (contentType.description, storedFingerprint)
                            }
                        )
                        return (kind.rawValue, fingerprintsByContentType)
                    }
                )
                return (version.description, fingerprintsByKind)
            }
        ))
        return try encoder.encode(container)
    }
}

extension Fingerprint.ContentType {
    fileprivate static func from(_ storage: StorageModel.Container.V2.StoredFingerprint.ContentType) -> Fingerprint
        .ContentType
    {
        switch storage {
        case .sourceCode:
            return .sourceCode
        case .manifest:
            return .manifest(.none)
        case .versionSpecificManifest(let toolsVersion):
            return .manifest(toolsVersion)
        }
    }
}

protocol FingerprintReference {
    var fingerprintsFilename: String { get throws }
}

extension PackageIdentity: FingerprintReference {
    var fingerprintsFilename: String {
        "\(self.description).json"
    }
}

extension PackageReference: FingerprintReference {
    var fingerprintsFilename: String {
        get throws {
            guard case .remoteSourceControl(let sourceControlURL) = self.kind else {
                throw StringError("Package kind [\(self.kind)] does not support fingerprints")
            }
            
            let canonicalLocation = CanonicalPackageLocation(sourceControlURL.absoluteString)
            // Cannot use hashValue because it is not consistent across executions
            let locationHash = canonicalLocation.description.sha256Checksum.prefix(8)
            return "\(self.identity.description)-\(locationHash).json"
        }
    }
}

private enum SerializationError: Error {
    case unknownKind(String)
    case invalidURL(String)
}
