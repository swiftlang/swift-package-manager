/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

extension Configuration {
    public struct ManifestsLoading {
        public var cachePath: AbsolutePath?
        public var serializedDiagnostics: Bool
        public var isManifestSandboxEnabled: Bool

        public init(cachePath: AbsolutePath?,
                    serializedDiagnostics: Bool? = .none,
                    isManifestSandboxEnabled: Bool? = .none
        ) {
            self.cachePath = cachePath
            self.serializedDiagnostics = serializedDiagnostics ?? false
            self.isManifestSandboxEnabled = isManifestSandboxEnabled ?? true
        }

        public static func cachePath(rootCachePath: AbsolutePath) -> AbsolutePath {
            return rootCachePath.appending(component: "manifests")
        }
    }
}
