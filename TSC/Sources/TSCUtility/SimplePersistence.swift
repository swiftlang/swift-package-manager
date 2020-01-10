/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// A protocol which needs to be implemented by the objects which can be
/// persisted using SimplePersistence
public protocol SimplePersistanceProtocol: class, JSONSerializable {
    /// Restores state from the given json object.
    func restore(from json: JSON) throws

    /// Restores state from the given json object and supported schema version.
    func restore(from json: JSON, supportedSchemaVersion: Int) throws
}

public extension SimplePersistanceProtocol {
    func restore(from json: JSON, supportedSchemaVersion: Int) throws {}
}

extension SimplePersistence.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidSchemaVersion(version):
            return "unsupported schema version \(version)"

        case let .restoreFailure(stateFile, error):
            return "unable to restore state from \(stateFile); \(error)"
        }
    }
}

/// A simple persistence helper.
///
/// This class can be used to save and restore state of objects in simple JSON
/// format. Note: This class is not thread safe.
public final class SimplePersistence {
    /// Describes a SimplePersistence errors.
    public enum Error: Swift.Error {
        case invalidSchemaVersion(Int)

        case restoreFailure(stateFile: AbsolutePath, error: Swift.Error)
    }

    /// The fileSystem to operate on.
    private let fileSystem: FileSystem

    /// The schema of the state file.
    private let schemaVersion: Int

    /// The schema versions, besides the current schema, that are supported for restoring.
    private let supportedSchemaVersions: Set<Int>

    /// The path at which we persist the state.
    private let statePath: AbsolutePath

    /// The list of paths to search for restore if no state was found at statePath.
    private let otherStatePaths: [AbsolutePath]

    /// Writes the state files with pretty print JSON.
    private let prettyPrint: Bool

    public init(
        fileSystem: FileSystem,
        schemaVersion: Int,
        supportedSchemaVersions: Set<Int> = [],
        statePath: AbsolutePath,
        otherStatePaths: [AbsolutePath] = [],
        prettyPrint: Bool = false
    ) {
        assert(!supportedSchemaVersions.contains(schemaVersion), "Supported schema versions should not include the current schema")
        self.fileSystem = fileSystem
        self.schemaVersion = schemaVersion
        self.supportedSchemaVersions = supportedSchemaVersions
        self.statePath = statePath
        self.otherStatePaths = otherStatePaths
        self.prettyPrint = prettyPrint
    }

    @discardableResult
    public func restoreState(_ object: SimplePersistanceProtocol) throws -> Bool {
        do {
            return try _restoreState(object)
        } catch {
            throw Error.restoreFailure(stateFile: statePath, error: error)
        }
    }

    private func _restoreState(_ object: SimplePersistanceProtocol) throws -> Bool {
        guard let path = findStatePath() else {
            return false
        }
        // Load the state.
        let json = try JSON(bytes: try fileSystem.readFileContents(path))
        // Get the schema version.
        let version: Int = try json.get("version")

        // Restore the state based on the provided schema version.
        switch version {
        case schemaVersion:
            try object.restore(from: json.get("object"))

        case _ where supportedSchemaVersions.contains(version):
            try object.restore(from: json.get("object"), supportedSchemaVersion: version)

        default:
            throw Error.invalidSchemaVersion(version)
        }

        // If we loaded an old file path, migrate to the new one.
        if path != statePath {
            try fileSystem.move(from: path, to: statePath)
        }

        return true
    }

    /// Merges the two given json if they both are dictionaries.
    ///
    /// In case of collisions, keep the value from new dictionary.
    private func merge(old: JSON?, new: JSON) -> JSON {
        guard case let .dictionary(oldDict)? = old,
              case var .dictionary(newDict) = new else {
            return new
        }

        // Merge the dictionaries, keeping new values in case of collisions.
        for (key, value) in oldDict where newDict[key] == nil {
            newDict[key] = value
        }

        return JSON(newDict)
    }

    public func saveState(_ object: SimplePersistanceProtocol) throws {
        var json = [String: JSON]()

        // Load the current data.
        let jsonData = try? JSON(bytes: fileSystem.readFileContents(statePath))
        if case let .dictionary(dict)? = jsonData {
            json = dict
        }

        // Set the schema version.
        json["version"] = self.schemaVersion.toJSON()

        // Set the object, keeping any keys in object which we don't know about.
        json["object"] = merge(old: json["object"], new: object.toJSON())

        try fileSystem.createDirectory(statePath.parentDirectory, recursive: true)
        // FIXME: This should write atomically.
        try fileSystem.writeFileContents(
            statePath, bytes: JSON(json).toBytes(prettyPrint: self.prettyPrint))
    }

    /// Returns true if the state file exists on the filesystem.
    public func stateFileExists() -> Bool {
        return findStatePath() != nil
    }

    private func findStatePath() -> AbsolutePath? {
        // Return the first path that exists.
        let allPaths = [statePath] + otherStatePaths
        let path = allPaths.first(where: { fileSystem.exists($0) })
        return path
    }
}
