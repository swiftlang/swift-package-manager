/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic
import TSCUtility

extension Configuration {
    public struct Netrc {
        private let fileSystem: FileSystem
        private let path: AbsolutePath?

        public init(fileSystem: FileSystem, path: AbsolutePath? = nil) {
            self.fileSystem = fileSystem
            self.path = path
        }

        public struct Settings: AuthorizationProviding {
            private let underlying: TSCUtility.Netrc?

            fileprivate init(_ underlying: TSCUtility.Netrc?) {
                self.underlying = underlying
            }

            public var machines: [TSCUtility.Netrc.Machine] {
                get {
                    self.underlying?.machines ?? []
                }
            }
            /// Basic authorization header string
            /// - Parameter url: URI of network resource to be accessed
            /// - Returns: (optional) Basic Authorization header string to be added to the request
            public func authorization(for url: Foundation.URL) -> String? {
                return self.underlying?.authorization(for: url)
            }
        }
    }
}

extension Configuration.Netrc {
    public func settings() throws -> Settings {
        guard let path = self.path, self.fileSystem.exists(path) else {
            return Settings(nil)
        }
        return try Settings.load(path, fileSystem: self.fileSystem)
    }
}

extension Configuration.Netrc.Settings {
    // FIXME: change TSC to take file system as well
    static func load(_ path: AbsolutePath, fileSystem: FileSystem) throws -> Self {
        return try .init(TSCUtility.Netrc.load(fromFileAtPath: path).get())
    }
}
