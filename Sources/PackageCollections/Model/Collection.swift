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
import SourceControl
import TSCUtility

public enum PackageCollectionsModel {}

// make things less verbose internally
internal typealias Model = PackageCollectionsModel

extension PackageCollectionsModel {
    /// A `Collection` is a collection of packages.
    public struct Collection: Equatable, Codable {
        public typealias Identifier = CollectionIdentifier
        public typealias Source = CollectionSource

        /// The identifier of the collection
        public let identifier: Identifier

        /// Where the collection and its contents are obtained
        public let source: Source

        /// The name of the collection
        public let name: String

        /// The description of the collection
        public let overview: String?

        /// Keywords for the collection
        public let keywords: [String]?

        /// Metadata of packages belonging to the collection
        public let packages: [Package]

        /// When this collection was created/published by the source
        public let createdAt: Date

        /// Who authored this collection
        public let createdBy: Author?

        /// When this collection was last processed locally
        public let lastProcessedAt: Date

        /// Initializes a `Collection`
        init(
            source: Source,
            name: String,
            overview: String?,
            keywords: [String]?,
            packages: [Package],
            createdAt: Date,
            createdBy: Author?,
            lastProcessedAt: Date = Date()
        ) {
            self.identifier = .init(from: source)
            self.source = source
            self.name = name
            self.overview = overview
            self.keywords = keywords
            self.packages = packages
            self.createdAt = createdAt
            self.createdBy = createdBy
            self.lastProcessedAt = lastProcessedAt
        }
    }
}

extension PackageCollectionsModel {
    /// Represents the source of a `Collection`
    public struct CollectionSource: Equatable, Hashable, Codable {
        /// Source type
        public let type: CollectionSourceType

        /// URL of the source file
        public let url: URL

        public init(type: CollectionSourceType, url: URL) {
            self.type = type
            self.url = url
        }
    }

    /// Represents the source type of a `Collection`
    public enum CollectionSourceType: String, Codable, CaseIterable {
        case json
    }
}

extension PackageCollectionsModel {
    /// Represents the identifier of a `Collection`
    public enum CollectionIdentifier: Hashable, Comparable {
        /// JSON based package collection at URL
        case json(URL)

        /// Creates an `Identifier` from `Source`
        init(from source: CollectionSource) {
            switch source.type {
            case .json:
                self = .json(source.url)
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.json(let lhs), .json(let rhs)):
                return lhs.absoluteString < rhs.absoluteString
            }
        }
    }
}

extension PackageCollectionsModel.CollectionIdentifier: Codable {
    public enum DiscriminatorKeys: String, Codable {
        case json
    }

    public enum CodingKeys: CodingKey {
        case _case
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: ._case) {
        case .json:
            let url = try container.decode(URL.self, forKey: .url)
            self = .json(url)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .json(let url):
            try container.encode(DiscriminatorKeys.json, forKey: ._case)
            try container.encode(url, forKey: .url)
        }
    }
}

extension PackageCollectionsModel.Collection {
    /// Represents the author of a `Collection`
    public struct Author: Equatable, Codable {
        /// The name of the author
        public let name: String
    }
}
