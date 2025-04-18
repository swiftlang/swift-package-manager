//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageGraph
import PackageModel
import SourceControl
import TSCBasic

import struct TSCUtility.Version

extension Workspace {
    /// An individual managed dependency.
    ///
    /// Each dependency will have a checkout containing the sources at a
    /// particular revision, and may have an associated version.
    public struct ManagedDependency: Equatable {
        /// Represents the state of the managed dependency.
        public indirect enum State: Equatable, CustomStringConvertible {
            /// The dependency is a local package on the file system.
            case fileSystem(Basics.AbsolutePath)

            /// The dependency is a managed source control checkout.
            case sourceControlCheckout(CheckoutState)

            /// The dependency is downloaded from a registry.
            case registryDownload(version: Version)

            /// The dependency is in edited state.
            ///
            /// If the path is non-nil, the dependency is managed by a user and is
            /// located at the path. In other words, this dependency is being used
            /// for top of the tree style development.
            case edited(basedOn: ManagedDependency?, unmanagedPath: Basics.AbsolutePath?)

            case custom(version: Version, path: Basics.AbsolutePath)

            public var description: String {
                switch self {
                case .fileSystem(let path):
                    return "fileSystem (\(path))"
                case .sourceControlCheckout(let checkoutState):
                    return "sourceControlCheckout (\(checkoutState))"
                case .registryDownload(let version):
                    return "registryDownload (\(version))"
                case .edited:
                    return "edited"
                case .custom:
                    return "custom"
                }
            }
        }

        /// The package reference.
        public let packageRef: PackageReference

        /// The state of the managed dependency.
        public let state: State

        /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
        public let subpath: Basics.RelativePath

        internal init(
            packageRef: PackageReference,
            state: State,
            subpath: Basics.RelativePath
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
        public func edited(subpath: Basics.RelativePath, unmanagedPath: Basics.AbsolutePath?) throws -> ManagedDependency {
            guard case .sourceControlCheckout =  self.state else {
                throw InternalError("invalid dependency state: \(self.state)")
            }
            return ManagedDependency(
                packageRef: self.packageRef,
                state: .edited(basedOn: self, unmanagedPath: unmanagedPath),
                subpath: subpath
            )
        }

        /// Create a dependency present locally on the filesystem.
        public static func fileSystem(
            packageRef: PackageReference
        ) throws -> ManagedDependency {
            switch packageRef.kind {
            case .root(let path), .fileSystem(let path), .localSourceControl(let path):
                return try ManagedDependency(
                    packageRef: packageRef,
                    state: .fileSystem(path),
                    // FIXME: This is just a fake entry, we should fix it.
                    subpath: RelativePath(validating: packageRef.identity.description)
                )
            default:
                throw InternalError("invalid package type: \(packageRef.kind)")
            }
        }

        /// Create a source control dependency checked out
        public static func sourceControlCheckout(
            packageRef: PackageReference,
            state: CheckoutState,
            subpath: Basics.RelativePath
        ) throws -> ManagedDependency {
            switch packageRef.kind {
            case .localSourceControl, .remoteSourceControl:
                return ManagedDependency(
                    packageRef: packageRef,
                    state: .sourceControlCheckout(state),
                    subpath: subpath
                )
            default:
                throw InternalError("invalid package type: \(packageRef.kind)")
            }
        }

        /// Create a registry dependency downloaded
        public static func registryDownload(
            packageRef: PackageReference,
            version: Version,
            subpath: Basics.RelativePath
        ) throws -> ManagedDependency {
            guard case .registry = packageRef.kind else {
                throw InternalError("invalid package type: \(packageRef.kind)")
            }
            return ManagedDependency(
                packageRef: packageRef,
                state: .registryDownload(version: version),
                subpath: subpath
            )
        }

        /// Create an edited dependency
        public static func edited(
            packageRef: PackageReference,
            subpath: Basics.RelativePath,
            basedOn: ManagedDependency?,
            unmanagedPath: Basics.AbsolutePath?
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
        return "<ManagedDependency: \(self.packageRef.identity) \(self.state)>"
    }
}

// MARK: - ManagedDependencies

extension Workspace {
    /// A collection of managed dependencies.
    public struct ManagedDependencies {
        private var dependencies: [PackageIdentity: ManagedDependency]

        init() {
            self.dependencies = [:]
        }
        
        private init(
            _ dependencies: [PackageIdentity: ManagedDependency]
        ) {
            self.dependencies = dependencies
        }

        init(_ dependencies: [ManagedDependency]) throws {
            // rdar://86857825 do not use Dictionary(uniqueKeysWithValues:) as it can crash the process when input is incorrect such as in older versions of SwiftPM
            self.dependencies = [:]
            for dependency in dependencies {
                if self.dependencies[dependency.packageRef.identity] != nil {
                    throw StringError("\(dependency.packageRef.identity) already exists in managed dependencies")
                }
                self.dependencies[dependency.packageRef.identity] = dependency
            }
        }

        public subscript(identity: PackageIdentity) -> ManagedDependency? {
            return self.dependencies[identity]
        }

        // When loading manifests in Workspace, there are cases where we must also compare the location
        // as it may attempt to load manifests for dependencies that have the same identity but from a different location
        // (e.g. dependency is changed to a fork with the same identity)
        public subscript(comparingLocation package: PackageReference) -> ManagedDependency? {
            if let dependency = self.dependencies[package.identity], dependency.packageRef.equalsIncludingLocation(package) {
                return dependency
            }
            return .none
        }

        public func add(_ dependency: ManagedDependency) -> Self {
            var dependencies = dependencies
            dependencies[dependency.packageRef.identity] = dependency
            return ManagedDependencies(dependencies)
        }

        public func remove(_ identity: PackageIdentity) -> Self {
            var dependencies = dependencies
            dependencies[identity] = nil
            return ManagedDependencies(dependencies)
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
