/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

public final class PinsStore {
    public typealias PinsMap = [PackageReference.Identity: PinsStore.Pin]

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
    private let pinsFile: AbsolutePath

    /// The filesystem to manage the pin file on.
    private var fileSystem: FileSystem

    /// The pins map.
    public private(set) var pinsMap: PinsMap

    /// The current pins.
    public var pins: AnySequence<Pin> {
        return AnySequence<Pin>(self.pinsMap.values)
    }

    private let persistence: SimplePersistence

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
            prettyPrint: true
        )
        self.pinsMap = [:]
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
        self.pinsMap[packageRef.identity] = Pin(
            packageRef: packageRef,
            state: state
        )
    }

    /// Add a pin.
    ///
    /// This will replace any previous pin with same package name.
    public func add(_ pin: Pin) {
        self.pinsMap[pin.packageRef.identity] = pin
    }

    /// Unpin all of the currently pinnned dependencies.
    ///
    /// This method does not automatically write to state file.
    public func unpinAll() {
        // Reset the pins map.
        self.pinsMap = [:]
    }

    public func saveState() throws {
        if self.pinsMap.isEmpty {
            // Remove the pins file if there are zero pins to save.
            //
            // This can happen if all dependencies are path-based or edited
            // dependencies.
            return try self.fileSystem.removeFileTree(self.pinsFile)
        }

        try self.persistence.saveState(self)
    }
}

// MARK: - JSON

extension PinsStore: JSONSerializable {
    /// Saves the current state of pins.
    public func toJSON() -> JSON {
        return JSON([
            "pins": self.pins.sorted(by: { $0.packageRef.identity < $1.packageRef.identity }).toJSON(),
        ])
    }
}

extension PinsStore.Pin: JSONMappable, JSONSerializable {
    /// Create an instance from JSON data.
    public init(json: JSON) throws {
        let name: String? = json.get("package")
        let url: String = try json.get("repositoryURL")
        let ref = PackageReference(identity: url, path: url)
        self.packageRef = name.flatMap(ref.with(newName:)) ?? ref
        self.state = try json.get("state")
    }

    /// Convert the pin to JSON.
    public func toJSON() -> JSON {
        return .init([
            "package": packageRef.name.toJSON(),
            "repositoryURL": packageRef.path,
            "state": state,
        ])
    }
}

// MARK: - SimplePersistanceProtocol

extension PinsStore: SimplePersistanceProtocol {
    public func restore(from json: JSON) throws {
        self.pinsMap = try Dictionary(json.get("pins").map { ($0.packageRef.identity, $0) }, uniquingKeysWith: { first, _ in throw StringError("duplicated entry for package \"\(first.packageRef.name)\"") })
    }
}
