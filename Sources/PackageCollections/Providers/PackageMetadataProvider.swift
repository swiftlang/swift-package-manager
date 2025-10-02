//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Date
import struct Foundation.URL

import PackageModel

import struct TSCUtility.Version

/// `PackageBasicMetadata` provider
protocol PackageMetadataProvider {

    // TODO: Review if this API is correct
    // This API is awkward because it unconditionally provides a context
    // Does it make sense to have a context if you don't have metadata?
    // The only use of provider on failure is PackageCollections.getPackageMetadata
    // It would be nice to change the API to
    // async throw -> (PackageCollectionsModel.PackageBasicMetadata, PackageMetadataProviderContext?)
    // or even
    // async throw -> (PackageCollectionsModel.PackageBasicMetadata, PackageMetadataProviderContext)

    /// Retrieves metadata for a package with the given identity and repository address.
    ///
    /// - Parameters:
    ///   - identity: The package's identity
    ///   - location: The package's location
    func get(
        identity: PackageIdentity,
        location: String
    ) async -> (Result<PackageCollectionsModel.PackageBasicMetadata, Error>, PackageMetadataProviderContext?)
}

extension Model {
    struct PackageBasicMetadata: Equatable, Codable {
        let summary: String?
        let keywords: [String]?
        let versions: [PackageBasicVersionMetadata]
        let watchersCount: Int?
        let readmeURL: URL?
        let license: PackageCollectionsModel.License?
        let authors: [PackageCollectionsModel.Package.Author]?
        let languages: Set<String>?
    }

    struct PackageBasicVersionMetadata: Equatable, Codable {
        let version: TSCUtility.Version
        let title: String?
        let summary: String?
        let author: PackageCollectionsModel.Package.Author?
        let createdAt: Date?
    }
}

public struct PackageMetadataProviderContext: Equatable {
    public let name: String
    public let authTokenType: AuthTokenType?
    public let isAuthTokenConfigured: Bool
    public let error: PackageMetadataProviderError?

    init(
        name: String,
        authTokenType: AuthTokenType?,
        isAuthTokenConfigured: Bool,
        error: PackageMetadataProviderError? = nil
    ) {
        self.name = name
        self.authTokenType = authTokenType
        self.isAuthTokenConfigured = isAuthTokenConfigured
        self.error = error
    }
}

public enum PackageMetadataProviderError: Error, Equatable {
    case invalidResponse(errorMessage: String)
    case permissionDenied
    case invalidAuthToken
    case apiLimitsExceeded
}
