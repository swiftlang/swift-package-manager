/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Dispatch
import PackageModel
import PackageLoading
import PackageGraph
import TSCBasic
import TSCUtility
import func XCTest.XCTFail

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

    public let manifests: ThreadSafeKeyValueStore<Key, Manifest>

    public init(manifests: [Key: Manifest]) {
        self.manifests = ThreadSafeKeyValueStore<Key, Manifest>(manifests)
    }

    public func load(
        at path: TSCBasic.AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        queue.async {
            let key = Key(url: packageLocation, version: version)
            if let result = self.manifests[key] {
                return completion(.success(result))
            } else {
                return completion(.failure(MockManifestLoaderError.unknownRequest("\(key)")))
            }
        }
    }

    public func resetCache() throws {}
    public func purgeCache() throws {}
}

extension ManifestLoader {
    public func load(
        at path: TSCBasic.AbsolutePath,
        packageKind: PackageModel.PackageReference.Kind,
        toolsVersion: PackageModel.ToolsVersion,
        identityResolver: IdentityResolver = DefaultIdentityResolver(),
        fileSystem: TSCBasic.FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> Manifest{
        let packageIdentity: PackageIdentity
        let packageLocation: String
        switch packageKind {
        case .root(let path):
            packageIdentity = try identityResolver.resolveIdentity(for: path)
            packageLocation = path.pathString
        case .fileSystem(let path):
            packageIdentity = try identityResolver.resolveIdentity(for: path)
            packageLocation = path.pathString
        case .localSourceControl(let path):
            packageIdentity = try identityResolver.resolveIdentity(for: path)
            packageLocation = path.pathString
        case .remoteSourceControl(let url):
            packageIdentity = try identityResolver.resolveIdentity(for: url)
            packageLocation = url.absoluteString
        case .registry(let identity):
            packageIdentity = identity
            // FIXME: placeholder
            packageLocation = identity.description
        }
        return try tsc_await {
            self.load(
                at: path,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                version: nil,
                revision: nil,
                toolsVersion: toolsVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                on: .sharedConcurrent,
                completion: $0
            )
        }
    }
}
