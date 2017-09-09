/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import Basic
import TestSupport

import Utility

fileprivate class Foo: SimplePersistanceProtocol {
    var int: Int
    var path: AbsolutePath
    let persistence: SimplePersistence

    init(int: Int, path: AbsolutePath, fileSystem: FileSystem) {
        self.int = int
        self.path = path
        self.persistence = SimplePersistence(
            fileSystem: fileSystem,
            schemaVersion: 1,
            statePath: AbsolutePath.root.appending(components: "subdir", "state.json")
        )
    }

    func restore(from json: JSON) throws {
        self.int = try json.get("int")
        self.path = try AbsolutePath(json.get("path"))
    }

    func toJSON() -> JSON {
        return JSON([
            "int": int,
            "path": path,
        ])
    }

    func save() throws {
        try persistence.saveState(self)
    }

    func restore() throws -> Bool {
        return try persistence.restoreState(self)
    }
}

fileprivate enum Bar {
    class V1: SimplePersistanceProtocol {
        var int: Int
        let persistence: SimplePersistence

        init(int: Int, fileSystem: FileSystem) {
            self.int = int
            self.persistence = SimplePersistence(
                fileSystem: fileSystem,
                schemaVersion: 1,
                statePath: AbsolutePath.root.appending(components: "subdir", "state.json")
            )
        }

        func restore(from json: JSON) throws {
            self.int = try json.get("int")
        }

        func toJSON() -> JSON {
            return JSON([
                "int": int,
            ])
        }
    }

    class V2: SimplePersistanceProtocol {
        var int: Int
        var string: String
        let persistence: SimplePersistence

        init(int: Int, string: String, fileSystem: FileSystem) {
            self.int = int
            self.string = string
            self.persistence = SimplePersistence(
                fileSystem: fileSystem,
                schemaVersion: 1,
                statePath: AbsolutePath.root.appending(components: "subdir", "state.json")
            )
        }

        func restore(from json: JSON) throws {
            self.int = try json.get("int")
            self.string = try json.get("string")
        }

        func toJSON() -> JSON {
            return JSON([
                "int": int,
                "string": string
            ])
        }
    }
}

class SimplePersistenceTests: XCTestCase {
    func testBasics() throws {
        let fs = InMemoryFileSystem()
        let stateFile = AbsolutePath.root.appending(components: "subdir", "state.json")
        let foo = Foo(int: 1, path: AbsolutePath("/hello"), fileSystem: fs)
        // Restoring right now should return false because state is not present.
        XCTAssertFalse(try foo.restore())

        // Save and check saved data.
        try foo.save()
        let json = try JSON(bytes: fs.readFileContents(stateFile))
        XCTAssertEqual(1, try json.get("version"))
        XCTAssertEqual(foo.toJSON(), try json.get("object"))

        // Modify local state and restore.
        foo.int = 5
        XCTAssertTrue(try foo.restore())
        XCTAssertEqual(foo.int, 1)
        XCTAssertEqual(foo.path, AbsolutePath("/hello"))

        // Modify state's schema version.
        let newJSON = JSON(["version": 2])
        try fs.writeFileContents(stateFile, bytes: newJSON.toBytes())

        do {
            _ = try foo.restore()
            XCTFail()
        } catch {
            let error = String(describing: error)
            XCTAssert(error.contains("unsupported schema version 2"), error)
        }
    }

    func testBackwardsCompatibleStateFile() throws {
        // Test that we don't overwrite the json in case we find keys we don't need.

        let fs = InMemoryFileSystem()
        let stateFile = AbsolutePath.root.appending(components: "subdir", "state.json")

        // Create and save v2 object.
        let v2 = Bar.V2(int: 100, string: "hello", fileSystem: fs)
        try v2.persistence.saveState(v2)

        // Restore v1 object from v2 file.
        let v1 = Bar.V1(int: 1, fileSystem: fs)
        XCTAssertEqual(v1.int, 1)
        XCTAssertTrue(try v1.persistence.restoreState(v1))
        XCTAssertEqual(v1.int, 100)

        // Check state file still has the old "string" key.
        let json = try JSON(bytes: fs.readFileContents(stateFile))
        XCTAssertEqual("hello", try json.get("object").get("string"))

        // Update a value in v1 object and save.
        v1.int = 500
        try v1.persistence.saveState(v1)

        v2.string = ""
        // Now restore v2 and expect string to be present as well as the updated int value.
        XCTAssertTrue(try v2.persistence.restoreState(v2))
        XCTAssertEqual(v2.int, 500)
        XCTAssertEqual(v2.string, "hello")
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testBackwardsCompatibleStateFile", testBackwardsCompatibleStateFile),
    ]
}
