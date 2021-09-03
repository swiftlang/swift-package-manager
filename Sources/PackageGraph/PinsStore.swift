/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageModel
import SourceControl
import TSCBasic

public final class PinsStore {
    public typealias PinsMap = [PackageIdentity: PinsStore.Pin]

    public struct Pin: Equatable {
        /// The package reference of the pinned dependency.
        public let packageRef: PackageReference

        /// The pinned state.
        public let state: CheckoutState

        public init(packageRef: PackageReference, state: CheckoutState) {
            self.packageRef = packageRef
            self.state = state
        }
    }

    private let mirrors: DependencyMirrors

    /// storage
    private let storage: PinsStorage
    private let _pins: ThreadSafeKeyValueStore<PackageIdentity, PinsStore.Pin>

    /// The current pins.

    public var pinsMap: PinsMap {
        self._pins.get()
    }

    public var pins: AnySequence<Pin> {
        return AnySequence<Pin>(self.pinsMap.values)
    }

    /// Create a new pins store.
    ///
    /// - Parameters:
    ///   - pinsFile: Path to the pins file.
    ///   - fileSystem: The filesystem to manage the pin file on.
    public init(pinsFile: AbsolutePath, workingDirectory: AbsolutePath, fileSystem: FileSystem, mirrors: DependencyMirrors) throws {
        self.storage = .init(path: pinsFile, workingDirectory: workingDirectory, fileSystem: fileSystem)
        self.mirrors = mirrors

        do {
            self._pins = .init(try self.storage.load(mirrors: mirrors))
        } catch {
            self._pins = .init()
            // FIXME: delete the file?
            // FIXME: warning instead of error?
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
    public func pin(packageRef: PackageReference, state: CheckoutState) {
        self.add(.init(
            packageRef: packageRef,
            state: state
        ))
    }

    /// Add a pin.
    ///
    /// This will replace any previous pin with same package name.
    public func add(_ pin: Pin) {
        self._pins[pin.packageRef.identity] = pin
    }

    /// Unpin all of the currently pinned dependencies.
    ///
    /// This method does not automatically write to state file.
    public func unpinAll() {
        // Reset the pins map.
        self._pins.clear()
    }

    public func saveState() throws {
        try self.storage.save(pins: self._pins.get(), mirrors: self.mirrors, removeIfEmpty: true)
    }
}

// MARK: - Serialization

fileprivate struct PinsStorage {
    private let path: AbsolutePath
    private let lockFilePath: AbsolutePath
    private let fileSystem: FileSystem
    private let encoder = JSONEncoder.makeWithDefaults()
    private let decoder = JSONDecoder.makeWithDefaults()

    init(path: AbsolutePath, workingDirectory: AbsolutePath, fileSystem: FileSystem) {
        self.path = path
        self.lockFilePath = workingDirectory.appending(component: path.basename)
        self.fileSystem = fileSystem
    }

    func load(mirrors: DependencyMirrors) throws -> PinsStore.PinsMap {
        if !self.fileSystem.exists(self.path) {
            return [:]
        }

        return try self.fileSystem.withLock(on: self.lockFilePath, type: .shared) {
            let version = try self.decoder.decode(path: self.path, fileSystem: self.fileSystem, as: Version.self)
            switch version.version {
            case V1.version:
                let v1 = try decoder.decode(path: self.path, fileSystem: self.fileSystem, as: V1.self)
                return try v1.object.pins.map{ try PinsStore.Pin($0, mirrors: mirrors) }.reduce(into: [PackageIdentity: PinsStore.Pin]()) { partial, iterator in
                    if partial.keys.contains(iterator.packageRef.identity) {
                        throw StringError("duplicated entry for package \"\(iterator.packageRef.name)\"")
                    }
                    partial[iterator.packageRef.identity] = iterator
                }
            case V2.version:
                let v2 = try decoder.decode(path: self.path, fileSystem: self.fileSystem, as: V2.self)
                return try v2.pins.map{ try PinsStore.Pin($0, mirrors: mirrors) }.reduce(into: [PackageIdentity: PinsStore.Pin]()) { partial, iterator in
                    if partial.keys.contains(iterator.packageRef.identity) {
                        throw StringError("duplicated entry for package \"\(iterator.packageRef.identity)\"")
                    }
                    partial[iterator.packageRef.identity] = iterator
                }
            default:
                throw InternalError("unknown RepositoryManager version: \(version)")
            }
        }
    }

    func save(pins: PinsStore.PinsMap, mirrors: DependencyMirrors, removeIfEmpty: Bool) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory)
        }
        try self.fileSystem.withLock(on: self.lockFilePath, type: .exclusive) {
            // Remove the pins file if there are zero pins to save.
            //
            // This can happen if all dependencies are path-based or edited
            // dependencies.
            if removeIfEmpty && pins.isEmpty {
                try self.fileSystem.removeFileTree(self.path)
                return
            }

            let container = V2(pins: pins, mirrors: mirrors)
            let data = try self.encoder.encode(container)
            try self.fileSystem.writeFileContents(self.path, data: data)
        }
    }

    func reset() throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            return
        }
        try self.fileSystem.withLock(on: self.lockFilePath, type: .exclusive) {
            try self.fileSystem.removeFileTree(self.path)
        }
    }

    // version reader
    struct Version: Codable {
        let version: Int
    }

    // v1 storage format
    struct V1: Codable {
        static let version = 1

        let version: Int
        let object: Container

        init (pins: PinsStore.PinsMap, mirrors: DependencyMirrors) {
            self.version = Self.version
            self.object = .init(
                pins: pins.values
                    .sorted(by: { $0.packageRef.identity < $1.packageRef.identity })
                    .map{ Pin($0, mirrors: mirrors) }
            )
        }

        struct Container: Codable {
            var pins: [Pin]
        }

        struct Pin: Codable {
            let package: String?
            let repositoryURL: String
            let state: CheckoutInfo

            init(_ pin: PinsStore.Pin, mirrors: DependencyMirrors) {
                self.package = pin.packageRef.name
                // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
                self.repositoryURL = mirrors.originalURL(for: pin.packageRef.location) ?? pin.packageRef.location
                self.state = .init(pin.state)
            }
        }
    }

    // v2 storage format
    struct V2: Codable {
        static let version = 2

        let version: Int
        let pins: [Pin]

        init (pins: PinsStore.PinsMap, mirrors: DependencyMirrors) {
            self.version = Self.version
            self.pins = pins.values
                .sorted(by: { $0.packageRef.identity < $1.packageRef.identity })
                .map{ Pin($0, mirrors: mirrors) }
        }

        struct Pin: Codable {
            let identity: PackageIdentity
            let location: String
            let state: CheckoutInfo

            init(_ pin: PinsStore.Pin, mirrors: DependencyMirrors) {
                self.identity = pin.packageRef.identity
                // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
                self.location = mirrors.originalURL(for: pin.packageRef.location) ?? pin.packageRef.location
                self.state = .init(pin.state)
            }
        }
    }

    struct CheckoutInfo: Codable {
        let revision: String
        let branch: String?
        let version: String?

        init(_ state: CheckoutState) {
            switch state {
            case .version(let version, let revision):
                self.version = version.description
                self.branch = nil
                self.revision = revision.identifier
            case .branch(let branch, let revision):
                self.version = nil
                self.branch = branch
                self.revision = revision.identifier
            case .revision(let revision):
                self.version = nil
                self.branch = nil
                self.revision = revision.identifier
            }
        }
    }
}

extension PinsStore.Pin {
    fileprivate init(_ pin: PinsStorage.V1.Pin, mirrors: DependencyMirrors) throws {
        // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
        let url = mirrors.effectiveURL(for: pin.repositoryURL)
        let identity = PackageIdentity(url: url) // FIXME: pin store should also encode identity
        var packageRef = PackageReference.remote(identity: identity, location: url)
        if let newName = pin.package {
            packageRef = packageRef.with(newName: newName)
        }
        self.init(
            packageRef: packageRef,
            state: try .init(pin.state)
        )
    }
}

extension PinsStore.Pin {
    fileprivate init(_ pin: PinsStorage.V2.Pin, mirrors: DependencyMirrors) throws {
        // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
        let url = mirrors.effectiveURL(for: pin.location)
        let identity = pin.identity
        let packageRef = PackageReference.remote(identity: identity, location: url)
        self.init(
            packageRef: packageRef,
            state: try .init(pin.state)
        )
    }
}

extension CheckoutState {
    fileprivate init(_ state: PinsStorage.CheckoutInfo) throws {
        let revision: Revision = .init(identifier: state.revision)
        if let branch = state.branch {
            self = .branch(name: branch, revision: revision)
        } else if let version = state.version {
            self = try .version(Version(versionString: version), revision: revision)
        } else {
            self = .revision(revision)
        }
    }
}
