/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageGraph
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

extension Workspace {
    /// An individual managed dependency.
    ///
    /// Each dependency will have a checkout containing the sources at a
    /// particular revision, and may have an associated version.
    public struct ManagedDependency: Equatable {
        /// Represents the state of the managed dependency.
        public indirect enum State: Equatable {
            /// The dependency is a managed checkout.
            case checkout(CheckoutState)

            /// The dependency is in edited state.
            ///
            /// If the path is non-nil, the dependency is managed by a user and is
            /// located at the path. In other words, this dependency is being used
            /// for top of the tree style development.
            case edited(basedOn: ManagedDependency?, unmanagedPath: AbsolutePath?)

            // The dependency is a local package.
            case local(AbsolutePath)
        }

        /// The package reference.
        public let packageRef: PackageReference

        /// The state of the managed dependency.
        public let state: State

        /// Returns true if state is checkout.
        var isCheckout: Bool {
            if case .checkout = self.state { return true }
            return false
        }

        /// Returns true if the dependency is edited.
        public var isEdited: Bool {
            if case .edited = self.state { return true }
            return false
        }

        /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
        public let subpath: RelativePath

        internal init(
            packageRef: PackageReference,
            state: State,
            subpath: RelativePath
        ) {
            self.packageRef = packageRef
            self.subpath = subpath
            self.state = state
        }

        /// Create an editable managed dependency based on a dependency which
        /// was *not* in edit state.
        ///
        /// - Parameters:
        ///     - subpath: The subpath inside the editable directory.
        ///     - unmanagedPath: A custom absolute path instead of the subpath.
        public func edited(subpath: RelativePath, unmanagedPath: AbsolutePath?) -> ManagedDependency {
            return .edited(packageRef: self.packageRef, subpath: subpath, basedOn: self, unmanagedPath: unmanagedPath)
        }

        /// Create a dependency present locally on the filesystem.
        public static func local(
            packageRef: PackageReference
        ) throws -> ManagedDependency {
            switch packageRef.kind {
            case .root(let path),
                    .fileSystem(let path),
                    .localSourceControl(let path):
                return ManagedDependency(
                    packageRef: packageRef,
                    state: .local(path),
                    // FIXME: This is just a fake entry, we should fix it.
                    subpath: RelativePath(packageRef.identity.description)
                )
            default:
                throw InternalError("invalid package type: \(packageRef.kind)")
            }
        }

        /// Create a remote dependency checked out
        public static func remote(
            packageRef: PackageReference,
            state: CheckoutState,
            subpath: RelativePath
        ) -> ManagedDependency {
            return ManagedDependency(
                packageRef: packageRef,
                state: .checkout(state),
                subpath: subpath
            )
        }

        /// Create an edited dependency
        public static func edited(
            packageRef: PackageReference,
            subpath: RelativePath,
            basedOn: ManagedDependency?,
            unmanagedPath: AbsolutePath?
        ) -> ManagedDependency {
            return ManagedDependency(
                packageRef: packageRef,
                state: .edited(basedOn: basedOn, unmanagedPath: unmanagedPath),
                subpath: subpath
            )
        }
    }
}

extension Workspace.ManagedDependency: CustomStringConvertible {
    public var description: String {
        return "<ManagedDependency: \(self.packageRef.name) \(self.state)>"
    }
}

// MARK: - ManagedDependencies

extension Workspace {
    /// A collection of managed dependencies.
    final public class ManagedDependencies {
        // FIXME: this should be identity based
        private var dependencies: [PackageIdentity: ManagedDependency]

        init(_ dependencies: [ManagedDependency] = []) {
            self.dependencies = Dictionary(uniqueKeysWithValues: dependencies.map{ ($0.packageRef.identity, $0) })
        }

        public subscript(identity: PackageIdentity) -> ManagedDependency? {
            return self.dependencies[identity]
        }

        // When loading manifests in Workspace, there are cases where we must also compare the location
        // as it may attempt to load manifests for dependencies that have the same identity but from a different location
        // (e.g. dependency is changed to  a fork with the same identity)
        public subscript(comparingLocation package: PackageReference) -> ManagedDependency? {
            if let dependency = self.dependencies[package.identity], dependency.packageRef.equalsIncludingLocation(package) {
                return dependency
            }
            return .none
        }

        public func add(_ dependency: ManagedDependency) {
            self.dependencies[dependency.packageRef.identity] = dependency
        }

        public func remove(_ identity: PackageIdentity) {
            self.dependencies[identity] = nil
        }
    }
}

extension Workspace.ManagedDependencies: Collection {
    public typealias Index = Dictionary<PackageIdentity, Workspace.ManagedDependency>.Index
    public typealias Element = Workspace.ManagedDependency

    public var startIndex: Index {
        self.dependencies.startIndex
    }

    public var endIndex: Index {
        self.dependencies.endIndex
    }

    public subscript(index: Index) -> Element {
        self.dependencies[index].value
    }

    public func index(after index: Index) -> Index {
        self.dependencies.index(after: index)
    }
}

extension Workspace.ManagedDependencies: CustomStringConvertible {
    public var description: String {
        "<ManagedDependencies: \(Array(self.dependencies.values))>"
    }
}
