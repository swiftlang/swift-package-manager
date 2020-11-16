/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.URL
import TSCBasic

// MARK: - PackageCollectionsProfileStorage

public protocol PackageCollectionsProfileStorage {
    /// Lists all configured profiles.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke when result becomes available
    func listProfiles(callback: @escaping (Result<[PackageCollectionsModel.Profile], Error>) -> Void)

    /// Lists all `PackageCollectionSource`s in the given profile.
    ///
    /// - Parameters:
    ///   - profile: The `PackageCollectionsModel.Profile`
    ///   - callback: The closure to invoke when result becomes available
    func listSources(in profile: PackageCollectionsModel.Profile,
                     callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void)

    /// Adds source to the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to add
    ///   - order: Optional. The order that the source should take after being added to the profile.
    ///            By default the new source is appended to the end (i.e., the least relevant order).
    ///   - profile: The `Profile` to add source
    ///   - callback: The closure to invoke when result becomes available
    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int?,
             to profile: PackageCollectionsModel.Profile,
             callback: @escaping (Result<Void, Error>) -> Void)

    /// Removes source from the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to remove
    ///   - profile: The `Profile` to remove source
    ///   - callback: The closure to invoke when result becomes available
    func remove(source: PackageCollectionsModel.CollectionSource,
                from profile: PackageCollectionsModel.Profile,
                callback: @escaping (Result<Void, Error>) -> Void)

    /// Moves source to a different order within the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to move
    ///   - order: The order that the source should take in the profile.
    ///   - profile: The `Profile` to move source
    ///   - callback: The closure to invoke when result becomes available
    func move(source: PackageCollectionsModel.CollectionSource,
              to order: Int,
              in profile: PackageCollectionsModel.Profile,
              callback: @escaping (Result<Void, Error>) -> Void)

    /// Checks if a source is already in a profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource`
    ///   - profile: Optional. The `Profile`, If not specified, checks across all profiles.
    ///   - callback: The closure to invoke when result becomes available
    func exists(source: PackageCollectionsModel.CollectionSource,
                in profile: PackageCollectionsModel.Profile?,
                callback: @escaping (Result<Bool, Error>) -> Void)
}

// MARK: - FilePackageCollectionsProfileStorage

struct FilePackageCollectionsProfileStorage: PackageCollectionsProfileStorage {
    let fileSystem: FileSystem
    let path: AbsolutePath

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let queue = DispatchQueue(label: "org.swift.swiftpm.FilePackageCollectionsProfileStorage")

    init(fileSystem: FileSystem = localFileSystem, path: AbsolutePath? = nil) {
        self.fileSystem = fileSystem

        let name = "collections"
        self.path = path ?? fileSystem.dotSwiftPM.appending(component: "\(name).json")

        self.encoder = JSONEncoder()
        if #available(macOS 10.15, *) {
            #if os(macOS)
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            #else // `.withoutEscapingSlashes` is not in 5.3 on non-Darwin platforms
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            #endif
        }
        self.decoder = JSONDecoder()
    }

    func listProfiles(callback: @escaping (Result<[PackageCollectionsModel.Profile], Error>) -> Void) {
        self.queue.async {
            do {
                let profiles = try self.withLock {
                    try self.loadFromDisk()
                }
                callback(.success(Array(profiles.keys)))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func listSources(in profile: PackageCollectionsModel.Profile, callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        self.queue.async {
            do {
                let profiles = try self.withLock {
                    try self.loadFromDisk()
                }
                callback(.success(profiles[profile] ?? []))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int?,
             to profile: PackageCollectionsModel.Profile,
             callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            do {
                try self.withLock {
                    var profiles = try self.loadFromDisk()
                    var sources = profiles[profile]?.filter { $0 != source } ?? []
                    let order = order.flatMap { $0 >= 0 && $0 < sources.endIndex ? order : sources.endIndex } ?? sources.endIndex
                    sources.insert(source, at: order)
                    profiles[profile] = sources
                    try self.saveToDisk(profiles)
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func remove(source: PackageCollectionsModel.CollectionSource,
                from profile: PackageCollectionsModel.Profile,
                callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            do {
                try self.withLock {
                    var profiles = try self.loadFromDisk()
                    guard let sources = profiles[profile] else {
                        throw Errors.invalidProfile(profile)
                    }
                    profiles[profile] = sources.filter { $0 != source }
                    try self.saveToDisk(profiles)
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func move(source: PackageCollectionsModel.CollectionSource,
              to order: Int,
              in profile: PackageCollectionsModel.Profile,
              callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            do {
                try self.withLock {
                    var profiles = try self.loadFromDisk()
                    guard var sources = profiles[profile] else {
                        throw Errors.invalidProfile(profile)
                    }
                    sources = sources.filter { $0 != source }
                    let order = order >= 0 && order < sources.endIndex ? order : sources.endIndex
                    sources.insert(source, at: order)
                    profiles[profile] = sources
                    try self.saveToDisk(profiles)
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func exists(source: PackageCollectionsModel.CollectionSource,
                in profile: PackageCollectionsModel.Profile?,
                callback: @escaping (Result<Bool, Error>) -> Void) {
        self.queue.async {
            do {
                let profiles = try self.withLock {
                    try self.loadFromDisk()
                }
                let containers = profiles.filter { $0.value.contains(source) }
                if let profile = profile {
                    callback(.success(containers.keys.contains(profile)))
                } else {
                    callback(.success(!containers.isEmpty))
                }
            } catch {
                callback(.failure(error))
            }
        }
    }

    private func loadFromDisk() throws -> [PackageCollectionsModel.Profile: [PackageCollectionsModel.CollectionSource]] {
        guard self.fileSystem.exists(self.path) else {
            return .init()
        }
        let buffer = try fileSystem.readFileContents(self.path).contents
        guard buffer.count > 0 else {
            return .init()
        }
        let container = try decoder.decode(Model.Container.self, from: Data(buffer))
        return try container.profiles()
    }

    private func saveToDisk(_ profiles: [PackageCollectionsModel.Profile: [PackageCollectionsModel.CollectionSource]]) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        let container = Model.Container(profiles)
        let buffer = try encoder.encode(container)
        try self.fileSystem.writeFileContents(self.path, bytes: ByteString(buffer))
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive, body)
    }

    private enum Errors: Error {
        case invalidProfile(PackageCollectionsModel.Profile)
    }
}

// MARK: - FilePackageCollectionsProfileStorage Serialization

private enum Model {
    struct Container: Codable {
        var data: [String: [Source]]

        init() {
            self.data = .init()
        }

        init(_ profiles: [PackageCollectionsModel.Profile: [PackageCollectionsModel.CollectionSource]]) {
            self.data = .init()
            profiles.forEach { key, value in
                self.data[key.profile()] = value.map { $0.source() }
            }
        }

        func profiles() throws -> [PackageCollectionsModel.Profile: [PackageCollectionsModel.CollectionSource]] {
            var profiles = [PackageCollectionsModel.Profile: [PackageCollectionsModel.CollectionSource]]()
            try self.data.forEach { key, value in
                try profiles[PackageCollectionsModel.Profile(key)] = value.map { try PackageCollectionsModel.CollectionSource($0) }
            }
            return profiles
        }
    }

    struct Source: Codable {
        let type: String
        let value: String
    }

    enum SourceType: String {
        case feed
    }
}

// MARK: - Utility

private extension PackageCollectionsModel.Profile {
    init(_ from: String) {
        self.init(name: from)
    }

    func profile() -> String {
        name
    }
}

private extension PackageCollectionsModel.CollectionSource {
    init(_ from: Model.Source) throws {
        guard let url = URL(string: from.value) else {
            throw SerializationError.invalidURL(from.value)
        }
        self.url = url
        switch from.type {
        case Model.SourceType.feed.rawValue:
            self.type = .feed
        default:
            throw SerializationError.unknownType(from.type)
        }
    }

    func source() -> Model.Source {
        switch self.type {
        case .feed:
            return .init(type: Model.SourceType.feed.rawValue, value: self.url.absoluteString)
        }
    }
}

private enum SerializationError: Error {
    case unknownType(String)
    case invalidURL(String)
}
