/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import PackageFingerprint
import PackageModel
import TSCBasic
import TSCUtility

public class MockPackageFingerprintStorage: PackageFingerprintStorage {
    private var packageFingerprints: [PackageIdentity: [Version: [Fingerprint.Kind: Fingerprint]]]
    private let lock = Lock()

    public init(_ packageFingerprints: [PackageIdentity: [Version: [Fingerprint.Kind: Fingerprint]]] = [:]) {
        self.packageFingerprints = packageFingerprints
    }

    public func get(package: PackageIdentity,
                    version: Version,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void)
    {
        if let fingerprints = self.lock.withLock({ self.packageFingerprints[package]?[version] }) {
            callbackQueue.async {
                callback(.success(fingerprints))
            }
        } else {
            callbackQueue.async {
                callback(.failure(PackageFingerprintStorageError.notFound))
            }
        }
    }

    public func put(package: PackageIdentity,
                    version: Version,
                    fingerprint: Fingerprint,
                    observabilityScope: ObservabilityScope,
                    callbackQueue: DispatchQueue,
                    callback: @escaping (Result<Void, Error>) -> Void)
    {
        do {
            try self.lock.withLock {
                var versionFingerprints = self.packageFingerprints[package] ?? [:]
                var fingerprints = versionFingerprints[version] ?? [:]

                if let existing = fingerprints[fingerprint.origin.kind] {
                    // Error if we try to write a different fingerprint
                    guard fingerprint == existing else {
                        throw PackageFingerprintStorageError.conflict(given: fingerprint, existing: existing)
                    }
                    // Don't need to do anything if fingerprints are the same
                    return
                }

                fingerprints[fingerprint.origin.kind] = fingerprint
                versionFingerprints[version] = fingerprints
                self.packageFingerprints[package] = versionFingerprints
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
