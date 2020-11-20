/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL
import PackageModel
import TSCUtility

/// `PackageBasicMetadata` provider
protocol PackageMetadataProvider {
    /// Retrieves metadata for a package at the given repository address.
    ///
    /// - Parameters:
    ///   - reference: The package's reference
    ///   - callback: The closure to invoke when result becomes available
    func get(_ reference: PackageReference, callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>) -> Void)
}

extension Model {
    struct PackageBasicMetadata: Equatable {
        let summary: String?
        let keywords: [String]?
        let versions: [TSCUtility.Version]
        let watchersCount: Int?
        let readmeURL: Foundation.URL?
        let authors: [PackageCollectionsModel.Package.Author]?
        let processedAt: Date
    }
}
