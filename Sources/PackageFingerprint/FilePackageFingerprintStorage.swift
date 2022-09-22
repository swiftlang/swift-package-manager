//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
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

    public func get(package: PackageIdentity,
                    version: Version,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void) {
        self.get(reference: package,
                 version: version,
                 observabilityScope: observabilityScope,
                 callbackQueue: callbackQueue,
                 callback: callback)
    }

    public func put(package: PackageIdentity,
                    version: Version,
                    fingerprint: Fingerprint,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<Void, Error>) -> Void) {
        self.put(reference: package,
                 version: version,
                 fingerprint: fingerprint,
                 observabilityScope: observabilityScope,
                 callbackQueue: callbackQueue,
                 callback: callback)
    }

    public func get(package: PackageReference,
                    version: Version,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void) {
        self.get(reference: package,
                 version: version,
                 observabilityScope: observabilityScope,
                 callbackQueue: callbackQueue,
                 callback: callback)
    }

    public func put(package: PackageReference,
                    version: Version,
                    fingerprint: Fingerprint,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<Void, Error>) -> Void) {
        self.put(reference: package,
                 version: version,
                 fingerprint: fingerprint,
                 observabilityScope: observabilityScope,
                 callbackQueue: callbackQueue,
                 callback: callback)
    }

    private func get(reference: FingerprintReference,
                     version: Version,
                     observabilityScope: ObservabilityScope,
                     callbackQueue: DispatchQueue,
                     callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void) {
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

    private func put(reference: FingerprintReference,
                     version: Version,
                     fingerprint: Fingerprint,
                     observabilityScope: ObservabilityScope,
                     callbackQueue: DispatchQueue,
                     callback: @escaping (Result<Void, Error>) -> Void) {
        let callback = self.makeAsync(callback, on: callbackQueue)

        do {
            try self.withLock {
                var packageFingerprints = try self.loadFromDisk(reference: reference)

                if let existing = packageFingerprints[version]?[fingerprint.origin.kind] {
                    // Error if we try to write a different fingerprint
                    guard fingerprint == existing else {
                        throw PackageFingerprintStorageError.conflict(given: fingerprint, existing: existing)
                    }
                    // Don't need to do anything if fingerprints are the same
                    return
                }

                var fingerprints = packageFingerprints.removeValue(forKey: version) ?? [:]
                fingerprints[fingerprint.origin.kind] = fingerprint
                packageFingerprints[version] = fingerprints

                try self.saveToDisk(reference: reference, fingerprints: packageFingerprints)
            }
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }

    private func loadFromDisk(reference: FingerprintReference) throws -> PackageFingerprints {
        let path = self.directoryPath.appending(component: reference.fingerprintsFilename)

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

        let path = self.directoryPath.appending(component: reference.fingerprintsFilename)
        try self.fileSystem.writeFileContents(path, bytes: ByteString(buffer))
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.directoryPath, type: .exclusive, body)
    }

    private func makeAsync<T>(_ closure: @escaping (Result<T, Error>) -> Void, on queue: DispatchQueue) -> (Result<T, Error>) -> Void {
        { result in queue.async { closure(result) } }
    }
}

private enum StorageModel {
    struct Container: Codable {
        let versionFingerprints: [String: [String: StoredFingerprint]]

        init(_ versionFingerprints: PackageFingerprints) throws {
            self.versionFingerprints = try Dictionary(throwingUniqueKeysWithValues: versionFingerprints.map { version, fingerprints in
                let fingerprintByKind: [String: StoredFingerprint] = Dictionary(uniqueKeysWithValues: fingerprints.map { kind, fingerprint in
                    let origin: String
                    switch fingerprint.origin {
                    case .sourceControl(let url):
                        origin = url.absoluteString
                    case .registry(let url):
                        origin = url.absoluteString
                    }
                    return (kind.rawValue, StoredFingerprint(origin: origin, fingerprint: fingerprint.value))
                })
                return (version.description, fingerprintByKind)
            })
        }

        func packageFingerprints() throws -> PackageFingerprints {
            try Dictionary(throwingUniqueKeysWithValues: self.versionFingerprints.map { version, fingerprints in
                let fingerprintByKind: [Fingerprint.Kind: Fingerprint] = try Dictionary(uniqueKeysWithValues: fingerprints.map { kind, fingerprint in
                    guard let kind = Fingerprint.Kind(rawValue: kind) else {
                        throw SerializationError.unknownKind(kind)
                    }
                    guard let originURL = URL(string: fingerprint.origin) else {
                        throw SerializationError.invalidURL(fingerprint.origin)
                    }

                    let origin: Fingerprint.Origin
                    switch kind {
                    case .sourceControl:
                        origin = .sourceControl(originURL)
                    case .registry:
                        origin = .registry(originURL)
                    }

                    return (kind, Fingerprint(origin: origin, value: fingerprint.fingerprint))
                })
                return (Version(stringLiteral: version), fingerprintByKind)
            })
        }
    }

    struct StoredFingerprint: Codable {
        let origin: String
        let fingerprint: String
    }
}

protocol FingerprintReference {
    var fingerprintsFilename: String { get }
}

extension PackageIdentity: FingerprintReference {
    var fingerprintsFilename: String {
        "\(self.description).json"
    }
}

extension PackageReference: FingerprintReference {
    var fingerprintsFilename: String {
        guard case .remoteSourceControl(let sourceControlURL) = self.kind else {
            fatalError("Package kind [\(self.kind)] does not support fingerprints")
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
