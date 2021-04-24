/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL

import PackageModel
import TSCBasic
import TSCUtility

/// `PackageBasicMetadata` provider
protocol PackageMetadataProvider: Closable {
    /// The name of the provider
    var name: String { get }

    /// Retrieves metadata for a package at the given repository address.
    ///
    /// - Parameters:
    ///   - reference: The package's reference
    ///   - callback: The closure to invoke when result becomes available
    func get(_ reference: PackageReference, callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>) -> Void)
}

extension Model {
    struct PackageBasicMetadata: Equatable, Codable {
        let summary: String?
        let keywords: [String]?
        let versions: [PackageBasicVersionMetadata]
        let watchersCount: Int?
        let readmeURL: Foundation.URL?
        let license: PackageCollectionsModel.License?
        let authors: [PackageCollectionsModel.Package.Author]?
        let languages: Set<String>?
        let processedAt: Date
    }

    struct PackageBasicVersionMetadata: Equatable, Codable {
        let version: TSCUtility.Version
        let title: String?
        let summary: String?
        let createdAt: Date
        let publishedAt: Date?
    }
}
