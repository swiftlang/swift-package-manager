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

import struct TSCUtility.Version
import struct TSCBasic.StringError

import Basics
import PackageModel

extension Workspace {
    /// A downloaded prebuilt managed by the workspace.
    public struct ManagedPrebuilt {
        /// The package identity
        public let identity: PackageIdentity

        /// The package version
        public let version: Version

        /// The name of the binary target the artifact corresponds to.
        public let libraryName: String

        /// The path to the extracted prebuilt artifacts
        public let path: AbsolutePath

        /// The path to the checked out source
        public let checkoutPath: AbsolutePath?

        /// The products in the library
        public let products: [String]

        /// The include path for the C modules
        public let includePath: [RelativePath]?

        /// The C modules that need their includes directory added to the include path
        public let cModules: [String]
    }
}

extension Workspace.ManagedPrebuilt: CustomStringConvertible {
    public var description: String {
        return "<ManagedArtifact: \(self.identity).\(self.libraryName)>"
    }
}

// MARK: - ManagedArtifacts

extension Workspace {
    /// A collection of managed artifacts which have been downloaded.
    public final class ManagedPrebuilts {
        /// A mapping from package identity, to target name, to ManagedArtifact.
        private var prebuiltMap: [PackageIdentity: [String: ManagedPrebuilt]]

        internal var prebuilts: AnyCollection<ManagedPrebuilt> {
            AnyCollection(self.prebuiltMap.values.lazy.flatMap{ $0.values })
        }

        init() {
            self.prebuiltMap = [:]
        }

        init(_ prebuilts: [ManagedPrebuilt]) throws {
            let prebuiltsByPackagePath = Dictionary(grouping: prebuilts, by: { $0.identity })
            self.prebuiltMap = try prebuiltsByPackagePath.mapValues{ prebuilt in
                try Dictionary(prebuilt.map { ($0.libraryName, $0) }, uniquingKeysWith: { _, _ in
                    // should be unique
                    throw StringError("prebuilt already exists in managed prebuilts")
                })
            }
        }

        public subscript(packageIdentity packageIdentity: PackageIdentity, targetName targetName: String) -> ManagedPrebuilt? {
            self.prebuiltMap[packageIdentity]?[targetName]
        }

        public func add(_ prebuilt: ManagedPrebuilt) {
            self.prebuiltMap[prebuilt.identity, default: [:]][prebuilt.libraryName] = prebuilt
        }

        public func remove(packageIdentity: PackageIdentity, targetName: String) {
            self.prebuiltMap[packageIdentity]?[targetName] = nil
        }
    }
}

extension Workspace.ManagedPrebuilts: Collection {
    public var startIndex: AnyIndex {
        self.prebuilts.startIndex
    }

    public var endIndex: AnyIndex {
        self.prebuilts.endIndex
    }

    public subscript(index: AnyIndex) -> Workspace.ManagedPrebuilt {
        self.prebuilts[index]
    }

    public func index(after index: AnyIndex) -> AnyIndex {
        self.prebuilts.index(after: index)
    }
}

extension Workspace.ManagedPrebuilts: CustomStringConvertible {
    public var description: String {
        "<ManagedArtifacts: \(Array(self.prebuilts))>"
    }
}
