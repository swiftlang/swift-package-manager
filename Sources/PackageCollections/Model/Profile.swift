/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension PackageCollectionsModel {
    /// A `PackageGroupProfile` is a grouping of `PackageGroup`s.
    public struct Profile: Hashable {
        /// The default profile; this should be used when a profile is required but not specified.
        public static let `default` = Profile(name: "default")

        /// Profile name
        public let name: String
    }
}
