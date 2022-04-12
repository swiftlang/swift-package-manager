//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

extension PackageCollectionsModel {
    /// A representation of package in search result
    public struct PackageSearchResult {
        /// Result items of the search
        public let items: [Item]

        /// Represents a search result item
        public struct Item: Encodable {
            // Merged package metadata from across collections
            /// The matching package
            public let package: PackageCollectionsModel.Package

            /// Package collections that contain the package
            public internal(set) var collections: [PackageCollectionsModel.CollectionIdentifier]
            
            /// Package indexes that contain the package
            public internal(set) var indexes: [URL]
            
            init(
                package: PackageCollectionsModel.Package,
                collections: [PackageCollectionsModel.CollectionIdentifier] = [],
                indexes: [URL] = []
            ) {
                self.package = package
                self.collections = collections
                self.indexes = indexes
            }
        }
    }

    /// An enum of target search types
    public enum TargetSearchType {
        case prefix
        case exactMatch
    }

    /// A representation of target in search result
    public struct TargetSearchResult {
        /// Result items of the search
        public let items: [TargetListItem]
    }
}
