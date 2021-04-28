/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import PackageModel
import PackageGraph
import SPMTestSupport
import SourceControl
import Workspace

final class PinsStoreTests: XCTestCase {

    let v1: Version = "1.0.0"

    func testBasics() throws {
        let fooPath = AbsolutePath("/foo")
        let barPath = AbsolutePath("/bar")
        let foo = PackageIdentity(path: fooPath)
        let bar = PackageIdentity(path: barPath)
        let fooRepo = RepositorySpecifier(url: fooPath.pathString)
        let barRepo = RepositorySpecifier(url: barPath.pathString)
        let revision = Revision(identifier: "81513c8fd220cf1ed1452b98060cd80d3725c5b7")
        let fooRef = PackageReference.remote(identity: foo, location: fooRepo.url)
        let barRef = PackageReference.remote(identity: bar, location: barRepo.url)

        let state = CheckoutState(revision: revision, version: v1)
        let pin = PinsStore.Pin(packageRef: fooRef, state: state)
        // We should be able to round trip from JSON.
        XCTAssertEqual(try PinsStore.Pin(json: pin.toJSON()), pin)

        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")
        var store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())
        // Pins file should not be created right now.
        XCTAssert(!fs.exists(pinsFile))
        XCTAssert(store.pins.map{$0}.isEmpty)

        store.pin(packageRef: fooRef, state: state)
        try store.saveState()

        XCTAssert(fs.exists(pinsFile))

        // Load the store again from disk.
        let store2 = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())
        // Test basics on the store.
        for s in [store, store2] {
            XCTAssert(s.pins.map{$0}.count == 1)
            XCTAssertEqual(s.pinsMap[bar], nil)
            let fooPin = s.pinsMap[foo]!
            XCTAssertEqual(fooPin.packageRef, fooRef)
            XCTAssertEqual(fooPin.state.version, v1)
            XCTAssertEqual(fooPin.state.revision, revision)
            XCTAssertEqual(fooPin.state.description, v1.description)
        }

        // We should be able to pin again.
        store.pin(packageRef: fooRef, state: state)
        store.pin(
            packageRef: fooRef,
            state: CheckoutState(revision: revision, version: "1.0.2")
        )
        store.pin(packageRef: barRef, state: state)
        try store.saveState()

        store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())
        XCTAssert(store.pins.map{$0}.count == 2)

        // Test branch pin.
        do {
            store.pin(
                packageRef: barRef,
                state: CheckoutState(revision: revision, branch: "develop")
            )
            try store.saveState()
            store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())

            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.state.branch, "develop")
            XCTAssertEqual(barPin.state.version, nil)
            XCTAssertEqual(barPin.state.revision, revision)
            XCTAssertEqual(barPin.state.description, "develop")
        }

        // Test revision pin.
        do {
            store.pin(packageRef: barRef, state: CheckoutState(revision: revision))
            try store.saveState()
            store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())

            let barPin = store.pinsMap[bar]!
            XCTAssertEqual(barPin.state.branch, nil)
            XCTAssertEqual(barPin.state.version, nil)
            XCTAssertEqual(barPin.state.revision, revision)
            XCTAssertEqual(barPin.state.description, revision.identifier)
        }
    }

    func testLoadingSchema1() throws {
        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")

        try fs.writeFileContents(pinsFile) {
            $0 <<< """
                {
                  "object": {
                    "pins": [
                      {
                        "package": "Clang_C",
                        "repositoryURL": "https://github.com/something/Clang_C.git",
                        "state": {
                          "branch": null,
                          "revision": "90a9574276f0fd17f02f58979423c3fd4d73b59e",
                          "version": "1.0.2",
                        }
                      },
                      {
                        "package": "Commandant",
                        "repositoryURL": "https://github.com/something/Commandant.git",
                        "state": {
                          "branch": null,
                          "revision": "c281992c31c3f41c48b5036c5a38185eaec32626",
                          "version": "0.12.0"
                        }
                      }
                    ]
                  },
                  "version": 1
                }
                """
        }

        let store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())
        XCTAssertEqual(store.pinsMap.keys.map { $0.description }.sorted(), ["clang_c", "commandant"])
    }

    func testEmptyPins() throws {
        let fs = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pinsfile.txt")
        let store = try PinsStore(pinsFile: pinsFile, fileSystem: fs, mirrors: .init())

        try store.saveState()
        XCTAssertFalse(fs.exists(pinsFile))

        let fooPath = AbsolutePath("/foo")
        let foo = PackageIdentity(path: fooPath)
        let fooRef = PackageReference.remote(identity: foo, location: fooPath.pathString)
        let revision = Revision(identifier: "81513c8fd220cf1ed1452b98060cd80d3725c5b7")
        store.pin(packageRef: fooRef, state: CheckoutState(revision: revision, version: v1))

        XCTAssert(!fs.exists(pinsFile))

        try store.saveState()
        XCTAssert(fs.exists(pinsFile))

        store.unpinAll()
        try store.saveState()
        XCTAssertFalse(fs.exists(pinsFile))
    }

    func testPinsWithMirrors() throws {
        let fooURL = "https://github.com/corporate/foo.git"
        let fooIdentity = PackageIdentity(url: fooURL)
        let fooMirroredURL = "https://github.corporate.com/team/foo.git"

        let barURL = "https://github.com/corporate/baraka.git"
        let barIdentity = PackageIdentity(url: barURL)
        let barMirroredURL = "https://github.corporate.com/team/bar.git"
        let barMirroredIdentity = PackageIdentity(url: barMirroredURL)

        let bazURL = "https://github.com/cool/baz.git"
        let bazIdentity = PackageIdentity(url: bazURL)

        let mirrors = DependencyMirrors()
        mirrors.set(mirrorURL: fooMirroredURL, forURL: fooURL)
        mirrors.set(mirrorURL: barMirroredURL, forURL: barURL)

        let fileSystem = InMemoryFileSystem()
        let pinsFile = AbsolutePath("/pins.txt")

        let store = try PinsStore(pinsFile: pinsFile, fileSystem: fileSystem, mirrors: mirrors)

        store.pin(packageRef: .remote(identity: fooIdentity, location: fooMirroredURL),
                  state: CheckoutState(revision: .init(identifier: "foo-revision"), version: v1))
        store.pin(packageRef: .remote(identity: barMirroredIdentity, location: barMirroredURL),
                  state: CheckoutState(revision: .init(identifier: "bar-revision"), version: v1))
        store.pin(packageRef: .remote(identity: bazIdentity, location: bazURL),
                  state: CheckoutState(revision: .init(identifier: "baz-revision"), version: v1))


        try store.saveState()
        XCTAssert(fileSystem.exists(pinsFile))

        // Load the store again from disk, with no mirrors
        let store2 = try PinsStore(pinsFile: pinsFile, fileSystem: fileSystem, mirrors: .init())
        XCTAssert(store2.pinsMap.count == 3)
        XCTAssertEqual(store2.pinsMap[fooIdentity]!.packageRef.location, fooURL)
        XCTAssertEqual(store2.pinsMap[barIdentity]!.packageRef.location, barURL)
        XCTAssertEqual(store2.pinsMap[bazIdentity]!.packageRef.location, bazURL)

        // Load the store again from disk, with mirrors
        let store3 = try PinsStore(pinsFile: pinsFile, fileSystem: fileSystem, mirrors: mirrors)
        XCTAssert(store3.pinsMap.count == 3)
        XCTAssertEqual(store3.pinsMap[fooIdentity]!.packageRef.location, fooMirroredURL)
        XCTAssertEqual(store3.pinsMap[barMirroredIdentity]!.packageRef.location, barMirroredURL)
        XCTAssertEqual(store3.pinsMap[bazIdentity]!.packageRef.location, bazURL)
    }
}
