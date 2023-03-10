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
import class Foundation.NSLock
import PackageModel
import PackageSigning

import struct TSCUtility.Version

public class MockPackageSigningEntityStorage: PackageSigningEntityStorage {
    private var packageSignedVersions: [PackageIdentity: [SigningEntity: Set<Version>]]
    private let lock = NSLock()

    public init(_ packageSignedVersions: [PackageIdentity: [SigningEntity: Set<Version>]] = [:]) {
        self.packageSignedVersions = packageSignedVersions
    }
    
    public func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[SigningEntity: Set<Version>], Error>) -> Void
    ) {
        if let signedVersions = self.lock.withLock({ self.packageSignedVersions[package] }) {
            callbackQueue.async {
                callback(.success(signedVersions))
            }
        } else {
            callbackQueue.async {
                callback(.success([:]))
            }
        }
    }

    public  func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            try self.lock.withLock {
                var signedVersions = self.packageSignedVersions[package] ?? [:]

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
                self.packageSignedVersions[package] = signedVersions
            }

            callbackQueue.async {
                callback(.success(()))
            }
        } catch {
            callbackQueue.async {
                callback(.failure(error))
            }
        }
    }
}
