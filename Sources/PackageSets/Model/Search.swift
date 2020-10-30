/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension PackageSetsModel {
    /// Represents a search query
    public enum SearchQuery {
        /// String search
        case string(String)

        // Can support more advanced queries in the future
    }

    /// A representation of package in search result
    public struct PackageSearchResult {
        /// Result items of the search
        public let items: [Item]

        /// Represents a search result item
        public struct Item {
            // Merged package metadata from across groups
            /// The matching package
            public let package: PackageSetsModel.Package

            /// Package sets that contain the package
            public let sets: [PackageSetsModel.PackageSetIdentifier]
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
        public let items: [Item]

        public typealias Item = Target
    }
}
