/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

extension Configuration {
    public struct Resolution {
        public var repositories: Repositories
        public var prefetchingEnabled: Bool
        public var tracingEnabled: Bool
        public var skipUpdate: Bool

        public init(
            repositories: Repositories,
            prefetchingEnabled: Bool? = .none,
            tracingEnabled: Bool? = .none,
            skipUpdate: Bool? = .none
        ) {
            self.repositories = repositories
            self.prefetchingEnabled = prefetchingEnabled ?? false
            self.tracingEnabled = tracingEnabled ?? false
            self.skipUpdate = skipUpdate ?? false
        }
    }
}

extension Configuration.Resolution {
    public struct Repositories {
        public var cachePath: AbsolutePath?

        public init(cachePath: AbsolutePath?) {
            self.cachePath = cachePath
        }

        public static func cachePath(rootCachePath: AbsolutePath) -> AbsolutePath {
            return rootCachePath.appending(component: "repositories")
        }
    }
}
