/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCTestSupport

import TSCUtility

final class PlatformTests: XCTestCase {
    func testFindCurrentPlatformDebian() {
        let fs = InMemoryFileSystem(files: ["/etc/debian_version": "xxx"])
        XCTAssertEqual(Platform.linux(.debian), Platform._findCurrentPlatformLinux(fs))
    }

    func testFindCurrentPlatformAndroid() {
        var fs = InMemoryFileSystem(files: ["/system/bin/toolbox": "xxx"])
        XCTAssertEqual(Platform.android, Platform._findCurrentPlatformLinux(fs))

        fs = InMemoryFileSystem(files: ["/system/bin/toybox": "xxx"])
        XCTAssertEqual(Platform.android, Platform._findCurrentPlatformLinux(fs))
    }

    func testFindCurrentPlatformFedora() {
        var fs = InMemoryFileSystem(files: ["/etc/fedora-release": "xxx"])
        XCTAssertEqual(Platform.linux(.fedora), Platform._findCurrentPlatformLinux(fs))

        fs = InMemoryFileSystem(files: ["/etc/redhat-release": "xxx"])
        XCTAssertEqual(Platform.linux(.fedora), Platform._findCurrentPlatformLinux(fs))

        fs = InMemoryFileSystem(files: ["/etc/centos-release": "xxx"])
        XCTAssertEqual(Platform.linux(.fedora), Platform._findCurrentPlatformLinux(fs))

        fs = InMemoryFileSystem(files: ["/etc/system-release": "Amazon Linux release 2 (Karoo)"])
        XCTAssertEqual(Platform.linux(.fedora), Platform._findCurrentPlatformLinux(fs))
    }
}
