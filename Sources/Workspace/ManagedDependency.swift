/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageGraph
import SourceControl
import Utility

/// An individual managed dependency.
///
/// Each dependency will have a checkout containing the sources at a
/// particular revision, and may have an associated version.
public final class ManagedDependency: JSONMappable, JSONSerializable {

    /// Represents the state of the managed dependency.
    public enum State: Equatable {

        /// The dependency is a managed checkout.
        case checkout(CheckoutState)

        /// The dependency is in edited state.
        case edited

        /// The dependency is managed by a user and is located at the path.
        /// 
        /// In other words, this dependency is being used for top of the
        /// tree style development.
        case unmanaged(path: AbsolutePath)

        /// Returns true if state is checkout.
        var isCheckout: Bool {
            if case .checkout = self { return true }
            return false
        }
    }

    /// The specifier for the dependency.
    public let repository: RepositorySpecifier

    /// The state of the managed dependency.
    public let state: State

    /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
    public let subpath: RelativePath

    /// A dependency which in editable state is based on a dependency from
    /// which it edited from.
    ///
    /// This information is useful so it can be restored when users 
    /// unedit a package.
    let basedOn: ManagedDependency?

    init(
        repository: RepositorySpecifier,
        subpath: RelativePath,
        checkoutState: CheckoutState
    ) {
        self.repository = repository
        self.state = .checkout(checkoutState)
        self.basedOn = nil
        self.subpath = subpath
    }

    private init(basedOn dependency: ManagedDependency, subpath: RelativePath, state: State) {
        assert(dependency.state.isCheckout)
        assert(!state.isCheckout)
        self.basedOn = dependency
        self.repository = dependency.repository
        self.subpath = subpath
        self.state = state
    }

    /// Create an editable managed dependency based on a dependency which
    /// was *not* in edit state.
    func makingEditable(subpath: RelativePath, state: State) -> ManagedDependency {
        return ManagedDependency(basedOn: self, subpath: subpath, state: state)
    }

    public init(json: JSON) throws {
        self.repository = try json.get("repositoryURL")
        self.subpath = try RelativePath(json.get("subpath"))
        self.basedOn = json.get("basedOn")
        self.state = try json.get("state")
    }

    public func toJSON() -> JSON {
        return .init([
            "repositoryURL": repository.url,
            "subpath": subpath.asString,
            "basedOn": basedOn.toJSON(),
            "state": state,
        ])
    }
}

extension ManagedDependency.State: JSONMappable, JSONSerializable {

    public static func ==(lhs: ManagedDependency.State, rhs: ManagedDependency.State) -> Bool {
        switch (lhs, rhs) {
        case (.checkout(let lhs), .checkout(let rhs)):
            return lhs == rhs
        case (.checkout, _):
            return false
        case (.edited, .edited):
            return true
        case (.edited, _):
            return false
        case (.unmanaged(let lhs), .unmanaged(let rhs)):
            return lhs == rhs
        case (.unmanaged, _):
            return false
        }
    }

    public func toJSON() -> JSON {
        switch self {
        case .checkout(let checkoutState):
            return .init([
                "name": "checkout",
                "checkoutState": checkoutState
            ])
        case .edited:
            return .init([
                "name": "edited",
            ])
        case .unmanaged(let path):
            return .init([
                "name": "unmanaged",
                "path": path,
            ])
        }
    }

    public init(json: JSON) throws {
        let name: String = try json.get("name")
        switch name {
        case "checkout":
            self = try .checkout(json.get("checkoutState"))
        case "edited":
            self = .edited
        case "unmanaged":
            self = try .unmanaged(path: AbsolutePath(json.get("path")))
        default:
            throw JSON.MapError.custom(key: nil, message: "Invalid state \(name)")
        }
    }
}

/// Represents a collection of managed dependency which are persisted on disk.
public final class ManagedDependencies: SimplePersistanceProtocol {

    /// The current state of managed dependencies.
    private var dependencyMap: [RepositorySpecifier: ManagedDependency]

    /// Path to the state file.
    let statePath: AbsolutePath

    /// persistence helper
    let persistence: SimplePersistence

    init(dataPath: AbsolutePath, fileSystem: FileSystem) throws {
        let statePath = dataPath.appending(component: "dependencies-state.json")

        self.dependencyMap = [:]
        self.statePath = statePath
        self.persistence = SimplePersistence(
            fileSystem: fileSystem,
            schemaVersion: 1,
            statePath: statePath)

        // Load the state from disk, if possible.
        if try !self.persistence.restoreState(self) {
            var fileSystem = fileSystem
            try fileSystem.createDirectory(dataPath, recursive: true)
            // There was no state, write the default state immediately.
            try self.persistence.saveState(self)
        }
    }

    public subscript(_ url: String) -> ManagedDependency? {
        return dependencyMap[RepositorySpecifier(url: url)]
    }

    public subscript(_ repository: RepositorySpecifier) -> ManagedDependency? {
        get {
            return dependencyMap[repository]
        }
        set {
            dependencyMap[repository] = newValue
        }
    }

    func reset() {
        dependencyMap = [:]
    }

    func saveState() throws {
        try self.persistence.saveState(self)
    }

    public var values: AnySequence<ManagedDependency> {
        return AnySequence<ManagedDependency>(dependencyMap.values)
    }

    public func restore(from json: JSON) throws {
        self.dependencyMap = try Dictionary(items: 
            json.get("dependencies").map{($0.repository, $0)}
        )
    }

    public func toJSON() -> JSON {
        return JSON([
            "dependencies": values.toJSON(),
        ])
    }
}
