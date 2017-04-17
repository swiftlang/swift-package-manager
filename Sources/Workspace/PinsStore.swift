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
    case autoPinEnabled

    public var description: String {
        switch self {
        case .notPinned:
            return "The provided package is not pinned"
        case .autoPinEnabled:
            return "Autopinning should be turned off to use this"
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

    /// Auto-pin enabled or disabled. Auto-pinned is enabled by default.
    public fileprivate(set) var isAutoPinEnabled: Bool

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
        isAutoPinEnabled = true
        _ = try self.persistence.restoreState(self)
    }

    /// Update the autopin setting. Writes the setting to pins file.
    public func setAutoPin(on value: Bool) throws {
        isAutoPinEnabled = value
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
    public func pin(
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
    public func unpin(package: String) throws -> Pin {
        // Ensure autopin is not on.
        guard !isAutoPinEnabled else {
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
    public func unpinAll() throws {
        // Reset the pins map.
        pinsMap = [:]
        // Save the state.
        try saveState()
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

    fileprivate func saveState() throws {
        try self.persistence.saveState(self)
    }

    public func restore(from json: JSON) throws {
        self.isAutoPinEnabled = try json.get("autoPin")
        self.pinsMap = try Dictionary(items: json.get("pins").map({ ($0.package, $0) }))
    }

    /// Saves the current state of pins.
    public func toJSON() -> JSON {
        return JSON([
            "pins": pins.sorted(by: { $0.package < $1.package }).toJSON(),
            "autoPin": isAutoPinEnabled,
        ])
    }
}

// JSON.
extension PinsStore.Pin: JSONMappable, JSONSerializable, Equatable {

    /// Create an instance from JSON data.
    public init(json: JSON) throws {

        // If it's a relative path then convert it into
        // absolute path relative to the woking directory.
        let repoUrl: String = try json.get("repositoryURL")
        let absPath = AbsolutePath(repoUrl, relativeTo: currentWorkingDirectory).asString

        self.package = try json.get("package")
        self.repository =  RepositorySpecifier(url: absPath)
        self.reason = json.get("reason")
        self.state = try json.get("state")
    }

    /// Convert the pin to JSON.
    public func toJSON() -> JSON {

        // If it's a local path then convert it into
        // relative path relative to the working directory.
        var repositoryPath = repository.url
        if repository.url.characters.first == "/" {
            let absPath = AbsolutePath(repository.url)

            if localFileSystem.exists(absPath) {
                repositoryPath = absPath.relative(to: currentWorkingDirectory).asString
            }
        }

        return .init([
            "package": package,
            "repositoryURL": repositoryPath,
            "state": state,
            "reason": reason.toJSON(),
        ])
    }

    public static func == (lhs: PinsStore.Pin, rhs: PinsStore.Pin) -> Bool {
        return lhs.package == rhs.package &&
               lhs.repository == rhs.repository &&
               lhs.state == rhs.state
    }
}
