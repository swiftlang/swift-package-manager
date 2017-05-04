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

extension SimplePersistence.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidSchemaVersion(version):
            return "Unsupported schema version (\(version))"

        case let .restoreFailure(stateFile, error):
            return "Unable to restore state from \(stateFile.asString). \(error)"
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

    @discardableResult
    public func restoreState(_ object: SimplePersistanceProtocol) throws -> Bool {
        do {
            return try _restoreState(object)
        } catch {
            throw Error.restoreFailure(stateFile: statePath, error: error)
        }
    }

    private func _restoreState(_ object: SimplePersistanceProtocol) throws -> Bool {
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

        // FIXME: This should write atomically.
        try fileSystem.writeFileContents(
            statePath, bytes: JSON(json).toBytes(prettyPrint: self.prettyPrint))
    }
}
