/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// A protocol which needs to be implemented by the objects which can be
/// persisted using SimplePersistence
public protocol SimplePersistanceProtocol: class, JSONSerializable {
    /// Restores state from the given json object.
    func restore(from json: JSON) throws
}

/// A simple persistence helper.
///
/// This class can be used to save and restore state of objects in simple JSON
/// format. Note: This class is not thread safe.
public final class SimplePersistence {
    /// Describes a SimplePersistence errors.
    public enum Error: Swift.Error {
        case invalidSchemaVersion(Int)
    }

    /// The fileSystem to operate on.
    private var fileSystem: FileSystem

    /// The schema of the state file.
    private let schemaVersion: Int

    /// The path at which we persist the state.
    private let statePath: AbsolutePath

    /// Writes the state files with pretty print JSON.
    private let prettyPrint: Bool

    public init(
        fileSystem: FileSystem,
        schemaVersion: Int,
        statePath: AbsolutePath,
        prettyPrint: Bool = false
    ) {
        self.fileSystem = fileSystem
        self.schemaVersion = schemaVersion
        self.statePath = statePath
        self.prettyPrint = prettyPrint
    }

    public func restoreState(_ object: SimplePersistanceProtocol) throws -> Bool {
        // If the state doesn't exist, don't try to load and fail.
        if !fileSystem.exists(statePath) {
            return false
        }
        // Load the state.
        let json = try JSON(bytes: try fileSystem.readFileContents(statePath))
        // Check the schema version.
        let version: Int = try json.get("version")
        guard version  == schemaVersion else {
            throw Error.invalidSchemaVersion(version)
        }
        // Restore the state.
        try object.restore(from: json.get("object"))
        return true
    }

    public func saveState(_ object: SimplePersistanceProtocol) throws {
        let data = JSON([
            "version": self.schemaVersion,
            "object": object
        ])
        // FIXME: This should write atomically.
        try fileSystem.writeFileContents(
            statePath, bytes: data.toBytes(prettyPrint: self.prettyPrint))
    }
}
