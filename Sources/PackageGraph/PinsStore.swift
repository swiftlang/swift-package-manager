//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
import TSCBasic

import struct TSCUtility.Version

public final class PinsStore {
    public typealias PinsMap = [PackageIdentity: PinsStore.Pin]

    public struct Pin: Equatable {
        /// The package reference of the pinned dependency.
        public let packageRef: PackageReference

        /// The pinned state.
        public let state: PinState

        public init(packageRef: PackageReference, state: PinState) {
            self.packageRef = packageRef
            self.state = state
        }
    }

    public enum PinState: Equatable, CustomStringConvertible {
        case branch(name: String, revision: String)
        case version(_ version: Version, revision: String?)
        case revision(_ revision: String)

        public var description: String {
            switch self {
            case .version(let version, _):
                return version.description
            case .branch(let name, _):
                return name
            case .revision(let revision):
                return revision
            }
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
        AnySequence<Pin>(self.pinsMap.values)
    }

    /// Create a new pins store.
    ///
    /// - Parameters:
    ///   - pinsFile: Path to the pins file.
    ///   - fileSystem: The filesystem to manage the pin file on.
    public init(
        pinsFile: AbsolutePath,
        workingDirectory: AbsolutePath,
        fileSystem: FileSystem,
        mirrors: DependencyMirrors
    ) throws {
        self.storage = .init(path: pinsFile, workingDirectory: workingDirectory, fileSystem: fileSystem)
        self.mirrors = mirrors

        do {
            self._pins = .init(try self.storage.load(mirrors: mirrors))
        } catch {
            self._pins = .init()
            throw StringError(
                "Package.resolved file is corrupted or malformed; fix or delete the file to continue: \(error)"
            )
        }
    }

    /// Pin a repository at a version.
    ///
    /// This method does not automatically write to state file.
    ///
    /// - Parameters:
    ///   - packageRef: The package reference to pin.
    ///   - state: The state to pin at.
    public func pin(packageRef: PackageReference, state: PinState) {
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

    /// Remove a pin.
    ///
    /// This will replace any previous pin with same package name.
    public func remove(_ pin: Pin) {
        self._pins[pin.packageRef.identity] = nil
    }

    /// Unpin all of the currently pinned dependencies.
    ///
    /// This method does not automatically write to state file.
    public func unpinAll() {
        // Reset the pins map.
        self._pins.clear()
    }

    public func saveState(toolsVersion: ToolsVersion) throws {
        try self.storage.save(
            pins: self._pins.get(),
            mirrors: self.mirrors,
            removeIfEmpty: true,
            toolsVersion: toolsVersion
        )
    }

    // for testing
    public func schemeVersion() throws -> Int {
        try self.storage.schemeVersion()
    }
}

// MARK: - Serialization

private struct PinsStorage {
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
                return try v1.object.pins.map { try PinsStore.Pin($0, mirrors: mirrors) }
                    .reduce(into: [PackageIdentity: PinsStore.Pin]()) { partial, iterator in
                        if partial.keys.contains(iterator.packageRef.identity) {
                            throw StringError("duplicated entry for package \"\(iterator.packageRef.identity)\"")
                        }
                        partial[iterator.packageRef.identity] = iterator
                    }
            case V2.version:
                let v2 = try decoder.decode(path: self.path, fileSystem: self.fileSystem, as: V2.self)
                return try v2.pins.map { try PinsStore.Pin($0, mirrors: mirrors) }
                    .reduce(into: [PackageIdentity: PinsStore.Pin]()) { partial, iterator in
                        if partial.keys.contains(iterator.packageRef.identity) {
                            throw StringError("duplicated entry for package \"\(iterator.packageRef.identity)\"")
                        }
                        partial[iterator.packageRef.identity] = iterator
                    }
            default:
                throw StringError("unknown 'PinsStorage' version '\(version.version)' at '\(self.path)'.")
            }
        }
    }

    func save(
        pins: PinsStore.PinsMap,
        mirrors: DependencyMirrors,
        removeIfEmpty: Bool,
        toolsVersion: ToolsVersion
    ) throws {
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

            var data: Data
            if toolsVersion >= .v5_6 {
                let container = try V2(pins: pins, mirrors: mirrors)
                data = try self.encoder.encode(container)
            } else {
                let container = try V1(pins: pins, mirrors: mirrors)
                let json = container.toLegacyJSON()
                let bytes = json.toBytes(prettyPrint: true)
                data = Data(bytes.contents)
            }
            #if !os(Windows)
            // rdar://83646952: add newline for POSIXy systems
            if data.last != 0x0A {
                data.append(0x0A)
            }
            #endif
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

    // for testing
    func schemeVersion() throws -> Int {
        try self.decoder.decode(path: self.path, fileSystem: self.fileSystem, as: Version.self).version
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

        init(pins: PinsStore.PinsMap, mirrors: DependencyMirrors) throws {
            self.version = Self.version
            self.object = try .init(
                pins: pins.values
                    .sorted(by: { $0.packageRef.identity < $1.packageRef.identity })
                    .map { try Pin($0, mirrors: mirrors) }
            )
        }

        // backwards compatibility of JSON format
        func toLegacyJSON() -> JSON {
            .init([
                "version": self.version.toJSON(),
                "object": self.object.toLegacyJSON(),
            ])
        }

        struct Container: Codable {
            var pins: [Pin]

            // backwards compatibility of JSON format
            func toLegacyJSON() -> JSON {
                .init([
                    "pins": self.pins.map { $0.toLegacyJSON() },
                ])
            }
        }

        struct Pin: Codable {
            let package: String?
            let repositoryURL: String
            let state: State

            init(_ pin: PinsStore.Pin, mirrors: DependencyMirrors) throws {
                let location: String
                switch pin.packageRef.kind {
                case .localSourceControl(let path):
                    location = path.pathString
                case .remoteSourceControl(let url):
                    location = url.absoluteString
                default:
                    throw StringError("invalid package type \(pin.packageRef.kind)")
                }

                self.package = pin.packageRef.deprecatedName
                // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
                self.repositoryURL = mirrors.original(for: location) ?? location
                self.state = try .init(pin.state)
            }

            // backwards compatibility of JSON format
            func toLegacyJSON() -> JSON {
                .init([
                    "package": self.package.toJSON(),
                    "repositoryURL": self.repositoryURL.toJSON(),
                    "state": self.state.toLegacyJSON(),
                ])
            }
        }

        struct State: Codable {
            let revision: String
            let branch: String?
            let version: String?

            init(_ state: PinsStore.PinState) throws {
                switch state {
                case .version(let version, let revision) where revision != nil:
                    self.version = version.description
                    self.branch = nil
                    self.revision = revision! // nil guarded above in case
                case .branch(let branch, let revision):
                    self.version = nil
                    self.branch = branch
                    self.revision = revision
                case .revision(let revision):
                    self.version = nil
                    self.branch = nil
                    self.revision = revision
                default:
                    throw StringError("invalid pin state: \(state)")
                }
            }

            // backwards compatibility of JSON format
            func toLegacyJSON() -> JSON {
                .init([
                    "revision": self.revision.toJSON(),
                    "version": self.version.toJSON(),
                    "branch": self.branch.toJSON(),
                ])
            }
        }
    }

    // v2 storage format
    struct V2: Codable {
        static let version = 2

        let version: Int
        let pins: [Pin]

        init(pins: PinsStore.PinsMap, mirrors: DependencyMirrors) throws {
            self.version = Self.version
            self.pins = try pins.values
                .sorted(by: { $0.packageRef.identity < $1.packageRef.identity })
                .map { try Pin($0, mirrors: mirrors) }
        }

        struct Pin: Codable {
            let identity: PackageIdentity
            let kind: Kind
            let location: String
            let state: State

            init(_ pin: PinsStore.Pin, mirrors: DependencyMirrors) throws {
                let kind: Kind
                let location: String
                switch pin.packageRef.kind {
                case .localSourceControl(let path):
                    kind = .localSourceControl
                    location = path.pathString
                case .remoteSourceControl(let url):
                    kind = .remoteSourceControl
                    location = url.absoluteString
                case .registry:
                    kind = .registry
                    location = "" // FIXME: this is likely not correct
                default:
                    throw StringError("invalid package type \(pin.packageRef.kind)")
                }

                self.identity = pin.packageRef.identity
                self.kind = kind
                // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
                self.location = mirrors.original(for: location) ?? location
                self.state = .init(pin.state)
            }
        }

        enum Kind: String, Codable {
            case localSourceControl
            case remoteSourceControl
            case registry
        }

        struct State: Codable {
            let version: String?
            let branch: String?
            let revision: String?

            init(_ state: PinsStore.PinState) {
                switch state {
                case .version(let version, let revision):
                    self.version = version.description
                    self.branch = nil
                    self.revision = revision
                case .branch(let branch, let revision):
                    self.version = nil
                    self.branch = branch
                    self.revision = revision
                case .revision(let revision):
                    self.version = nil
                    self.branch = nil
                    self.revision = revision
                }
            }
        }
    }
}

extension PinsStore.Pin {
    fileprivate init(_ pin: PinsStorage.V1.Pin, mirrors: DependencyMirrors) throws {
        // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
        let location = mirrors.effective(for: pin.repositoryURL)
        let identity = PackageIdentity(urlString: location) // FIXME: pin store should also encode identity
        var packageRef: PackageReference
        if let path = try? AbsolutePath(validating: location) {
            packageRef = .localSourceControl(identity: identity, path: path)
        } else if let url = URL(string: location) {
            packageRef = .remoteSourceControl(identity: identity, url: url)
        } else {
            throw StringError("invalid package location \(location)")
        }
        if let newName = pin.package {
            packageRef = packageRef.withName(newName)
        }
        self.init(
            packageRef: packageRef,
            state: try .init(pin.state)
        )
    }
}

extension PinsStore.PinState {
    fileprivate init(_ state: PinsStorage.V1.State) throws {
        let revision = state.revision
        if let version = state.version {
            self = try .version(Version(versionString: version), revision: revision)
        } else if let branch = state.branch {
            self = .branch(name: branch, revision: revision)
        } else {
            self = .revision(revision)
        }
    }
}

extension PinsStore.Pin {
    fileprivate init(_ pin: PinsStorage.V2.Pin, mirrors: DependencyMirrors) throws {
        let packageRef: PackageReference
        let identity = pin.identity
        // rdar://52529014, rdar://52529011: pin file should store the original location but remap when loading
        let location = mirrors.effective(for: pin.location)
        switch pin.kind {
        case .localSourceControl:
            packageRef = try .localSourceControl(identity: identity, path: AbsolutePath(validating: location))
        case .remoteSourceControl:
            guard let url = URL(string: location) else {
                throw StringError("invalid url location: \(location)")
            }
            packageRef = .remoteSourceControl(identity: identity, url: url)
        case .registry:
            packageRef = .registry(identity: identity)
        }
        self.init(
            packageRef: packageRef,
            state: try .init(pin.state)
        )
    }
}

extension PinsStore.PinState {
    fileprivate init(_ state: PinsStorage.V2.State) throws {
        if let version = state.version {
            self = try .version(Version(versionString: version), revision: state.revision)
        } else if let branch = state.branch, let revision = state.revision {
            self = .branch(name: branch, revision: revision)
        } else if let revision = state.revision {
            self = .revision(revision)
        } else {
            throw StringError("invalid pin state: \(state)")
        }
    }
}
