/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

struct PackageIndexConfiguration {
    var url: Foundation.URL?
}

struct PackageIndexConfigurationStorage {
    let fileSystem: FileSystem
    let path: AbsolutePath

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileSystem: FileSystem = localFileSystem, path: AbsolutePath? = nil) {
        self.fileSystem = fileSystem

        self.path = path ?? fileSystem.swiftPMConfigurationDirectory.appending(component: "index.json")
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    func get(callback: @escaping (Result<PackageIndexConfiguration, Error>) -> Void) {
        DispatchQueue.sharedConcurrent.async {
            do {
                let index = try self.withLock {
                    try self.loadFromDisk()
                }
                callback(.success(index))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func update(index: PackageIndexConfiguration, callback: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.sharedConcurrent.async {
            do {
                try self.withLock {
                    try self.saveToDisk(index)
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    private func loadFromDisk() throws -> PackageIndexConfiguration {
        guard self.fileSystem.exists(self.path) else {
            return .init()
        }
        let buffer = try fileSystem.readFileContents(self.path).contents
        guard buffer.count > 0 else {
            return .init()
        }
        let container = try decoder.decode(StorageModel.Container.self, from: Data(buffer))
        return try PackageIndexConfiguration(container.index)
    }

    private func saveToDisk(_ index: PackageIndexConfiguration) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        let container = StorageModel.Container(index)
        let buffer = try encoder.encode(container)
        try self.fileSystem.writeFileContents(self.path, bytes: ByteString(buffer))
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive, body)
    }
}

private enum StorageModel {
    struct Container: Codable {
        var index: Index

        init() {
            self.index = .init(url: nil)
        }

        init(_ from: PackageIndexConfiguration) {
            self.index = .init(url: from.url?.absoluteString)
        }
    }

    struct Index: Codable {
        let url: String?
    }
}

// MARK: - Utility

private extension PackageIndexConfiguration {
    init(_ from: StorageModel.Index) throws {
        switch from.url {
        case .none:
            self.init(url: nil)
        case .some(let urlString):
            guard let url = URL(string: urlString) else {
                throw SerializationError.invalidURL(urlString)
            }
            self.init(url: url)
        }
    }
}

private enum SerializationError: Error {
    case invalidURL(String)
}
