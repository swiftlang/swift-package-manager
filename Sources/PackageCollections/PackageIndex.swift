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
    private let configurationStorage: PackageIndexConfigurationStorage
    private let httpClient: HTTPClient
    private let callbackQueue: DispatchQueue
    private let observabilityScope: ObservabilityScope
    
    // Feature flag: env var SWIFTPM_ENABLE_PACKAGE_INDEX
    let enabled: Bool

    // TODO: cache metadata results

    init(
        fileSystem: FileSystem,
        customHTTPClient: HTTPClient? = nil,
        callbackQueue: DispatchQueue,
        observabilityScope: ObservabilityScope
    ) {
        self.configurationStorage = PackageIndexConfigurationStorage(fileSystem: fileSystem)
        self.httpClient = customHTTPClient ?? HTTPClient()
        self.callbackQueue = callbackQueue
        self.observabilityScope = observabilityScope
        self.enabled = ProcessInfo.processInfo.environment["SWIFTPM_ENABLE_PACKAGE_INDEX"] == "1"
    }

    func set(
        url: Foundation.URL,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let callback = self.makeAsync(callback)
        
        guard self.enabled else {
            return callback(.failure(PackageIndexError.featureDisabled))
        }
        
        self.configurationStorage.update(index: .init(url: url)) { result in
            callback(result.tryMap { () })
        }
    }

    func unset(callback: @escaping (Result<Void, Error>) -> Void) {
        let callback = self.makeAsync(callback)
        
        guard self.enabled else {
            return callback(.failure(PackageIndexError.featureDisabled))
        }
        
        self.configurationStorage.update(index: .init(url: nil)) { result in
            callback(result.tryMap { () })
        }
    }

    func get(callback: @escaping (Result<Foundation.URL?, Error>) -> Void) {
        let callback = self.makeAsync(callback)
        
        guard self.enabled else {
            return callback(.failure(PackageIndexError.featureDisabled))
        }
        
        self.configurationStorage.get { result in
            callback(result.tryMap { $0.url })
        }
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
        
        guard self.enabled else {
            return callback(.failure(PackageIndexError.featureDisabled))
        }
        
        self.get { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(.none):
                callback(.failure(PackageIndexError.notConfigured))
            case .success(.some(let url)):
                closure(url, callback)
            }
        }
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
                
                let url = try? temp_await { callback in self.get(callback: callback) }
                let name = url?.host ?? "package index"
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
