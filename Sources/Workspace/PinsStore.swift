/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import struct Utility.Version
import struct SourceControl.RepositorySpecifier
import typealias PackageGraph.RepositoryPackageConstraint

public enum PinOperationError: Swift.Error {
    case notPinned
    case autoPinEnabled
}

public struct PinsStore {
    public struct Pin {
        /// The package name of the pinned dependency.
        public let package: String

        /// The repository specifier of the pinned dependency.
        public let repository: RepositorySpecifier

        /// The pinned version.
        public let version: Version

        /// The reason text for pinning this dependency.
        public let reason: String?

        init(package: String, repository: RepositorySpecifier, version: Version, reason: String? = nil) {
            self.package = package 
            self.repository = repository 
            self.version = version
            self.reason = reason
        }
    }

    /// The path to the pins file.
    fileprivate let pinsFile: AbsolutePath

    /// The filesystem to manage the pin file on.
    fileprivate var fileSystem: FileSystem

    /// The pins map.
    fileprivate(set) var pinsMap: [String: Pin]

    /// Autopin enabled or disabled. Autopin is enabled by default.
    public fileprivate(set) var autoPin: Bool

    /// The current pins.
    public var pins: AnySequence<Pin> {
        return AnySequence<Pin>(pinsMap.values)
    }

    /// Create a new pins store.
    ///
    /// - Parameters:
    ///   - pinsFile: Path to the pins file.
    ///   - fileSystem: The filesystem to manage the pin file on.
    public init(pinsFile: AbsolutePath, fileSystem: FileSystem) throws {
        self.pinsFile = pinsFile
        self.fileSystem = fileSystem
        pinsMap = [:]
        autoPin = true
        try restoreState()
    }

    /// Update the autopin setting. Writes the setting to pins file.
    public mutating func setAutoPin(on value: Bool) throws {
        autoPin = value
        try saveState()
    }

    /// Pin a repository at a version.
    ///
    /// - Parameters:
    ///   - package: The name of the package to pin.
    ///   - version: The version to pin at.
    ///   - reason: The optional reason for pinning.
    /// - Throws: PinOperationError
    public mutating func pin(package: String, repository: RepositorySpecifier, at version: Version, reason: String? = nil) throws {
        // Add pin and save the state.
        pinsMap[package] = Pin(package: package, repository: repository, version: version, reason: reason)
        try saveState()
    }

    /// Unpin a pinnned repository and saves the state.
    ///
    /// - Parameters:
    ///   - package: The package name to unpin. It should already be pinned.
    /// - Returns: The pin which was removed.
    /// - Throws: PinOperationError
    @discardableResult
    public mutating func unpin(package: String) throws -> Pin {
        // Ensure autopin is not on.
        guard !autoPin else {
            throw PinOperationError.autoPinEnabled
        }
        // The repo should already be pinned.
        guard let pin = pinsMap[package] else { throw PinOperationError.notPinned }
        // Remove pin and save the state.
        pinsMap[package] = nil
        try saveState()
        return pin
    }

    /// Unpin all of the currently pinnned dependencies.
    public mutating func unpinAll() throws {
        // Reset the pins map.
        pinsMap = [:]
        // Save the state.
        try saveState()
    }

    /// Creates constraints based on the pins in the store.
    public func createConstraints() -> [RepositoryPackageConstraint] {
        return pins.map {
            RepositoryPackageConstraint(container: $0.repository, versionRequirement: .exact($0.version))
        }
    }
}

/// Persistence.
extension PinsStore {
    // FIXME: A lot of the persistence mechanism here is copied from
    // `RepositoryManager`. It would be nice to get actual infrastructure around
    // persistence to handle the boilerplate parts.

    private enum PersistenceError: Swift.Error {
        /// There was a missing or malformed key.
        case unexpectedData
    }

    /// The current schema version for the persisted information.
    private static let currentSchemaVersion = 1
    
    fileprivate mutating func restoreState() throws {
        if !fileSystem.exists(pinsFile) {
            return
        }
        // Load the state.
        let json = try JSON(bytes: try fileSystem.readFileContents(pinsFile))

        // Load the state from JSON.
        guard case let .dictionary(contents) = json,
        case let .int(version)? = contents["version"] else {
            throw PersistenceError.unexpectedData
        }
        // FIXME: We will need migration support when we update pins schema.
        guard version == PinsStore.currentSchemaVersion else {
            fatalError("Migration not supported yet")
        }
        guard case let .bool(autoPin)? = contents["autoPin"],
              case let .array(pinsData)? = contents["pins"] else {
            throw PersistenceError.unexpectedData
        }

        // Load the pins.
        var pins = [String: Pin]()
        for pinData in pinsData {
            guard let pin = Pin(json: pinData) else {
                throw PersistenceError.unexpectedData
            }
            pins[pin.package] = pin
        }

        self.autoPin = autoPin
        self.pinsMap = pins 
    }

    /// Saves the current state of pins.
    fileprivate mutating func saveState() throws {
        var data = [String: JSON]()
        data["version"] = .int(PinsStore.currentSchemaVersion)
        data["pins"] = .array(pins.sorted{ $0.package < $1.package  }.map{ $0.toJSON() })
        data["autoPin"] = .bool(autoPin)
        // FIXME: This should write atomically.
        try fileSystem.writeFileContents(pinsFile, bytes: JSON.dictionary(data).toBytes(prettyPrint: true))
    }
}

// JSON.
extension PinsStore.Pin: Equatable {
    /// Create an instance from JSON data.
    init?(json data: JSON) {
        guard case let .dictionary(contents) = data,
              case let .string(package)? = contents["package"],
              case let .string(version)? = contents["version"],
              case let .string(repositoryURL)? = contents["repositoryURL"],
              let reasonData = contents["reason"] else {
            return nil
        }
        self.package = package
        self.repository = RepositorySpecifier(url: repositoryURL)
        if case .string(let reason) = reasonData { 
            self.reason = reason
        } else {
            self.reason = nil
        }
        self.version = Version(string: version)!
    }

    /// Convert the pin to JSON.
    func toJSON() -> JSON {
        return .dictionary([
                "package": .string(package),
                "repositoryURL": .string(repository.url),
                "version": .string(String(describing: version)),
                "reason": reason.flatMap(JSON.string) ?? .null,
            ])
    }

    public static func ==(lhs: PinsStore.Pin, rhs: PinsStore.Pin) -> Bool {
        return lhs.package == rhs.package &&
               lhs.repository == rhs.repository &&
               lhs.version == rhs.version
    }
}
