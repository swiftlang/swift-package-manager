//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import Basics
import Dispatch
import TSCBasic
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.URL

struct FilePackageCollectionsSourcesStorage: PackageCollectionsSourcesStorage {
    let fileSystem: FileSystem
    let path: Basics.AbsolutePath

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileSystem: FileSystem, path: Basics.AbsolutePath? = nil) {
        self.fileSystem = fileSystem

        self.path = path ?? (try? fileSystem.swiftPMConfigurationDirectory.appending("collections.json")) ?? .root
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    func list() async throws -> [PackageCollectionsModel.CollectionSource] {
        try self.withLock {
            try self.loadFromDisk()
        }
    }

    func add(source: PackageCollectionsModel.CollectionSource, order: Int? = nil) async throws {
        try self.withLock {
            var sources = try self.loadFromDisk()
            sources = sources.filter { $0 != source }
            let order = order.flatMap { $0 >= 0 && $0 < sources.endIndex ? order : sources.endIndex } ?? sources.endIndex
            sources.insert(source, at: order)
            try self.saveToDisk(sources)
        }
    }

    func remove(source: PackageCollectionsModel.CollectionSource) async throws {
        try self.withLock {
            var sources = try self.loadFromDisk()
            sources = sources.filter { $0 != source }
            try self.saveToDisk(sources)
        }
    }

    func move(source: PackageCollectionsModel.CollectionSource, to order: Int) async throws {
        try self.withLock {
            var sources = try self.loadFromDisk()
            sources = sources.filter { $0 != source }
            let order = order >= 0 && order < sources.endIndex ? order : sources.endIndex
            sources.insert(source, at: order)
            try self.saveToDisk(sources)
        }
    }

    func exists(source: PackageCollectionsModel.CollectionSource) async throws -> Bool {
        try self.withLock {
            try self.loadFromDisk()
        }.contains(source)
    }

    func update(source: PackageCollectionsModel.CollectionSource) async throws {
        try self.withLock {
            var sources = try self.loadFromDisk()
            if let index = sources.firstIndex(where: { $0 == source }) {
                sources[index] = source
                try self.saveToDisk(sources)
            }
        }
    }

    private func loadFromDisk() throws -> [Model.CollectionSource] {
        guard self.fileSystem.exists(self.path) else {
            return .init()
        }
        let data: Data = try fileSystem.readFileContents(self.path)
        guard data.count > 0 else {
            return .init()
        }
        let container = try decoder.decode(StorageModel.Container.self, from: data)
        return try container.sources()
    }

    private func saveToDisk(_ sources: [Model.CollectionSource]) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        let container = StorageModel.Container(sources)
        let buffer = try encoder.encode(container)
        try self.fileSystem.writeFileContents(self.path, data: buffer)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        if !fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive, body)
    }
}

// MARK: - FilePackageCollectionsSourcesStorage Serialization

private enum StorageModel {
    struct Container: Codable {
        var data: [Source]

        init() {
            self.data = .init()
        }

        init(_ from: [Model.CollectionSource]) {
            self.data = from.map { $0.source() }
        }

        func sources() throws -> [Model.CollectionSource] {
            return try self.data.map { try Model.CollectionSource($0) }
        }
    }

    struct Source: Codable {
        let type: String
        let value: String
        let isTrusted: Bool?
        let skipSignatureCheck: Bool?
    }

    enum SourceType: String {
        case json
    }
}

// MARK: - Utility

private extension Model.CollectionSource {
    init(_ from: StorageModel.Source) throws {
        guard let url = URL(string: from.value) else {
            throw SerializationError.invalidURL(from.value)
        }

        switch from.type {
        case StorageModel.SourceType.json.rawValue:
            self.init(type: .json, url: url, isTrusted: from.isTrusted, skipSignatureCheck: from.skipSignatureCheck ?? false)
        default:
            throw SerializationError.unknownType(from.type)
        }
    }

    func source() -> StorageModel.Source {
        switch self.type {
        case .json:
            return .init(type: StorageModel.SourceType.json.rawValue, value: self.url.absoluteString,
                         isTrusted: self.isTrusted, skipSignatureCheck: self.skipSignatureCheck)
        }
    }
}

private enum SerializationError: Error {
    case unknownType(String)
    case invalidURL(String)
}
