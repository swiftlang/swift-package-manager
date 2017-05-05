/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import SourceControl
import typealias PackageGraph.RepositoryPackageConstraint

public enum PinOperationError: Swift.Error, CustomStringConvertible {
    case notPinned

    public var description: String {
        switch self {
        case .notPinned:
            return "The provided package is not pinned"
        }
    }
}

public final class PinsStore {
    public struct Pin {
        /// The package name of the pinned dependency.
        public let package: String

        /// The repository specifier of the pinned dependency.
        public let repository: RepositorySpecifier

        /// The pinned state.
        public let state: CheckoutState

        init(
            package: String,
            repository: RepositorySpecifier,
            state: CheckoutState
        ) {
            self.package = package
            self.repository = repository
            self.state = state
        }
    }

    /// The path to the pins file.
    fileprivate let pinsFile: AbsolutePath

    /// The filesystem to manage the pin file on.
    fileprivate var fileSystem: FileSystem

    /// The pins map.
    fileprivate(set) var pinsMap: [String: Pin]

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
            schemaVersion: 1,
            statePath: pinsFile,
            prettyPrint: true)
        pinsMap = [:]
        _ = try self.persistence.restoreState(self)
    }

    /// Pin a repository at a version.
    ///
    /// This method does not automatically write to state file.
    ///
    /// - Parameters:
    ///   - package: The name of the package to pin.
    ///   - repository: The repository to pin.
    ///   - state: The state to pin at.
    public func pin(
        package: String,
        repository: RepositorySpecifier,
        state: CheckoutState
    ) {
        pinsMap[package] = Pin(
            package: package,
            repository: repository,
            state: state
        )
    }

    /// Add a pin.
    ///
    /// This will replace any previous pin with same package name.
    public func add(_ pin: Pin) {
        pinsMap[pin.package] = pin
    }

    /// Pin a managed dependency at its checkout state.
    ///
    /// This method does nothing if the dependency is in edited state.
    func pin(_ dependency: ManagedDependency) {

        // Get the checkout state.
        let checkoutState: CheckoutState
        switch dependency.state {
        case .checkout(let state):
            checkoutState = state
        case .edited:
            return
        }

        self.pin(
            package: dependency.name,
            repository: dependency.repository,
            state: checkoutState)
    }

    /// Unpin all of the currently pinnned dependencies.
    ///
    /// This method does not automatically write to state file.
    public func unpinAll() {
        // Reset the pins map.
        pinsMap = [:]
    }

    /// Creates constraints based on the pins in the store.
    public func createConstraints() -> [RepositoryPackageConstraint] {
        return pins.map({ pin in
            return RepositoryPackageConstraint(
                container: pin.repository, requirement: pin.state.requirement())
        })
    }
}

/// Persistence.
extension PinsStore: SimplePersistanceProtocol {

    public func saveState() throws {
        try self.persistence.saveState(self)
    }

    public func restore(from json: JSON) throws {
        self.pinsMap = try Dictionary(items: json.get("pins").map({ ($0.package, $0) }))
    }

    /// Saves the current state of pins.
    public func toJSON() -> JSON {
        return JSON([
            "pins": pins.sorted(by: { $0.package < $1.package }).toJSON(),
        ])
    }
}

// JSON.
extension PinsStore.Pin: JSONMappable, JSONSerializable, Equatable {
    /// Create an instance from JSON data.
    public init(json: JSON) throws {
        self.package = try json.get("package")
        self.repository = try json.get("repositoryURL")
        self.state = try json.get("state")
    }

    /// Convert the pin to JSON.
    public func toJSON() -> JSON {
        return .init([
            "package": package,
            "repositoryURL": repository,
            "state": state,
        ])
    }

    public static func == (lhs: PinsStore.Pin, rhs: PinsStore.Pin) -> Bool {
        return lhs.package == rhs.package &&
               lhs.repository == rhs.repository &&
               lhs.state == rhs.state
    }
}
