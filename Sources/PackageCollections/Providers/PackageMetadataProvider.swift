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
package protocol PackageMetadataProvider {

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
    package struct PackageBasicMetadata: Equatable, Codable {
        package let summary: String?
        package let keywords: [String]?
        package let versions: [PackageBasicVersionMetadata]
        package let watchersCount: Int?
        package let readmeURL: URL?
        package let license: PackageCollectionsModel.License?
        package let authors: [PackageCollectionsModel.Package.Author]?
        package let languages: Set<String>?

        package init(
            summary: String?,
            keywords: [String]?,
            versions: [PackageBasicVersionMetadata],
            watchersCount: Int?,
            readmeURL: URL?,
            license: PackageCollectionsModel.License?,
            authors: [PackageCollectionsModel.Package.Author]?,
            languages: Set<String>?
        ) {
            self.summary = summary
            self.keywords = keywords
            self.versions = versions
            self.watchersCount = watchersCount
            self.readmeURL = readmeURL
            self.license = license
            self.authors = authors
            self.languages = languages
        }
    }

    package struct PackageBasicVersionMetadata: Equatable, Codable {
        package let version: TSCUtility.Version
        package let title: String?
        package let summary: String?
        package let author: PackageCollectionsModel.Package.Author?
        package let createdAt: Date?

        package init(
            version: TSCUtility.Version,
            title: String?,
            summary: String?,
            author: PackageCollectionsModel.Package.Author?,
            createdAt: Date?
        ) {
            self.version = version
            self.title = title
            self.summary = summary
            self.author = author
            self.createdAt = createdAt
        }
    }
}

public struct PackageMetadataProviderContext: Equatable {
    public let name: String
    public let authTokenType: AuthTokenType?
    public let isAuthTokenConfigured: Bool
    public let error: PackageMetadataProviderError?

    package init(
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
