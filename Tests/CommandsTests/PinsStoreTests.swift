/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import struct Utility.Version
import TestSupport
@testable import Commands

final class PinsStoreTests: XCTestCase {

    let v1: Version = "1.0.0"

    func testBasics() throws {
        let foo = "foo"
        let bar = "bar"

        let pin = PinsStore.Pin(package: foo, version: v1, reason: "bad")
        // We should be able to round trip from JSON.
        XCTAssertEqual(PinsStore.Pin(json: pin.toJSON()), pin)
        
        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")
        var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        // Pins file should not be created right now.
        XCTAssert(!fs.exists(pinsFile))
        XCTAssert(store.pins.map{$0}.isEmpty)

        try store.pin(package: foo, at: v1, reason: "bad")
        XCTAssert(fs.exists(pinsFile))

        // Load the store again from disk.
        let store2 = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        // Test basics on the store.
        for s in [store, store2] {
            XCTAssert(s.pins.map{$0}.count == 1)
            XCTAssertEqual(s.pinsMap[bar], nil)
            let fooPin = s.pinsMap[foo]!
            XCTAssertEqual(fooPin.package, foo)
            XCTAssertEqual(fooPin.version, v1)
            XCTAssertEqual(fooPin.reason, "bad")
        }
        
        // We should be able to pin again.
        try store.pin(package: foo, at: v1)
        try store.pin(package: foo, at: "1.0.2")

        XCTAssertThrows(PinOperationError.notPinned) {
            try store.unpin(package: bar)
        }

        try store.pin(package: bar, at: v1)
        XCTAssert(store.pins.map{$0}.count == 2)
        try store.unpin(package: foo)
        try store.unpin(package: bar)
        XCTAssert(store.pins.map{$0}.isEmpty)
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
