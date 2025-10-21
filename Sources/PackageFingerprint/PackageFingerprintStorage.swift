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
import PackageModel
import TSCBasic

import struct TSCUtility.Version

public protocol PackageFingerprintStorage {
    func get(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope
    ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]]

    func put(
        package: PackageIdentity,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope
    ) throws

    func get(
        package: PackageReference,
        version: Version,
        observabilityScope: ObservabilityScope
    ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]]

    func put(
        package: PackageReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope
    ) throws
}

extension PackageFingerprintStorage {
    public func get(
        package: PackageIdentity,
        version: Version,
        kind: Fingerprint.Kind,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope
    ) throws -> Fingerprint {
        let fingerprints = try self.get(
            package: package,
            version: version,
            observabilityScope: observabilityScope
        )
        guard let fingerprint = fingerprints[kind]?[contentType] else {
            throw PackageFingerprintStorageError.notFound
        }
        return fingerprint
    }

    public func get(
        package: PackageReference,
        version: Version,
        kind: Fingerprint.Kind,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope
    ) throws -> Fingerprint{
        let fingerprints = try self.get(
            package: package,
            version: version,
            observabilityScope: observabilityScope
        )
        guard let fingerprint = fingerprints[kind]?[contentType] else {
            throw PackageFingerprintStorageError.notFound
        }
        return fingerprint
    }

    private func get(
        kind: Fingerprint.Kind,
        contentType: Fingerprint.ContentType,
        _ fingerprintsByKindResult: Result<[Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]], Error>,
        callback: @escaping (Result<Fingerprint, Error>) -> Void
    ) {
        callback(fingerprintsByKindResult.tryMap { fingerprintsByKind in
            guard let fingerprintsByContentType = fingerprintsByKind[kind],
                  let fingerprint = fingerprintsByContentType[contentType]
            else {
                throw PackageFingerprintStorageError.notFound
            }
            return fingerprint
        })
    }
}

public enum PackageFingerprintStorageError: Error, Equatable, CustomStringConvertible {
    case conflict(given: Fingerprint, existing: Fingerprint)
    case notFound

    public var description: String {
        switch self {
        case .conflict(let given, let existing):
            return "fingerprint \(given) is different from previously recorded value \(existing)"
        case .notFound:
            return "not found"
        }
    }
}
