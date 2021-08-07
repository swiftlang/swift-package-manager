/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import TSCBasic

extension Configuration {
    public struct Collections {
        private let fileSystem: FileSystem
        public let path: AbsolutePath
        public var authTokens: () -> [AuthTokenType: String]?

        public init(fileSystem: FileSystem,
                    path: AbsolutePath? = nil,
                    authTokens: @escaping () -> [AuthTokenType: String]? = { nil }) {
            self.fileSystem = fileSystem
            self.path = path ?? fileSystem.swiftPMConfigDirectory.appending(component: "collections.json")
            self.authTokens = authTokens
        }

        public struct Source: Equatable {
            public let type: String
            public let value: String
            public let isTrusted: Bool?
            public let skipSignatureCheck: Bool?

            public init(type: String, value: String, isTrusted: Bool?, skipSignatureCheck: Bool?) {
                self.type = type
                self.value = value
                self.isTrusted = isTrusted
                self.skipSignatureCheck = skipSignatureCheck
            }
        }

        public enum AuthTokenType: Hashable, Equatable {
            case github(_ host: String)
        }
    }
}

extension Configuration.Collections {
    @discardableResult
    public func withSources(handler: (inout [Source]) throws  -> Void) throws -> [Source] {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive) {
            let sources = try Self.load(self.path, fileSystem: self.fileSystem)
            var updatedSources = sources
            try handler(&updatedSources)
            if updatedSources != sources {
                try Self.save(updatedSources, to: self.path, fileSystem: self.fileSystem)
            }
            return updatedSources
        }
    }

    public func sources() throws -> [Source] {
        try self.withSources { _ in }
    }
}

extension Configuration.Collections {
    private static func load(_ path: AbsolutePath, fileSystem: FileSystem) throws -> [Source] {
        guard fileSystem.exists(path) else {
            return .init()
        }
        let data: Data = try fileSystem.readFileContents(path)
        guard data.count > 0 else {
            return .init()
        }
        let decoder = JSONDecoder.makeWithDefaults()
        let container = try decoder.decode(Storage.Container.self, from: data)
        return try container.sources()
    }

    private static func save(_ sources: [Source], to path: AbsolutePath, fileSystem: FileSystem) throws {
        if !fileSystem.exists(path.parentDirectory) {
            try fileSystem.createDirectory(path.parentDirectory, recursive: true)
        }
        let encoder = JSONEncoder.makeWithDefaults()
        let container = Storage.Container(sources)
        let data = try encoder.encode(container)
        try fileSystem.writeFileContents(path, data: data)
    }

    private enum Storage {
        struct Container: Codable {
            var data: [Source]

            init() {
                self.data = .init()
            }

            init(_ from: [Configuration.Collections.Source]) {
                self.data = from.map {
                    Source(type: $0.type,
                           value: $0.value,
                           isTrusted: $0.isTrusted,
                           skipSignatureCheck: $0.skipSignatureCheck)
                }
            }

            func sources() throws -> [Configuration.Collections.Source] {
                return self.data.map {
                    Configuration.Collections.Source(type: $0.type,
                                                     value: $0.value,
                                                     isTrusted: $0.isTrusted,
                                                     skipSignatureCheck: $0.skipSignatureCheck)

                }
            }
        }

        struct Source: Codable {
            let type: String
            let value: String
            let isTrusted: Bool?
            let skipSignatureCheck: Bool?
        }
    }
}
