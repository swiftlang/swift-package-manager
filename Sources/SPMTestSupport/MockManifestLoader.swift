/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import TSCBasic
import PackageModel
import PackageLoading
import PackageGraph
import TSCUtility

public enum MockManifestLoaderError: Swift.Error {
    case unknownRequest(String)
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
public final class MockManifestLoader: ManifestLoaderProtocol {
    public struct Key: Hashable {
        public let url: String
        public let version: Version?

        public init(url: String, version: Version? = nil) {
            self.url = url
            self.version = version
        }
    }

    public var manifests: [Key: Manifest]

    public init(manifests: [Key: Manifest]) {
        self.manifests = manifests
    }

    public func load(
        packagePath path: TSCBasic.AbsolutePath,
        baseURL: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        fileSystem: FileSystem?,
        diagnostics: DiagnosticsEngine?
    ) throws -> PackageModel.Manifest {
        let key = Key(url: baseURL, version: version)
        if let result = manifests[key] {
            return result
        }
        throw MockManifestLoaderError.unknownRequest("\(key)")
    }
}
