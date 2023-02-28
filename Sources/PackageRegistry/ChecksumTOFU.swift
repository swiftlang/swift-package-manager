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

import Dispatch

import Basics
import PackageFingerprint
import PackageModel

import struct TSCUtility.Version

struct PackageVersionChecksumTOFU {
    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode

    private let registryClient: RegistryClient

    init(
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        registryClient: RegistryClient
    ) {
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.registryClient = registryClient
    }

    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.getExpectedChecksum(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            completion(
                result.tryMap { expectedChecksum in
                    if checksum != expectedChecksum {
                        switch self.fingerprintCheckingMode {
                        case .strict:
                            throw RegistryError.invalidChecksum(expected: expectedChecksum, actual: checksum)
                        case .warn:
                            observabilityScope
                                .emit(
                                    warning: "The checksum \(checksum) does not match previously recorded value \(expectedChecksum)"
                                )
                        }
                    }
                }
            )
        }
    }

    private func getExpectedChecksum(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // We either use a previously recorded checksum, or fetch it from the registry.
        self.readFromStorage(
            package: package,
            version: version,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(.some(let savedChecksum)):
                completion(.success(savedChecksum))
            default:
                // Try fetching checksum from registry if:
                //   - No storage available
                //   - Checksum not found in storage
                //   - Reading from storage resulted in error
                self.registryClient.getRawPackageVersionMetadata(
                    registry: registry,
                    package: package,
                    version: version,
                    timeout: timeout,
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue
                ) { result in
                    switch result {
                    case .success(let metadata):
                        guard let sourceArchive = metadata.sourceArchive else {
                            return completion(.failure(RegistryError.missingSourceArchive))
                        }

                        guard let checksum = sourceArchive.checksum else {
                            return completion(.failure(RegistryError.invalidSourceArchive))
                        }

                        self.writeToStorage(
                            registry: registry,
                            package: package,
                            version: version,
                            checksum: checksum,
                            observabilityScope: observabilityScope,
                            callbackQueue: callbackQueue
                        ) { writeResult in
                            completion(writeResult.tryMap { _ in checksum })
                        }
                    case .failure(RegistryError.failedRetrievingReleaseInfo(_, _, _, let error)):
                        completion(.failure(RegistryError.failedRetrievingReleaseChecksum(
                            registry: registry,
                            package: package.underlying,
                            version: version,
                            error: error
                        )))
                    case .failure(let error):
                        completion(.failure(RegistryError.failedRetrievingReleaseChecksum(
                            registry: registry,
                            package: package.underlying,
                            version: version,
                            error: error
                        )))
                    }
                }
            }
        }
    }

    private func readFromStorage(
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard let fingerprintStorage = self.fingerprintStorage else {
            return completion(.success(nil))
        }

        fingerprintStorage.get(
            package: package.underlying,
            version: version,
            kind: .registry,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let fingerprint):
                completion(.success(fingerprint.value))
            case .failure(PackageFingerprintStorageError.notFound):
                completion(.success(nil))
            case .failure(let error):
                observabilityScope
                    .emit(error: "Failed to get registry fingerprint for \(package) \(version) from storage: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func writeToStorage(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let fingerprintStorage = self.fingerprintStorage else {
            return completion(.success(()))
        }

        fingerprintStorage.put(
            package: package.underlying,
            version: version,
            fingerprint: .init(origin: .registry(registry.url), value: checksum),
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(PackageFingerprintStorageError.conflict(_, let existing)):
                switch self.fingerprintCheckingMode {
                case .strict:
                    completion(.failure(RegistryError.checksumChanged(latest: checksum, previous: existing.value)))
                case .warn:
                    observabilityScope
                        .emit(
                            warning: "The checksum \(checksum) from \(registry.url.absoluteString) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))"
                        )
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
