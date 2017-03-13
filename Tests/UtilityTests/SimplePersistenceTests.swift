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
            statePath: AbsolutePath.root.appending(component: "state.json")
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

class SimplePersistenceTests: XCTestCase {
    func testBasics() throws {
        let fs = InMemoryFileSystem()
        let stateFile = AbsolutePath.root.appending(component: "state.json")
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
        } catch SimplePersistence.Error.invalidSchemaVersion(let v){
            XCTAssertEqual(v, 2)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
