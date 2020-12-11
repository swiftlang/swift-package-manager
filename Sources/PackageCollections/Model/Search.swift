/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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
            public let collections: [PackageCollectionsModel.CollectionIdentifier]
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
