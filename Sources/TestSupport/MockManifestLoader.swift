/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import Basic
import PackageModel
import PackageLoading
import Utility

public enum MockManifestLoaderError: Swift.Error {
    case unknownRequest
}

/// A mock manifest loader implementation.
///
/// This implementation takes a canned set of manifests for known URLs and
/// versions and exposes them via the `ManifestLoaderProtocol`, for use in
/// testing higher-level clients which use manifests, but don't require testing
/// the loading logic itself.
///
/// This implementation will throw an error if a request to load an unknown
/// manifest is made.
public struct MockManifestLoader: ManifestLoaderProtocol {
    public struct Key: Hashable {
        public let url: String
        public let version: Version?

        public init(url: String, version: Version?) {
            self.url = url
            self.version = version
        }

        public var hashValue: Int {
            return url.hashValue ^ (version?.hashValue ?? 0)
        }
    }

    public let manifests: [Key: Manifest]

    public init(manifests: [Key: Manifest]) {
        self.manifests = manifests
    }

    public func load(
        packagePath path: Basic.AbsolutePath,
        baseURL: String,
        version: PackageDescription.Version?,
        fileSystem: FileSystem?
    ) throws -> PackageModel.Manifest {
        if let result = manifests[Key(url: baseURL, version: version)] {
            return result
        }
        throw MockManifestLoaderError.unknownRequest
    }
}
public func ==(lhs: MockManifestLoader.Key, rhs: MockManifestLoader.Key) -> Bool {
    return lhs.url == rhs.url && lhs.version == rhs.version
}
