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
import Dispatch
import Foundation
import PackageModel
import TSCBasic

import struct TSCUtility.Version

public struct FilePackageSigningEntityStorage: PackageSigningEntityStorage {
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
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[SigningEntity: Set<Version>], Error>) -> Void
    ) {
        let callback = self.makeAsync(callback, on: callbackQueue)

        do {
            let signedVersions = try self.withLock {
                try self.loadFromDisk(package: package)
            }
            callback(.success(signedVersions))
        } catch {
            callback(.failure(error))
        }
    }

    public func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let callback = self.makeAsync(callback, on: callbackQueue)

        do {
            try self.withLock {
                var signedVersions = try self.loadFromDisk(package: package)

                if let existing = signedVersions.signingEntity(of: version) {
                    // Error if we try to write a different signing entity for a version
                    guard signingEntity == existing else {
                        throw PackageSigningEntityStorageError.conflict(
                            package: package,
                            version: version,
                            given: signingEntity,
                            existing: existing
                        )
                    }
                    // Don't need to do anything if signing entities are the same
                    return
                }

                var versions = signedVersions.removeValue(forKey: signingEntity) ?? []
                versions.insert(version)
                signedVersions[signingEntity] = versions

                try self.saveToDisk(package: package, signedVersions: signedVersions)
            }
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }

    private func loadFromDisk(package: PackageIdentity) throws -> [SigningEntity: Set<Version>] {
        let path = self.directoryPath.appending(component: package.signedVersionsFilename)

        guard self.fileSystem.exists(path) else {
            return [:]
        }

        let data: Data = try fileSystem.readFileContents(path)
        guard data.count > 0 else {
            return [:]
        }

        let container = try self.decoder.decode(StorageModel.Container.self, from: data)
        return try container.signedVersionsByEntity()
    }

    private func saveToDisk(package: PackageIdentity, signedVersions: [SigningEntity: Set<Version>]) throws {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }

        let container = try StorageModel.Container(signedVersions)
        let buffer = try encoder.encode(container)

        let path = self.directoryPath.appending(component: package.signedVersionsFilename)
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
        let signedVersions: [SignedVersions]

        init(_ signedVersionsByEntity: [SigningEntity: Set<Version>]) throws {
            self.signedVersions = signedVersionsByEntity
                .map { SignedVersions(signingEntity: $0.key, versions: $0.value) }
        }

        func signedVersionsByEntity() throws -> [SigningEntity: Set<Version>] {
            try Dictionary(throwingUniqueKeysWithValues: self.signedVersions.map {
                ($0.signingEntity, $0.versions)
            })
        }
    }

    struct SignedVersions: Codable {
        let signingEntity: SigningEntity
        let versions: Set<Version>
    }
}

extension PackageIdentity {
    var signedVersionsFilename: String {
        "\(self.description).json"
    }
}

extension Dictionary where Key == SigningEntity, Value == Set<Version> {
    fileprivate func signingEntity(of version: Version) -> SigningEntity? {
        for (signingEntity, versions) in self {
            if versions.contains(version) {
                return signingEntity
            }
        }
        return nil
    }
}
