//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

public struct PackageIndexConfiguration: Equatable {
    public var url: URL?
    public var searchResultMaxItemsCount: Int
    public var cacheDirectory: AbsolutePath
    public var cacheTTLInSeconds: Int
    public var cacheMaxSizeInMegabytes: Int
    
    // TODO: rdar://87575573 remove feature flag
    public internal(set) var enabled = ProcessInfo.processInfo.environment["SWIFTPM_ENABLE_PACKAGE_INDEX"] == "1"
    
    public init(
        url: URL? = nil,
        searchResultMaxItemsCount: Int? = nil,
        disableCache: Bool = false,
        cacheDirectory: AbsolutePath? = nil,
        cacheTTLInSeconds: Int? = nil,
        cacheMaxSizeInMegabytes: Int? = nil
    ) {
        self.url = url
        self.searchResultMaxItemsCount = searchResultMaxItemsCount ?? 50
        self.cacheDirectory = (try? cacheDirectory.map(resolveSymlinks)) ?? (try? localFileSystem.swiftPMCacheDirectory.appending(components: "package-metadata")) ?? .root
        self.cacheTTLInSeconds = disableCache ? -1 : (cacheTTLInSeconds ?? 3600)
        self.cacheMaxSizeInMegabytes = cacheMaxSizeInMegabytes ?? 10
    }
}

public struct PackageIndexConfigurationStorage {
    private let path: AbsolutePath
    private let fileSystem: FileSystem

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: AbsolutePath, fileSystem: FileSystem) {
        self.path = path
        self.fileSystem = fileSystem
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }
    
    public func load() throws -> PackageIndexConfiguration {
        guard self.fileSystem.exists(self.path) else {
            return .init()
        }
        let data: Data = try self.fileSystem.readFileContents(self.path)
        guard data.count > 0 else {
            return .init()
        }
        let container = try decoder.decode(StorageModel.Container.self, from: data)
        return try PackageIndexConfiguration(container.index)
    }

    public func save(_ configuration: PackageIndexConfiguration) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        let container = StorageModel.Container(configuration)
        let buffer = try encoder.encode(container)
        try self.fileSystem.writeFileContents(self.path, data: buffer)
    }
    
    @discardableResult
    public func update(with handler: (inout PackageIndexConfiguration) throws -> Void) throws -> PackageIndexConfiguration {
        let configuration = try self.load()
        var updatedConfiguration = configuration
        try handler(&updatedConfiguration)
        if updatedConfiguration != configuration {
            try self.save(updatedConfiguration)
        }
        return updatedConfiguration
    }
}

private enum StorageModel {
    struct Container: Codable {
        var index: Index

        init(_ from: PackageIndexConfiguration) {
            self.index = .init(
                url: from.url?.absoluteString,
                searchResultMaxItemsCount: from.searchResultMaxItemsCount,
                cacheDirectory: from.cacheDirectory.pathString,
                cacheTTLInSeconds: from.cacheTTLInSeconds,
                cacheMaxSizeInMegabytes: from.cacheMaxSizeInMegabytes
            )
        }
    }

    struct Index: Codable {
        let url: String?
        let searchResultMaxItemsCount: Int?
        let cacheDirectory: String?
        let cacheTTLInSeconds: Int?
        let cacheMaxSizeInMegabytes: Int?
    }
}

// MARK: - Utility

private extension PackageIndexConfiguration {
    init(_ from: StorageModel.Index) throws {
        let url: URL?
        switch from.url {
        case .none:
            url = nil
        case .some(let urlString):
            url = URL(string: urlString)
            guard url != nil else {
                throw SerializationError.invalidURL(urlString)
            }
        }
        
        let cacheDirectory: AbsolutePath?
        switch from.cacheDirectory {
        case .none:
            cacheDirectory = nil
        case .some(let path):
            cacheDirectory = try? AbsolutePath(validating: path)
            guard cacheDirectory != nil else {
                throw SerializationError.invalidPath(path)
            }
        }

        self.init(
            url: url,
            searchResultMaxItemsCount: from.searchResultMaxItemsCount,
            cacheDirectory: cacheDirectory,
            cacheTTLInSeconds: from.cacheTTLInSeconds,
            cacheMaxSizeInMegabytes: from.cacheMaxSizeInMegabytes
        )
    }
}

private enum SerializationError: Error {
    case invalidURL(String)
    case invalidPath(String)
}
