/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import Foundation
import PackageModel
import TSCBasic

struct PackageIndex: PackageIndexProtocol {
    private let configuration: PackageIndexConfiguration
    private let httpClient: HTTPClient
    private let callbackQueue: DispatchQueue
    private let observabilityScope: ObservabilityScope

    // TODO: cache metadata results
    
    var isEnabled: Bool {
        self.configuration.enabled && self.configuration.url != .none
    }

    init(
        configuration: PackageIndexConfiguration,
        customHTTPClient: HTTPClient? = nil,
        callbackQueue: DispatchQueue,
        observabilityScope: ObservabilityScope
    ) {
        self.configuration = configuration
        self.httpClient = customHTTPClient ?? HTTPClient()
        self.callbackQueue = callbackQueue
        self.observabilityScope = observabilityScope
    }

    func getPackageMetadata(
        identity: PackageIdentity,
        location: String?,
        callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void
    ) {
        self.runIfConfigured(callback: callback) { _, _ in
            // TODO: call package index's get metadata API
            fatalError("Not implemented: \(#function)")
        }
    }
    
    func findPackages(
        _ query: String,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.runIfConfigured(callback: callback) { _, _ in
            // TODO: call package index's search API
            fatalError("Not implemented: \(#function)")
        }
    }

    func listPackages(
        offset: Int,
        limit: Int,
        callback: @escaping (Result<PackageCollectionsModel.PaginatedPackageList, Error>) -> Void
    ) {
        self.runIfConfigured(callback: callback) { _, _ in
            // TODO: cap `limit`
            // TODO: call package index's list API
            fatalError("Not implemented: \(#function)")
        }
    }

    private func runIfConfigured<T>(
        callback: @escaping (Result<T, Error>) -> Void,
        closure: @escaping (Foundation.URL, (Result<T, Error>) -> Void) -> Void
    ) {
        let callback = self.makeAsync(callback)
        
        guard self.configuration.enabled else {
            return callback(.failure(PackageIndexError.featureDisabled))
        }
        guard let url = self.configuration.url else {
            return callback(.failure(PackageIndexError.notConfigured))
        }

        closure(url, callback)
    }

    private func makeAsync<T>(_ closure: @escaping (Result<T, Error>) -> Void) -> (Result<T, Error>) -> Void {
        { result in self.callbackQueue.async { closure(result) } }
    }
}

// MARK: - PackageMetadataProvider conformance

extension PackageIndex: PackageMetadataProvider {
    func get(
        identity: PackageIdentity,
        location: String,
        callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>, PackageMetadataProviderContext?) -> Void
    ) {
        self.getPackageMetadata(identity: identity, location: location) { result in
            switch result {
            case .failure(let error):
                // Package index fails to produce result so it cannot be the provider
                callback(.failure(error), nil)
            case .success(let metadata):
                let package = metadata.package
                let basicMetadata = PackageCollectionsModel.PackageBasicMetadata(
                    summary: package.summary,
                    keywords: package.keywords,
                    versions: package.versions.map { version in
                        PackageCollectionsModel.PackageBasicVersionMetadata(
                            version: version.version,
                            title: version.title,
                            summary: version.summary,
                            createdAt: version.createdAt
                        )
                    },
                    watchersCount: package.watchersCount,
                    readmeURL: package.readmeURL,
                    license: package.license,
                    authors: package.authors,
                    languages: package.languages
                )

                let name = self.configuration.url?.host ?? "package index"
                let context = PackageMetadataProviderContext(
                    name: name,
                    // Package index doesn't require auth
                    authTokenType: nil,
                    isAuthTokenConfigured: true
                )
                
                callback(.success(basicMetadata), context)
            }
        }
    }
}
