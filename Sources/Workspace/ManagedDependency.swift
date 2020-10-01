/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility

/// An individual managed dependency.
///
/// Each dependency will have a checkout containing the sources at a
/// particular revision, and may have an associated version.
public final class ManagedDependency {

    /// Represents the state of the managed dependency.
    public enum State: Equatable {

        /// The dependency is a managed checkout.
        case checkout(CheckoutState)

        /// The dependency is in edited state.
        ///
        /// If the path is non-nil, the dependency is managed by a user and is
        /// located at the path. In other words, this dependency is being used
        /// for top of the tree style development.
        case edited(AbsolutePath?)

        // The dependency is a local package.
        case local

        /// Returns true if state is checkout.
        var isCheckout: Bool {
            if case .checkout = self { return true }
            return false
        }
    }

    /// The package reference.
    public let packageRef: PackageReference

    /// The state of the managed dependency.
    public let state: State

    /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
    public let subpath: RelativePath

    /// A dependency which in editable state is based on a dependency from
    /// which it edited from.
    ///
    /// This information is useful so it can be restored when users
    /// unedit a package.
    public internal(set) var basedOn: ManagedDependency?

    public init(
        packageRef: PackageReference,
        subpath: RelativePath,
        checkoutState: CheckoutState
    ) {
        self.packageRef = packageRef
        self.state = .checkout(checkoutState)
        self.basedOn = nil
        self.subpath = subpath
    }

    /// Create a dependency present locally on the filesystem.
    public static func local(
        packageRef: PackageReference
    ) -> ManagedDependency {
        return ManagedDependency(
            packageRef: packageRef,
            state: .local,
            // FIXME: This is just a fake entry, we should fix it.
            subpath: RelativePath(packageRef.identity),
            basedOn: nil
        )
    }

    private init(
        packageRef: PackageReference,
        state: State,
        subpath: RelativePath,
        basedOn: ManagedDependency?
    ) {
        self.packageRef = packageRef
        self.subpath = subpath
        self.basedOn = basedOn
        self.state = state
    }

    private init(
        basedOn dependency: ManagedDependency,
        subpath: RelativePath,
        unmanagedPath: AbsolutePath?
    ) {
        assert(dependency.state.isCheckout)
        self.basedOn = dependency
        self.packageRef = dependency.packageRef
        self.subpath = subpath
        self.state = .edited(unmanagedPath)
    }

    /// Create an editable managed dependency based on a dependency which
    /// was *not* in edit state.
    ///
    /// - Parameters:
    ///     - subpath: The subpath inside the editables directory.
    ///     - unmanagedPath: A custom absolute path instead of the subpath.
    public func editedDependency(subpath: RelativePath, unmanagedPath: AbsolutePath?) -> ManagedDependency {
        return ManagedDependency(basedOn: self, subpath: subpath, unmanagedPath: unmanagedPath)
    }

    /// Returns true if the dependency is edited.
    public var isEdited: Bool {
        switch state {
        case .checkout, .local:
            return false
        case .edited:
            return true
        }
    }
}

// MARK: - JSON

extension ManagedDependency: JSONMappable, JSONSerializable, CustomStringConvertible {
    public convenience init(json: JSON) throws {
        try self.init(
            packageRef: json.get("packageRef"),
            state: json.get("state"),
            subpath: RelativePath(json.get("subpath")),
            basedOn: json.get("basedOn")
        )
    }

    public func toJSON() -> JSON {
        return .init([
            "packageRef": packageRef.toJSON(),
            "subpath": subpath,
            "basedOn": basedOn.toJSON(),
            "state": state
        ])
    }

    public var description: String {
        return "<ManagedDependency: \(packageRef.name) \(state)>"
    }
}


extension ManagedDependency.State: JSONMappable, JSONSerializable {
    public func toJSON() -> JSON {
        switch self {
        case .checkout(let checkoutState):
            return .init([
                "name": "checkout",
                "checkoutState": checkoutState,
            ])
        case .edited(let path):
            return .init([
                "name": "edited",
                "path": path.toJSON(),
            ])
        case .local:
            return .init([
                "name": "local",
            ])
        }
    }

    public init(json: JSON) throws {
        let name: String = try json.get("name")
        switch name {
        case "checkout":
            self = try .checkout(json.get("checkoutState"))
        case "edited":
            let path: String? = json.get("path")
            self = .edited(path.map({AbsolutePath($0)}))
        case "local":
            self = .local
        default:
            throw JSON.MapError.custom(key: nil, message: "Invalid state \(name)")
        }
    }

    public var description: String {
        switch self {
        case .checkout(let checkout):
            return "\(checkout)"
        case .edited:
            return "edited"
        case .local:
            return "local"
        }
    }
}
