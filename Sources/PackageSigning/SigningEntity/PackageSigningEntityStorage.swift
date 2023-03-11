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
import PackageModel

import struct TSCUtility.Version

public protocol PackageSigningEntityStorage {
    /// For a given package, return the signing entities and the package versions that each of them signed.
    func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[SigningEntity: Set<Version>], Error>) -> Void
    )

    /// Record signing entity for a given package version.
    func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )
}

extension Dictionary where Key == SigningEntity, Value == Set<Version> {
    public func signingEntity(of version: Version) -> SigningEntity? {
        for (signingEntity, versions) in self {
            if versions.contains(version) {
                return signingEntity
            }
        }
        return nil
    }

    public var versionSigners: [Version: SigningEntity] {
        var versionSigners = [Version: SigningEntity]()
        for (signingEntity, versions) in self {
            versions.forEach { version in
                versionSigners[version] = signingEntity
            }
        }
        return versionSigners
    }
}

public enum PackageSigningEntityStorageError: Error, Equatable, CustomStringConvertible {
    case conflict(package: PackageIdentity, version: Version, given: SigningEntity, existing: SigningEntity)

    public var description: String {
        switch self {
        case .conflict(let package, let version, let given, let existing):
            return "\(package) version \(version) was previously signed by '\(existing)', which is different from '\(given)'."
        }
    }
}

public enum SigningEntityCheckingMode: String {
    case strict
    case warn
}
