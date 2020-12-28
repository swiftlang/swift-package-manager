/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

public final class PinsStore {
    public typealias PinsMap = [PackageIdentity: PinsStore.Pin]

    public struct Pin: Equatable {
        /// The package reference of the pinned dependency.
        public let packageRef: PackageReference

        /// The pinned state.
        public let state: CheckoutState

        public init(
            packageRef: PackageReference,
            state: CheckoutState
        ) {
            self.packageRef = packageRef
            self.state = state
        }
    }

    /// The schema version of the resolved file.
    ///
    /// * 1: Initial version.
    static let schemaVersion: Int = 1

    /// The path to the pins file.
    fileprivate let pinsFile: AbsolutePath

    /// The filesystem to manage the pin file on.
    fileprivate var fileSystem: FileSystem

    /// The pins map.
    public fileprivate(set) var pinsMap: PinsMap

    /// The current pins.
    public var pins: AnySequence<Pin> {
        return AnySequence<Pin>(pinsMap.values)
    }

    fileprivate let persistence: SimplePersistence

    /// Create a new pins store.
    ///
    /// - Parameters:
    ///   - pinsFile: Path to the pins file.
    ///   - fileSystem: The filesystem to manage the pin file on.
    public init(pinsFile: AbsolutePath, fileSystem: FileSystem) throws {
        self.pinsFile = pinsFile
        self.fileSystem = fileSystem
        self.persistence = SimplePersistence(
            fileSystem: fileSystem,
            schemaVersion: PinsStore.schemaVersion,
            statePath: pinsFile,
            prettyPrint: true)
        pinsMap = [:]
        do {
            _ = try self.persistence.restoreState(self)
        } catch SimplePersistence.Error.restoreFailure(_, let error) {
            throw StringError("Package.resolved file is corrupted or malformed; fix or delete the file to continue: \(error)")
        }
    }

    /// Pin a repository at a version.
    ///
    /// This method does not automatically write to state file.
    ///
    /// - Parameters:
    ///   - packageRef: The package reference to pin.
    ///   - state: The state to pin at.
    public func pin(
        packageRef: PackageReference,
        state: CheckoutState
    ) {
        pinsMap[packageRef.identity] = Pin(
            packageRef: packageRef,
            state: state
        )
    }

    /// Add a pin.
    ///
    /// This will replace any previous pin with same package name.
    public func add(_ pin: Pin) {
        pinsMap[pin.packageRef.identity] = pin
    }

    /// Unpin all of the currently pinnned dependencies.
    ///
    /// This method does not automatically write to state file.
    public func unpinAll() {
        // Reset the pins map.
        pinsMap = [:]
    }

    public func saveState() throws {
        if pinsMap.isEmpty {
            // Remove the pins file if there are zero pins to save.
            //
            // This can happen if all dependencies are path-based or edited
            // dependencies.
            return try fileSystem.removeFileTree(pinsFile)
        }

        try self.persistence.saveState(self)
    }
}

// MARK: - JSON

extension PinsStore: JSONSerializable {
    /// Saves the current state of pins.
    public func toJSON() -> JSON {
        return JSON([
            "pins": pins.sorted(by: { $0.packageRef.identity < $1.packageRef.identity }).toJSON(),
        ])
    }
}

extension PinsStore.Pin: JSONMappable, JSONSerializable {
    /// Create an instance from JSON data.
    public init(json: JSON) throws {
        // backwards compatibility 12/2020
        let location: String
        if let value: String = json.get("location") {
            location = value
        } else if let value: String = json.get("repositoryURL") {
            location = value
        } else {
            throw InternalError("unknown location")
        }

        // backwards compatibility 12/2020
        let identity: PackageIdentity
        if let value: PackageIdentity = json.get("identity") {
            identity = value
        } else {
            identity = PackageIdentity(url: location)
        }

        // backwards compatibility 12/2020
        var alternateIdentity: PackageIdentity? = nil
        if let value: PackageIdentity = json.get("alternate_identity") {
            alternateIdentity = value
        } else if let value: String = json.get("name") {
            alternateIdentity = PackageIdentity(name: value)
        }
        let package = PackageReference.remote(identity: identity, location: location)
        self.packageRef = alternateIdentity.map{ package.with(alternateIdentity: $0) } ?? package
        self.state = try json.get("state")
    }

    /// Convert the pin to JSON.
    public func toJSON() -> JSON {
        var map: [String: JSONSerializable] = [
            "identity": self.packageRef.identity,
            "location": self.packageRef.location,
            "state": self.state
        ]
        if let alternateIdentity = self.packageRef.alternateIdentity {
            map["alternate_identity"] = alternateIdentity
        }
        return .init(map)
    }
}

// MARK: - SimplePersistanceProtocol

extension PinsStore: SimplePersistanceProtocol {
    public func restore(from json: JSON) throws {
        self.pinsMap = try Dictionary(json.get("pins").map({ ($0.packageRef.identity, $0) }), uniquingKeysWith: { first, _ in throw StringError("duplicated entry for package \"\(first.packageRef.identity)\"") })
    }
}
