//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A `swiftpmrc` file is similar to a `netrc` file but in JSON format instead.
/// For example:
///
/// ````
/// {
///   "machines": [
///     {
///       "name": "example.com",
///       "login": "jappleseed",
///       "password": "top-secret"
///     },
///     {
///       "name": "example.com:8080",
///       "password": "secret-token"
///     }
///   ],
///   "version": 1
/// }
/// ````
///
/// Both `login` and `password` are required for basic authentication.
/// Only `password` is required for token authentication.
///
/// Machine name should include port if non-standard ports are used.
public struct Swiftpmrc {
    /// Representation of `machine` connection settings
    public let machines: [Machine]

    /// Returns authorization information.
    ///
    /// - Parameters:
    ///   - url: The url to retrieve authorization information for.
    public func authorization(for url: URL) -> Authorization? {
        guard let index = machines.firstIndex(where: { $0.name == url.machineName }) else {
            return .none
        }
        let machine = self.machines[index]
        return Authorization(
            login: machine.login,
            password: machine.password
        )
    }

    private func machineName(for url: URL) throws -> String? {
        guard let host = url.host?.lowercased() else {
            return .none
        }
        return [host, url.port?.description].compactMap { $0 }.joined(separator: ":")
    }

    /// Representation of connection settings
    public struct Machine: Equatable, Decodable {
        public let name: String
        // `login` is not required in some authentication methods (e.g., token)
        public let login: String?
        public let password: String
    }

    /// Representation of authorization information
    public struct Authorization: Equatable {
        public let login: String?
        public let password: String
    }
}

extension URL {
    fileprivate var machineName: String? {
        guard let host = self.host?.lowercased() else {
            return .none
        }
        return [host, self.port?.description].compactMap { $0 }.joined(separator: ":")
    }
}

// MARK: - swiftpmrc parsing

extension Swiftpmrc {
    /// Parse a `swiftpmrc` file at the give location.
    ///
    /// - Parameters:
    ///   - fileSystem: The file system to use.
    ///   - path: The file to parse.
    public static func parse(fileSystem: FileSystem, path: AbsolutePath) throws -> Swiftpmrc {
        guard fileSystem.exists(path) else {
            throw SwiftpmrcError.fileNotFound(path)
        }
        guard fileSystem.isReadable(path) else {
            throw SwiftpmrcError.unreadableFile(path)
        }
        let content: Data = try fileSystem.readFileContents(path)
        return try Self.parse(content)
    }

    /// Parse `swiftpmrc` contents.
    ///
    /// - Parameters:
    ///   - content: The content to parse.
    public static func parse(_ content: Data) throws -> Swiftpmrc {
        let decoder = JSONDecoder()
        let schemaVersion = try decoder.decode(SchemaVersion.self, from: content)
        switch schemaVersion.version {
        case .some(1):
            let container = try decoder.decode(Container.V1.self, from: content)
            guard !container.machines.isEmpty else {
                throw SwiftpmrcError.machineNotFound
            }
            return Swiftpmrc(machines: container.machines)
        default:
            throw SwiftpmrcError.unsupportedVersion(schemaVersion.version)
        }
    }
}

extension Swiftpmrc {
    struct SchemaVersion: Codable {
        let version: Int?
    }

    enum Container {
        struct V1: Decodable {
            let version: Int?
            let machines: [Swiftpmrc.Machine]
        }
    }
}

public enum SwiftpmrcError: Error, Equatable {
    case fileNotFound(AbsolutePath)
    case unreadableFile(AbsolutePath)
    case machineNotFound
    case unsupportedVersion(Int?)
}
