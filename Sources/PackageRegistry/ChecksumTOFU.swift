//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import Dispatch

import Basics
import PackageFingerprint
import PackageModel

import struct TSCUtility.Version

package struct PackageVersionChecksumTOFU {
    package typealias VersionMetadataProvider =
        (PackageIdentity.RegistryIdentity, Version) async throws -> RegistryClient.PackageVersionMetadata

    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode
    private let versionMetadataProvider: VersionMetadataProvider

    package init(
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        versionMetadataProvider: @escaping VersionMetadataProvider
    ) {
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.versionMetadataProvider = versionMetadataProvider
    }

    // MARK: - source archive
    package func validateSourceArchive(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.validateSourceArchive(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                timeout: timeout,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                completion: {
                    continuation.resume(with: $0)
                }
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
        if let savedChecksum = try? self.readFromStorage(package: package, version: version, contentType: .sourceCode, observabilityScope: observabilityScope) {
            return completion(.success(savedChecksum))
        }

        // Try fetching checksum from registry if:
        //   - No storage available
        //   - Checksum not found in storage
        //   - Reading from storage resulted in error
        Task {
            do {
                let versionMetadata = try await self.versionMetadataProvider(package, version)
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
                do {
                    try self.writeToStorage(
                        registry: registry,
                        package: package,
                        version: version,
                        checksum: checksum,
                        contentType: .sourceCode,
                        observabilityScope: observabilityScope
                    )
                    completion(.success(checksum))
                } catch {
                    completion(.failure(error))
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

    @available(*, noasync, message: "Use the async alternative")
    package func validateManifest(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        toolsVersion: ToolsVersion?,
        checksum: String,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) throws {
        let contentType = Fingerprint.ContentType.manifest(toolsVersion)

        guard let expectedChecksum = try? self.readFromStorage(
            package: package,
            version: version,
            contentType: .manifest(toolsVersion),
            observabilityScope: observabilityScope
        ) else {
            return try self.writeToStorage(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                contentType: .manifest(toolsVersion),
                observabilityScope: observabilityScope
            )
        }
        // Previously recorded checksum
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
    }

    // MARK: - storage helpers

    private func readFromStorage(
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope
    ) throws -> String? {
        guard let fingerprintStorage else {
            return nil
        }

        do {
            return try fingerprintStorage.get(
                package: package.underlying,
                version: version,
                kind: .registry,
                contentType: contentType,
                observabilityScope: observabilityScope
            ).value
        } catch PackageFingerprintStorageError.notFound {
            return nil
        } catch {
            observabilityScope
                .emit(
                    error: "failed to get registry fingerprint for \(contentType) of \(package) \(version) from storage",
                    underlyingError: error
                )
            throw error
        }
    }

    private func writeToStorage(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        contentType: Fingerprint.ContentType,
        observabilityScope: ObservabilityScope
    ) throws {
        guard let fingerprintStorage else {
            return
        }

        let fingerprint = Fingerprint(origin: .registry(registry.url), value: checksum, contentType: contentType)
        do {
            try fingerprintStorage.put(
                package: package.underlying,
                version: version,
                fingerprint: fingerprint,
                observabilityScope: observabilityScope
            )
        } catch PackageFingerprintStorageError.conflict(_, let existing){
            switch self.fingerprintCheckingMode {
            case .strict:
                throw RegistryError.checksumChanged(latest: checksum, previous: existing.value)
            case .warn:
                observabilityScope
                    .emit(
                        warning: "the checksum \(checksum) for \(contentType) of \(package) \(version) from \(registry.url.absoluteString) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))"
                    )
            }
        }
    }
}
