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

/// A downloaded artifact managed by the workspace.
public final class ManagedArtifact {

    /// Represents the source of the artifact.
    public enum Source: Equatable {

        /// Represents a remote artifact, with the url it was downloaded from, its checksum, and its path relative to
        /// the workspace artifacts path.
        case remote(url: String, checksum: String, subpath: RelativePath)

        /// Represents a locally available artifact, with its path relative to its package.
        case local(path: String)
    }

    /// The package reference.
    public let packageRef: PackageReference

    /// The name of the binary target the artifact corresponds to.
    public let targetName: String

    /// The source of the artifact (local or remote).
    public let source: Source

    public init(
        packageRef: PackageReference,
        targetName: String,
        source: Source
    ) {
        self.packageRef = packageRef
        self.targetName = targetName
        self.source = source
    }

    /// Create an artifact downloaded from a remote url.
    public static func remote(
        packageRef: PackageReference,
        targetName: String,
        url: String,
        checksum: String,
        subpath: RelativePath
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .remote(url: url, checksum: checksum, subpath: subpath)
        )
    }

    /// Create an artifact present locally on the filesystem.
    public static func local(
        packageRef: PackageReference,
        targetName: String,
        path: String
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .local(path: path)
        )
    }
}

// MARK: - JSON

extension ManagedArtifact: JSONMappable, JSONSerializable, CustomStringConvertible {
    public convenience init(json: JSON) throws {
        try self.init(
            packageRef: json.get("packageRef"),
            targetName: json.get("targetName"),
            source: json.get("source")
        )
    }

    public func toJSON() -> JSON {
        return .init([
            "packageRef": packageRef,
            "targetName": targetName,
            "source": source,
        ])
    }

    public var description: String {
        return "<ManagedArtifact: \(packageRef.name).\(targetName) \(source)>"
    }
}

extension ManagedArtifact.Source: JSONMappable, JSONSerializable, CustomStringConvertible {
    public init(json: JSON) throws {
        let type: String = try json.get("type")
        switch type {
        case "local":
            self = try .local(path: json.get("path"))
        case "remote":
            let url: String = try json.get("url")
            let checksum: String = try json.get("checksum")
            let subpath = try RelativePath(json.get("subpath"))
            self = .remote(url: url, checksum: checksum, subpath: subpath)
        default:
            throw JSON.MapError.custom(key: nil, message: "Invalid type \(type)")
        }
    }

    public func toJSON() -> JSON {
        switch self {
        case .local(let path):
            return .init([
                "type": "local",
                "path": path,
            ])
        case .remote(let url, let checksum, let subpath):
            return .init([
                "type": "remote",
                "url": url,
                "checksum": checksum,
                "subpath": subpath.toJSON(),
            ])
        }
    }

    public var description: String {
        switch self {
        case .local(let path):
            return "local(path: \(path))"
        case .remote(let url, let checksum, let subpath):
            return "remote(url: \(url), checksum: \(checksum), subpath: \(subpath))"
        }
    }
}
