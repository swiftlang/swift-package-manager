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

        /// The pinned revision.
        public let revision: Revision

        /// The pinned version, if known.
        public let version: Version?

        /// The pinned branch name, if known.
        public let branch: String?

        /// The reason text for pinning this dependency.
        public let reason: String?

        init(
            package: String,
            repository: RepositorySpecifier,
            revision: Revision,
            version: Version? = nil,
            branch: String? = nil,
            reason: String? = nil
        ) {
            assert(version == nil || branch == nil, "Can't set both branch and version.")
            self.package = package 
            self.repository = repository 
            self.revision = revision
            self.version = version
            self.branch = branch
            self.reason = reason
        }

        /// Returns the description of the pin which can be used in user
        /// viewable diagnostics. It returns one the pin information available.
        /// Search order: version, branch, revision.
        public var description: String {
            if let version = version {
                return version.description
            } else if let branch = branch {
                return branch
            }
            return revision.identifier
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
    ///   - revision: The version to pin at.
    ///   - version: The version of the revision, if known.
    ///   - branch: The branch name, if known.
    ///   - reason: The optional reason for pinning.
    /// - Throws: PinOperationError
    public mutating func pin(
        package: String,
        repository: RepositorySpecifier,
        revision: Revision,
        version: Version? = nil,
        branch: String? = nil,
        reason: String? = nil
    ) throws {
        precondition(version == nil || branch == nil, "Can't set both branch and version.")
        // Add pin and save the state.
        pinsMap[package] = Pin(
            package: package,
            repository: repository,
            revision: revision,
            version: version,
            branch: branch,
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
            let requirement: RepositoryPackageConstraint.Requirement
            if let version = pin.version {
                requirement = .versionSet(.exact(version))
            } else if let branch = pin.branch {
                requirement = .revision(branch)
            } else {
                requirement = .revision(pin.revision.identifier)
            }
            return RepositoryPackageConstraint(container: pin.repository, requirement: requirement)
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
              case let .string(repositoryURL)? = contents["repositoryURL"],
              case let .string(revision)? = contents["revision"] else {
            return nil
        }
        self.package = package
        self.repository = RepositorySpecifier(url: repositoryURL)
        self.reason = contents["reason"].flatMap{
            if case .string(let reason) = $0 { return reason }
            return nil
        }
        self.revision = Revision(identifier: revision)
        self.version = contents["version"].flatMap{
            if case .string(let versionString) = $0 { return Version(string: versionString)! }
            return nil
        }
        self.branch = contents["branch"].flatMap{
            if case .string(let branch) = $0 { return branch }
            return nil
        }
    }

    /// Convert the pin to JSON.
    func toJSON() -> JSON {
        return .dictionary([
                "package": .string(package),
                "repositoryURL": .string(repository.url),
                "revision": .string(revision.identifier),
                "version": version.flatMap{ JSON.string(String(describing: $0)) } ?? .null,
                "branch": branch.flatMap(JSON.string) ?? .null,
                "reason": reason.flatMap(JSON.string) ?? .null,
            ])
    }

    public static func ==(lhs: PinsStore.Pin, rhs: PinsStore.Pin) -> Bool {
        return lhs.package == rhs.package &&
               lhs.repository == rhs.repository &&
               lhs.revision == rhs.revision &&
               lhs.version == rhs.version &&
               lhs.branch == rhs.branch
    }
}
