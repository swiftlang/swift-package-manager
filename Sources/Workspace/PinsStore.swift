/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import struct Utility.Version
import SourceControl
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

        /// The pinned state.
        public let state: CheckoutState

        /// The reason text for pinning this dependency.
        public let reason: String?

        init(
            package: String,
            repository: RepositorySpecifier,
            state: CheckoutState,
            reason: String? = nil
        ) {
            self.package = package 
            self.repository = repository 
            self.state = state
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
    /// - precodition: Both branch and version can't be provided.
    /// - Parameters:
    ///   - package: The name of the package to pin.
    ///   - repository: The repository to pin.
    ///   - state: The state to pin at.
    ///   - reason: The reason for pinning.
    /// - Throws: PinOperationError
    public mutating func pin(
        package: String,
        repository: RepositorySpecifier,
        state: CheckoutState,
        reason: String? = nil
    ) throws {
        // Add pin and save the state.
        pinsMap[package] = Pin(
            package: package,
            repository: repository,
            state: state,
            reason: reason
        )
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
        return pins.map { pin in
            return RepositoryPackageConstraint(
                container: pin.repository, requirement: pin.state.requirement())
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
        // FIXME: We will need migration support when we update pins schema.
        guard try json.get("version") == PinsStore.currentSchemaVersion else {
            fatalError("Migration not supported yet")
        }
        // Load the pins.
        self.autoPin = try json.get("autoPin")
        self.pinsMap = try Dictionary(items: json.get("pins").map{($0.package, $0)})
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
extension PinsStore.Pin: JSONMappable, Equatable {
    /// Create an instance from JSON data.
    public init(json: JSON) throws {
        self.package = try json.get("package")
        self.repository = try json.get("repositoryURL")
        self.reason = json.get("reason")
        self.state = try json.get("state")
    }

    /// Convert the pin to JSON.
    func toJSON() -> JSON {
        return .dictionary([
                "package": .string(package),
                "repositoryURL": .string(repository.url),
                "state": state.toJSON(),
                "reason": reason.flatMap(JSON.string) ?? .null,
            ])
    }

    public static func ==(lhs: PinsStore.Pin, rhs: PinsStore.Pin) -> Bool {
        return lhs.package == rhs.package &&
               lhs.repository == rhs.repository &&
               lhs.state == rhs.state
    }
}
