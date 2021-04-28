/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

// TODO: how do we read default config values? ENV variables? user settings?
extension PackageCollections {
    public struct Configuration {
        // TODO: add configuration including:
        // JSONPackageCollectionProvider: maximumSizeInBytes
        // JSONPackageCollectionValidator: maximumPackageCount, maximumMajorVersionCount, maximumMinorVersionCount

        /// Auth tokens for the collections or metadata provider
        public var authTokens: () -> [AuthTokenType: String]?

        public init(authTokens: @escaping () -> [AuthTokenType: String]? = { nil }) {
            self.authTokens = authTokens
        }
    }
}

public enum AuthTokenType: Hashable {
    case github(_ host: String)
}
