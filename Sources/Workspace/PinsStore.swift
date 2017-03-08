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

public enum PinOperationError: Swift.Error, Equatable {
    case notPinned
    case autoPinEnabled
    case hasPriorError(error: Swift.Error)
    
    public static func ==(lhs: PinOperationError, rhs: PinOperationError) -> Bool {
        switch (lhs, rhs) {
        case (.notPinned, .notPinned):
            return true
        case (.notPinned, _):
            return false
        case (.autoPinEnabled, .autoPinEnabled):
            return true
        case (.autoPinEnabled, _):
            return false
        case (.hasPriorError(_), .hasPriorError(_)):
            // should we also compare the error somehow?
            return true
        case (.hasPriorError, _):
            return false
        }
    }

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
    
    /// Most recent error, if any.
    /// FIXME: This needs to be an array of diagnostics, or perhaps a structured
    /// log of what-all went on while trying to instantiate the PinStore.
    public var error: Error?
    
    /// Returns true if and only iff there are any errors; when this property is
    /// true, mutating PinStore operations are disallowed and will throw errors.
    /// FIXME: We should have a protocol for "things that can hold errors", and
    /// then the `hasErrors` property should be a convenience implementation so
    /// it doesn't need to be implemented in every adopter of the protocol.
    public var hasError: Bool { return error != nil }

    /// Create a new pins store. This never fails; even if the file is malformed
    /// the PinStore will be created, but will be in an error state.  Operations
    /// that can modify the PinStore are disallowed (i.e. throw `hasPriorError`
    /// errors) in the presence of prior errors.
    ///
    /// - Parameters:
    ///   - pinsFile: Path to the pins file.
    ///   - fileSystem: The filesystem to manage the pin file on.
    public init(pinsFile: AbsolutePath, fileSystem: FileSystem) {
        self.pinsFile = pinsFile
        self.fileSystem = fileSystem
        self.pinsMap = [:]
        self.autoPin = true
        restoreState()
    }

    /// Update the autopin setting. Writes the setting to pins file. Throws an
    /// error if the PinStore is in an error state (if there was an error trying
    /// to originally load it).
    public mutating func setAutoPin(on value: Bool) throws {
        autoPin = value
        try saveState()
    }

    /// Pin a repository at a version. Throws an error if the PinStore is in an
    /// error state (if there was an error trying to originally load it).
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
        // If we have an error, we can go no further.
        if let error = self.error {
            throw PinOperationError.hasPriorError(error: error)
        }
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
        // If we have an error, we can go no further.
        if let error = self.error {
            throw PinOperationError.hasPriorError(error: error)
        }
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
        // If we have an error, we can go no further.
        if let error = self.error {
            throw PinOperationError.hasPriorError(error: error)
        }
        // Reset the pins map.
        pinsMap = [:]
        // Save the state.
        try saveState()
    }

    /// Creates constraints based on the pins in the store.
    public func createConstraints() throws -> [RepositoryPackageConstraint] {
        // If we have an error, we can go no further.
        if let error = self.error {
            throw PinOperationError.hasPriorError(error: error)
        }
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
    
    fileprivate mutating func restoreState() {
        // If the pin file doesn't exist, don't even try to go further.
        guard fileSystem.exists(pinsFile) else {
            // FIXME: Should we also clear out the error here?
            return
        }
        
        do {
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
        catch {
            // An error occurred, so save it for future reporting.  Because we have an error, operations on the PinStore will throw errors, preventing overwriting of the broken file, and operations that try to use it can report the error to the user.
            self.error = error
        }
    }

    /// Saves the current state of pins.
    fileprivate mutating func saveState() throws {
        // If we have an error, we can go no further.
        if let error = self.error { throw error }
        
        // Otherwise, create a JSON dictionary.
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
              case let .string(repositoryURL)? = contents["repositoryURL"],
              let stateData = contents["state"],
              let state = CheckoutState(json: stateData) else {
            return nil
        }
        self.package = package
        self.repository = RepositorySpecifier(url: repositoryURL)
        self.reason = JSON.getOptional(contents["reason"])
        self.state = state
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
