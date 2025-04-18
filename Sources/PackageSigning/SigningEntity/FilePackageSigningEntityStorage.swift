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
        observabilityScope: ObservabilityScope
    ) throws -> PackageSigners {
        try self.withLock {
            try self.loadFromDisk(package: package)
        }
    }

    public func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.withLock {
            var packageSigners = try self.loadFromDisk(package: package)

            let otherSigningEntities = packageSigners.signingEntities(of: version).filter { $0 != signingEntity }
            // Error if we try to write a different signing entity for a version
            guard otherSigningEntities.isEmpty else {
                throw PackageSigningEntityStorageError.conflict(
                    package: package,
                    version: version,
                    given: signingEntity,
                    existing: otherSigningEntities.first! // !-safe because otherSigningEntities is not empty
                )
            }

            try self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            try self.saveToDisk(package: package, packageSigners: packageSigners)
        }
    }

    public func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.withLock {
            var packageSigners = try self.loadFromDisk(package: package)
            try self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            try self.saveToDisk(package: package, packageSigners: packageSigners)
        }
    }

    public func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.withLock {
            var packageSigners = try self.loadFromDisk(package: package)
            packageSigners.expectedSigner = (signingEntity: signingEntity, fromVersion: version)
            try self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            try self.saveToDisk(package: package, packageSigners: packageSigners)
        }
    }

    public func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws {
        try self.withLock {
            var packageSigners = try self.loadFromDisk(package: package)
            packageSigners.expectedSigner = (signingEntity: signingEntity, fromVersion: version)
            // Delete all other signers
            packageSigners.signers = packageSigners.signers.filter { $0.key == signingEntity }
            try self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            try self.saveToDisk(package: package, packageSigners: packageSigners)
        }
    }

    private func add(
        packageSigners: inout PackageSigners,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        version: Version
    ) throws {
        guard case .recognized = signingEntity else {
            throw PackageSigningEntityStorageError.unrecognizedSigningEntity(signingEntity)
        }

        if var existingSigner = packageSigners.signers.removeValue(forKey: signingEntity) {
            existingSigner.origins.insert(origin)
            existingSigner.versions.insert(version)
            packageSigners.signers[signingEntity] = existingSigner
        } else {
            let signer = PackageSigner(
                signingEntity: signingEntity,
                origins: [origin],
                versions: [version]
            )
            packageSigners.signers[signingEntity] = signer
        }
    }

    private func loadFromDisk(package: PackageIdentity) throws -> PackageSigners {
        let path = self.directoryPath.appending(component: package.signedVersionsFilename)

        guard self.fileSystem.exists(path) else {
            return .init()
        }

        let data: Data = try fileSystem.readFileContents(path)
        guard data.count > 0 else {
            return .init()
        }

        let container = try self.decoder.decode(StorageModel.Container.self, from: data)
        return try container.packageSigners()
    }

    private func saveToDisk(package: PackageIdentity, packageSigners: PackageSigners) throws {
        if !self.fileSystem.exists(self.directoryPath) {
            try self.fileSystem.createDirectory(self.directoryPath, recursive: true)
        }

        let container = try StorageModel.Container(packageSigners)
        let buffer = try encoder.encode(container)

        let path = self.directoryPath.appending(component: package.signedVersionsFilename)
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
    struct Container: Codable {
        let expectedSigner: ExpectedSigner?
        let signers: [PackageSigner]

        init(_ packageSigners: PackageSigners) throws {
            self.expectedSigner = packageSigners.expectedSigner.map {
                ExpectedSigner(signingEntity: $0.signingEntity, fromVersion: $0.fromVersion)
            }
            self.signers = Array(packageSigners.signers.values)
        }

        func packageSigners() throws -> PackageSigners {
            let signers = try Dictionary(throwingUniqueKeysWithValues: self.signers.map {
                ($0.signingEntity, $0)
            })
            return PackageSigners(
                expectedSigner: self.expectedSigner.map { ($0.signingEntity, $0.fromVersion) },
                signers: signers
            )
        }
    }

    struct ExpectedSigner: Codable {
        let signingEntity: SigningEntity
        let fromVersion: Version
    }
}

extension PackageIdentity {
    var signedVersionsFilename: String {
        "\(self.description).json"
    }
}
