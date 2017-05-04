/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility
import TestSupport
import SourceControl
@testable import Workspace

final class PinsStoreTests: XCTestCase {

    let v1: Version = "1.0.0"

    func testBasics() throws {
        let foo = "foo"
        let bar = "bar"
        let fooRepo = RepositorySpecifier(url: "/foo")
        let barRepo = RepositorySpecifier(url: "/bar")
        let revision = Revision(identifier: "81513c8fd220cf1ed1452b98060cd80d3725c5b7")

        let state = CheckoutState(revision: revision, version: v1)
        let pin = PinsStore.Pin(package: foo, repository: fooRepo, state: state)
        // We should be able to round trip from JSON.
        XCTAssertEqual(try PinsStore.Pin(json: pin.toJSON()), pin)
        
        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")
        var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        // Pins file should not be created right now.
        XCTAssert(!fs.exists(pinsFile))
        XCTAssert(store.pins.map{$0}.isEmpty)

        store.pin(package: foo, repository: fooRepo, state: state)
        try store.saveState()

        XCTAssert(fs.exists(pinsFile))

        // Load the store again from disk.
        let store2 = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        // Test basics on the store.
        for s in [store, store2] {
            XCTAssert(s.pins.map{$0}.count == 1)
            XCTAssertEqual(s.pinsMap[bar], nil)
            let fooPin = s.pinsMap[foo]!
            XCTAssertEqual(fooPin.package, foo)
            XCTAssertEqual(fooPin.state.version, v1)
            XCTAssertEqual(fooPin.state.revision, revision)
            XCTAssertEqual(fooPin.state.description, v1.description)
        }
        
        // We should be able to pin again.
        store.pin(package: foo, repository: fooRepo, state: state)
        store.pin(package: foo, repository: fooRepo, state: CheckoutState(revision: revision, version: "1.0.2"))
        store.pin(package: bar, repository: barRepo, state: state)
        try store.saveState()

        store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        XCTAssert(store.pins.map{$0}.count == 2)

        // Test branch pin.
        do {
            store.pin(package: bar, repository: barRepo, state: CheckoutState(revision: revision, branch: "develop"))
            try store.saveState()
            store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)

            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.state.branch, "develop")
            XCTAssertEqual(barPin.state.version, nil)
            XCTAssertEqual(barPin.state.revision, revision)
            XCTAssertEqual(barPin.state.description, "develop")
        }

        // Test revision pin.
        do {
            store.pin(package: bar, repository: barRepo, state: CheckoutState(revision: revision))
            try store.saveState()
            store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)

            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.state.branch, nil)
            XCTAssertEqual(barPin.state.version, nil)
            XCTAssertEqual(barPin.state.revision, revision)
            XCTAssertEqual(barPin.state.description, revision.identifier)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
