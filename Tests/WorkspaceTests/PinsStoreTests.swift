/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import struct Utility.Version
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

        let pin = PinsStore.Pin(package: foo, repository: fooRepo, revision: revision, version: v1, reason: "bad")
        // We should be able to round trip from JSON.
        XCTAssertEqual(PinsStore.Pin(json: pin.toJSON()), pin)
        
        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")
        var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        // Pins file should not be created right now.
        XCTAssert(!fs.exists(pinsFile))
        XCTAssert(store.pins.map{$0}.isEmpty)
        XCTAssert(store.autoPin)

        try store.pin(package: foo, repository: fooRepo, revision: revision, version: v1, reason: "bad")
        XCTAssert(fs.exists(pinsFile))

        // Test autopin toggle and persistence.
        do {
            var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
            XCTAssert(store.autoPin)
            try store.setAutoPin(on: false)
            XCTAssertFalse(store.autoPin)
        }
        do {
            var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
            XCTAssertFalse(store.autoPin)
            try store.setAutoPin(on: true)
            XCTAssert(store.autoPin)
        }
        do {
            let store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
            XCTAssert(store.autoPin)
        }

        // Load the store again from disk.
        let store2 = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        XCTAssert(store2.autoPin)
        // Test basics on the store.
        for s in [store, store2] {
            XCTAssert(s.pins.map{$0}.count == 1)
            XCTAssertEqual(s.pinsMap[bar], nil)
            let fooPin = s.pinsMap[foo]!
            XCTAssertEqual(fooPin.package, foo)
            XCTAssertEqual(fooPin.version, v1)
            XCTAssertEqual(fooPin.revision, revision)
            XCTAssertEqual(fooPin.reason, "bad")
            XCTAssertEqual(fooPin.description, v1.description)
        }
        
        // We should be able to pin again.
        try store.pin(package: foo, repository: fooRepo, revision: revision, version: v1)
        try store.pin(package: foo, repository: fooRepo, revision: revision, version: "1.0.2")

        XCTAssertThrows(PinOperationError.autoPinEnabled) {
            try store.unpin(package: bar)
        }

        XCTAssertThrows(PinOperationError.notPinned) {
            try store.setAutoPin(on: false)
            try store.unpin(package: bar)
        }

        try store.pin(package: bar, repository: barRepo, revision: revision, version: v1)
        XCTAssert(store.pins.map{$0}.count == 2)
        try store.unpin(package: foo)
        try store.unpin(package: bar)
        XCTAssert(store.pins.map{$0}.isEmpty)

        // Test branch pin.
        do {
            try store.pin(package: bar, repository: barRepo, revision: revision, branch: "develop")
            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.branch, "develop")
            XCTAssertEqual(barPin.version, nil)
            XCTAssertEqual(barPin.revision, revision)
            XCTAssertEqual(barPin.description, "develop")
        }

        // Test revision pin.
        do {
            try store.pin(package: bar, repository: barRepo, revision: revision)
            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.branch, nil)
            XCTAssertEqual(barPin.version, nil)
            XCTAssertEqual(barPin.revision, revision)
            XCTAssertEqual(barPin.description, revision.identifier)
        }
    }

    func testLoadingV1() throws {
      // Disabled until we get migration support: https://bugs.swift.org/browse/SR-4098
      #if false
        let pinsFile = AbsolutePath("/pinsfile.txt")
        let fs = InMemoryFileSystem()
        let contents =
            "{"                                                         + "\n" +
            "  \"autoPin\": true,"                                      + "\n" +
            "  \"pins\": ["                                             + "\n" +
            "    {"                                                     + "\n" +
            "      \"package\": \"bam\","                               + "\n" +
            "      \"reason\": null,"                                   + "\n" +
            "      \"repositoryURL\": \"/private/tmp/BigPackage/bam\"," + "\n" +
            "      \"version\": \"1.0.0\""                              + "\n" +
            "    },"                                                    + "\n" +
            "    {"                                                     + "\n" +
            "      \"package\": \"bar\","                               + "\n" +
            "      \"reason\": null,"                                   + "\n" +
            "      \"repositoryURL\": \"/private/tmp/BigPackage/bar\"," + "\n" +
            "      \"version\": \"1.0.0\""                              + "\n" +
            "    },"                                                    + "\n" +
            "    {"                                                     + "\n" +
            "      \"package\": \"baz\","                               + "\n" +
            "      \"reason\": null,"                                   + "\n" +
            "      \"repositoryURL\": \"/private/tmp/BigPackage/baz\"," + "\n" +
            "      \"version\": \"1.0.0\""                              + "\n" +
            "    }"                                                     + "\n" +
            "  ],"                                                      + "\n" +
            "  \"version\": 1"                                          + "\n" +
            "}"
        try fs.writeFileContents(pinsFile, bytes: ByteString(encodingAsUTF8: contents))
        let store = try PinsStore(pinsFile: pinsFile, fileSystem: fs)
        XCTAssertEqual(store.autoPin, true)
        XCTAssertEqual(store.pins.map {$0.package}.sorted() , ["bam", "bar", "baz"])
      #endif
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testLoadingV1", testLoadingV1),
    ]
}
