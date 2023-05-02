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

import Basics

// TODO: how do we read default config values? ENV variables? user settings?
extension PackageCollections {
    public struct Configuration {
        // TODO: add configuration including:
        // JSONPackageCollectionProvider: maximumSizeInBytes
        // JSONPackageCollectionValidator: maximumPackageCount, maximumMajorVersionCount, maximumMinorVersionCount
        
        /// Path of the parent directory for collections-related configuration files
        public var configurationDirectory: AbsolutePath?
        
        /// Path of the parent directory for collections-related cache(s)
        public var cacheDirectory: AbsolutePath?

        /// Auth tokens for the collections or metadata provider
        public var authTokens: () -> [AuthTokenType: String]?

        public init(
            configurationDirectory: AbsolutePath? = nil,
            cacheDirectory: AbsolutePath? = nil,
            authTokens: @escaping () -> [AuthTokenType: String]? = { nil }
        ) {
            self.authTokens = authTokens
        }
    }
}

public enum AuthTokenType: Hashable {
    case github(_ host: String)
}
