//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import TSCBasic

extension Workspace {
    /// A downloaded prebuilt managed by the workspace.
    public struct ManagedPrebuilt {
        /// The package reference.
        public let packageRef: PackageReference

        /// The name of the binary target the artifact corresponds to.
        public let libraryName: String

        /// The path to the extracted prebuilt artifacts
        public let path: Basics.AbsolutePath

        /// The products in the library
        public let products: [String]

        /// The C modules that need their includes directory added to the include path
        public let cModules: [String]
    }
}

extension Workspace.ManagedPrebuilt: CustomStringConvertible {
    public var description: String {
        return "<ManagedArtifact: \(self.packageRef.identity).\(self.libraryName)>"
    }
}

// MARK: - ManagedArtifacts

extension Workspace {
    /// A collection of managed artifacts which have been downloaded.
    public final class ManagedPrebuilts {
        /// A mapping from package identity, to target name, to ManagedArtifact.
        private var artifactMap: [PackageIdentity: [String: ManagedPrebuilt]]

        internal var artifacts: AnyCollection<ManagedPrebuilt> {
            AnyCollection(self.artifactMap.values.lazy.flatMap{ $0.values })
        }

        init() {
            self.artifactMap = [:]
        }

        init(_ artifacts: [ManagedPrebuilt]) throws {
            let artifactsByPackagePath = Dictionary(grouping: artifacts, by: { $0.packageRef.identity })
            self.artifactMap = try artifactsByPackagePath.mapValues{ artifacts in
                try Dictionary(artifacts.map { ($0.libraryName, $0) }, uniquingKeysWith: { _, _ in
                    // should be unique
                    throw StringError("binary artifact already exists in managed artifacts")
                })
            }
        }

        public subscript(packageIdentity packageIdentity: PackageIdentity, targetName targetName: String) -> ManagedPrebuilt? {
            self.artifactMap[packageIdentity]?[targetName]
        }

        public func add(_ artifact: ManagedPrebuilt) {
            self.artifactMap[artifact.packageRef.identity, default: [:]][artifact.libraryName] = artifact
        }

        public func remove(packageIdentity: PackageIdentity, targetName: String) {
            self.artifactMap[packageIdentity]?[targetName] = nil
        }
    }
}

extension Workspace.ManagedPrebuilts: Collection {
    public var startIndex: AnyIndex {
        self.artifacts.startIndex
    }

    public var endIndex: AnyIndex {
        self.artifacts.endIndex
    }

    public subscript(index: AnyIndex) -> Workspace.ManagedPrebuilt {
        self.artifacts[index]
    }

    public func index(after index: AnyIndex) -> AnyIndex {
        self.artifacts.index(after: index)
    }
}

extension Workspace.ManagedPrebuilts: CustomStringConvertible {
    public var description: String {
        "<ManagedArtifacts: \(Array(self.artifacts))>"
    }
}
