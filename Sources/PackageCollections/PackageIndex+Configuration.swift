/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

public struct PackageIndexConfiguration: Equatable {
    public var url: Foundation.URL?
    public var searchResultMaxItemsCount: UInt = 50
    
    // TODO: rdar://87575573 remove feature flag
    public internal(set) var enabled = ProcessInfo.processInfo.environment["SWIFTPM_ENABLE_PACKAGE_INDEX"] == "1"
    
    public init() {
        self.url = nil
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
        let buffer = try self.fileSystem.readFileContents(self.path).contents
        guard buffer.count > 0 else {
            return .init()
        }
        let container = try decoder.decode(StorageModel.Container.self, from: Data(buffer))
        return try PackageIndexConfiguration(container.index)
    }

    public func save(_ configuration: PackageIndexConfiguration) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        let container = StorageModel.Container(configuration)
        let buffer = try encoder.encode(container)
        try self.fileSystem.writeFileContents(self.path, bytes: ByteString(buffer), atomically: true)
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
                searchResultMaxItemsCount: from.searchResultMaxItemsCount
            )
        }
    }

    struct Index: Codable {
        let url: String?
        let searchResultMaxItemsCount: UInt
    }
}

// MARK: - Utility

private extension PackageIndexConfiguration {
    init(_ from: StorageModel.Index) throws {
        switch from.url {
        case .none:
            self.url = nil
        case .some(let urlString):
            guard let url = URL(string: urlString) else {
                throw SerializationError.invalidURL(urlString)
            }
            self.url = url
        }
        self.searchResultMaxItemsCount = from.searchResultMaxItemsCount
    }
}

private enum SerializationError: Error {
    case invalidURL(String)
}
