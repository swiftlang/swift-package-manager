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

extension PackageCollectionsModel {
    /// A representation of paginated list of packages.
    public struct PaginatedPackageList {
        /// List of packages
        public let items: [PackageCollectionsModel.Package]

        /// Offset of the first item in the result
        public let offset: Int
        
        /// The requested page size
        public let limit: Int
        
        /// Total number of packages
        public let total: Int
    }
}
