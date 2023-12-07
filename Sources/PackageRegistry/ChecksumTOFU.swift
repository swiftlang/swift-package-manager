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
    private let versionMetadataProvider: (PackageIdentity.RegistryIdentity, Version) throws -> RegistryClient
        .PackageVersionMetadata

    init(
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        versionMetadataProvider: @escaping (PackageIdentity.RegistryIdentity, Version) throws -> RegistryClient
            .PackageVersionMetadata
    ) {
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.versionMetadataProvider = versionMetadataProvider
    }

    // MARK: - source archive
    func validateSourceArchive(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.validateSourceArchive(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                timeout: timeout,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                completion: $0
            )
        }
    }
    
    @available(*, noasync, message: "Use the async alternative")
    func validateSourceArchive(
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
                                    warning: "the checksum \(checksum) for source archive of \(package) \(version) does not match previously recorded value \(expectedChecksum)"
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
            contentType: .sourceCode,
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
                do {
                    let versionMetadata = try self.versionMetadataProvider(package, version)
                    guard let sourceArchiveResource = versionMetadata.sourceArchive else {
                        throw RegistryError.missingSourceArchive
                    }
                    guard let checksum = sourceArchiveResource.checksum else {
                        throw RegistryError.sourceArchiveMissingChecksum(
                            registry: registry,
                            package: package.underlying,
                            version: version
                        )
                    }

                    self.writeToStorage(
                        registry: registry,
                        package: package,
                        version: version,
                        checksum: checksum,
                        contentType: .sourceCode,
                        observabilityScope: observabilityScope,
                        callbackQueue: callbackQueue
                    ) { writeResult in
                        completion(writeResult.tryMap { _ in checksum })
                    }
                } catch {
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

    // MARK: - manifests
    func validateManifest(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        toolsVersion: ToolsVersion?,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.validateManifest(
                registry: registry,
                package: package,
                version: version,
                toolsVersion: toolsVersion,
                checksum: checksum,
                timeout: timeout,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue, 
                completion: $0
            )
        }
    }
    @available(*, noasync, message: "Use the async alternative")
    func validateManifest(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        toolsVersion: ToolsVersion?,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let contentType = Fingerprint.ContentType.manifest(toolsVersion)

        self.readFromStorage(
            package: package,
            version: version,
            contentType: .manifest(toolsVersion),
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(.some(let expectedChecksum)):
                // Previously recorded checksum
                do {
                    if checksum != expectedChecksum {
                        switch self.fingerprintCheckingMode {
                        case .strict:
                            throw RegistryError.invalidChecksum(expected: expectedChecksum, actual: checksum)
                        case .warn:
                            observabilityScope
                                .emit(
                                    warning: "the checksum \(checksum) for \(contentType) of \(package) \(version) does not match previously recorded value \(expectedChecksum)"
                                )
                        }
                    }
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            default:
                self.writeToStorage(
                    registry: registry,
                    package: package,
                    version: version,
                    checksum: checksum,
                    contentType: .manifest(toolsVersion),
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue
                ) { writeResult in
                    completion(writeResult.tryMap { _ in () })
                }
            }
        }
    }

    // MARK: - storage helpers

    private func readFromStorage(
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard let fingerprintStorage else {
            return completion(.success(nil))
        }

        fingerprintStorage.get(
            package: package.underlying,
            version: version,
            kind: .registry,
            contentType: contentType,
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
                    .emit(
                        error: "failed to get registry fingerprint for \(contentType) of \(package) \(version) from storage",
                        underlyingError: error
                    )
                completion(.failure(error))
            }
        }
    }

    private func writeToStorage(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let fingerprintStorage else {
            return completion(.success(()))
        }

        let fingerprint = Fingerprint(origin: .registry(registry.url), value: checksum, contentType: contentType)
        fingerprintStorage.put(
            package: package.underlying,
            version: version,
            fingerprint: fingerprint,
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
                            warning: "the checksum \(checksum) for \(contentType) of \(package) \(version) from \(registry.url.absoluteString) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))"
                        )
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
