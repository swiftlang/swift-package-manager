//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
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

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import protocol TSCBasic.HashAlgorithm

// MARK: - Registry downloads manager

public struct RegistryDownloads {
    /// Additional information about a fetch
    public struct FetchDetails: Equatable {
        /// Indicates if the repository was fetched from the cache or from the remote.
        public let fromCache: Bool
        /// Indicates wether the wether the repository was already present in the cache and updated or if a clean fetch was performed.
        public let updatedCache: Bool

        public init(fromCache: Bool, updatedCache: Bool) {
            self.fromCache = fromCache
            self.updatedCache = updatedCache
        }
    }
}

/// Delegate to notify clients about actions being performed by RegistryManager.
public protocol RegistryDownloadsManagerDelegate {
    /// Called when a package is about to be fetched.
    func willFetch(package: PackageIdentity, version: Version, fetchDetails: RegistryDownloads.FetchDetails)

    /// Called when a package has finished fetching.
    func didFetch(package: PackageIdentity, version: Version, result: Result<RegistryDownloads.FetchDetails, Error>, duration: DispatchTimeInterval)

    /// Called every time the progress of a repository fetch operation updates.
    func fetching(package: PackageIdentity, version: Version, bytesDownloaded: Int64, totalBytesToDownload: Int64?)
}

public protocol RegistryDownloadsManagerInterface {
    func lookup(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping  (Result<AbsolutePath, Error>) -> Void
    )

    func purgeCache() throws
    func remove(package: PackageIdentity) throws
    func reset() throws
}

// MARK: - Registry client

public struct RegistryPackageMetadata {
    public let versions: [Version]
    public let alternateLocations: [URL]?

    public init(versions: [Version], alternateLocations: [URL]?) {
        self.versions = versions
        self.alternateLocations = alternateLocations
    }
}

public protocol RegistryClientInterface {
    var configured: Bool { get }

    func cancel(deadline: DispatchTime) throws

    func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        checksumAlgorithm: HashAlgorithm, // the same algorithm used by `package compute-checksum` tool
        progressHandler: ((_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void)?,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func getAvailableManifests(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<[String: (toolsVersion: ToolsVersion, content: String?)], Error>) -> Void
    )

    func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String, Error>) -> Void
    )

    func getPackageMetadata(
        package: PackageIdentity,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<RegistryPackageMetadata, Error>) -> Void
    )

    func lookupIdentities(
        url: URL,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Set<PackageIdentity>, Error>) -> Void
    )
}

public extension RegistryClientInterface {
    func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        checksumAlgorithm: HashAlgorithm, // the same algorithm used by `package compute-checksum` tool
        progressHandler: ((_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void)?,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.downloadSourceArchive(package: package,
                                   version: version,
                                   fileSystem: fileSystem,
                                   destinationPath: destinationPath,
                                   checksumAlgorithm: checksumAlgorithm,
                                   progressHandler: progressHandler,
                                   timeout: .none,
                                   observabilityScope: observabilityScope,
                                   callbackQueue: callbackQueue,
                                   completion: completion)
    }

    func getAvailableManifests(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<[String: (toolsVersion: ToolsVersion, content: String?)], Error>) -> Void
    ) {
        self.getAvailableManifests(package: package,
                                   version: version,
                                   timeout: .none,
                                   observabilityScope: observabilityScope,
                                   callbackQueue: callbackQueue,
                                   completion: completion)
    }

    func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.getManifestContent(package: package,
                                version: version,
                                customToolsVersion: customToolsVersion,
                                timeout: .none,
                                observabilityScope: observabilityScope,
                                callbackQueue: callbackQueue,
                                completion: completion)
    }

    func getPackageMetadata(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<RegistryPackageMetadata, Error>) -> Void
    ) {
        self.getPackageMetadata(
            package: package,
            timeout: .none,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            completion: completion)
    }

    func lookupIdentities(
        url: URL,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Set<PackageIdentity>, Error>) -> Void
    ) {
        self.lookupIdentities(url: url,
                              timeout: .none,
                              observabilityScope: observabilityScope,
                              callbackQueue: callbackQueue,
                              completion: completion)
    }
}
