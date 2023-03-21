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
    let directoryPath: AbsolutePath

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileSystem: FileSystem, directoryPath: AbsolutePath) {
        self.fileSystem = fileSystem
        self.directoryPath = directoryPath

        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    public func get(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]], Error>)
            -> Void
    ) {
        self.get(
            reference: package,
            version: version,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    public func put(
        package: PackageIdentity,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.put(
            reference: package,
            version: version,
            fingerprint: fingerprint,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    public func get(
        package: PackageReference,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]], Error>)
            -> Void
    ) {
        self.get(
            reference: package,
            version: version,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    public func put(
        package: PackageReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.put(
            reference: package,
            version: version,
            fingerprint: fingerprint,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    private func get(
        reference: FingerprintReference,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]], Error>)
            -> Void
    ) {
        let callback = self.makeAsync(callback, on: callbackQueue)

        do {
            let packageFingerprints = try self.withLock {
                try self.loadFromDisk(reference: reference)
            }

            guard let fingerprints = packageFingerprints[version] else {
                throw PackageFingerprintStorageError.notFound
            }

            callback(.success(fingerprints))
        } catch {
            callback(.failure(error))
        }
    }

    private func put(
        reference: FingerprintReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let callback = self.makeAsync(callback, on: callbackQueue)

        do {
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
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }

    private func loadFromDisk(reference: FingerprintReference) throws -> PackageFingerprints {
        let path = try self.directoryPath.appending(component: reference.fingerprintsFilename())

        guard self.fileSystem.exists(path) else {
            return .init()
        }

        let data: Data = try fileSystem.readFileContents(path)
        guard data.count > 0 else {
            return .init()
        }

        let container = try self.decoder.decode(StorageModel.Container.self, from: data)
        return try container.packageFingerprints()
    }

    private func saveToDisk(reference: FingerprintReference, fingerprints: PackageFingerprints) throws {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }

        let container = try StorageModel.Container(fingerprints)
        let buffer = try encoder.encode(container)

        let path = try self.directoryPath.appending(component: reference.fingerprintsFilename())
        try self.fileSystem.writeFileContents(path, bytes: ByteString(buffer))
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
    struct Container: Codable {
        // version -> fingerprint kind -> fingerprint content type
        let versionFingerprints: [String: [String: [String: StoredFingerprint.V2]]]
        let schemaVersion: SchemaVersion = .v2

        init(_ versionFingerprints: PackageFingerprints) throws {
            self.versionFingerprints = try Dictionary(
                throwingUniqueKeysWithValues: versionFingerprints.map { version, fingerprintsForVersion in
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

                                    let storedFingerprint = StoredFingerprint.V2(
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
            )
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
                                    guard let originURL = URL(string: storedFingerprint.origin) else {
                                        throw SerializationError.invalidURL(storedFingerprint.origin)
                                    }

                                    let origin: Fingerprint.Origin
                                    switch kind {
                                    case .sourceControl:
                                        origin = .sourceControl(originURL)
                                    case .registry:
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

        private enum CodingKeys: String, CodingKey {
            case versionFingerprints
            case schemaVersion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try container.decodeIfPresent(SchemaVersion.self, forKey: .schemaVersion) ?? .v1

            switch schemaVersion {
            case .v2:
                let versionFingerprints = try container.decode(
                    [String: [String: [String: StoredFingerprint.V2]]].self,
                    forKey: .versionFingerprints
                )
                self.versionFingerprints = try Dictionary(
                    throwingUniqueKeysWithValues: versionFingerprints.map { version, fingerprintsForVersion in
                        let fingerprintsByKind = try Dictionary(
                            throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprintsForKind in
                                let fingerprintsByContentType = try Dictionary(
                                    throwingUniqueKeysWithValues: fingerprintsForKind.map { contentType, fingerprint in
                                        (contentType, fingerprint)
                                    }
                                )
                                return (kind, fingerprintsByContentType)
                            }
                        )
                        return (version, fingerprintsByKind)
                    }
                )
            case .v1:
                let versionFingerprints = try container.decode(
                    [String: [String: StoredFingerprint.V1]].self,
                    forKey: .versionFingerprints
                )
                self.versionFingerprints = try Dictionary(
                    throwingUniqueKeysWithValues: versionFingerprints.map { version, fingerprintsForVersion in
                        let fingerprintsByKind = try Dictionary(
                            throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprint in
                                // All v1 fingerprints are for source code
                                let contentType = StoredFingerprint.V2.ContentType.sourceCode
                                let fingerprintV2 = StoredFingerprint.V2(
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
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            let storageFingerprints = try Dictionary(
                throwingUniqueKeysWithValues: versionFingerprints.map { version, fingerprintsForVersion in
                    let fingerprintsByKind = try Dictionary(
                        throwingUniqueKeysWithValues: fingerprintsForVersion.map { kind, fingerprintsForKind in
                            let fingerprintsByContentType = try Dictionary(
                                throwingUniqueKeysWithValues: fingerprintsForKind.map { contentType, fingerprint in
                                    (contentType, fingerprint)
                                }
                            )
                            return (kind, fingerprintsByContentType)
                        }
                    )
                    return (version, fingerprintsByKind)
                }
            )
            try container.encode(storageFingerprints, forKey: .versionFingerprints)
            try container.encode(self.schemaVersion, forKey: .schemaVersion)
        }
    }

    enum SchemaVersion: String, Codable {
        case v1 = "1"
        case v2 = "2"
    }

    struct StoredFingerprint: Codable {
        struct V1: Codable {
            let origin: String
            let fingerprint: String
        }

        struct V2: Codable {
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
    }
}

extension Fingerprint.ContentType {
    fileprivate static func from(_ storage: StorageModel.StoredFingerprint.V2.ContentType) -> Fingerprint.ContentType {
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
    func fingerprintsFilename() throws -> String
}

extension PackageIdentity: FingerprintReference {
    func fingerprintsFilename() -> String {
        "\(self.description).json"
    }
}

extension PackageReference: FingerprintReference {
    func fingerprintsFilename() throws -> String {
        guard case .remoteSourceControl(let sourceControlURL) = self.kind else {
            throw StringError("Package kind [\(self.kind)] does not support fingerprints")
        }

        let canonicalLocation = CanonicalPackageLocation(sourceControlURL.absoluteString)
        let locationHash = String(format: "%02x", canonicalLocation.description.hashValue)
        return "\(self.identity.description)-\(locationHash).json"
    }
}

private enum SerializationError: Error {
    case unknownKind(String)
    case invalidURL(String)
}
