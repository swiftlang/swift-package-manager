/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import SourceControl
import Workspace

final class SwiftPMConfigTests: XCTestCase {
    func testLoadingSchema1() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/.swiftpm/config")

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try fs.writeFileContents(configFile) {
            $0 <<< """
                {
                  "object": [
                    {
                      "mirror": "\(mirrorURL)",
                      "original": "\(originalURL)"
                    }
                  ],
                  "version": 1
                }
                """
        }

        let mirrors = try SwiftPMConfig(path: configFile, fs: fs)

        XCTAssertEqual(mirrors.getMirror(forURL: "https://github.com/apple/swift-argument-parser.git"), "https://github.com/mona/swift-argument-parser.git")
    }

    func testThrowsMirrorNotFound() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/.swiftpm/config")
        let mirrors = try SwiftPMConfig(path: configFile, fs: fs)

        XCTAssertThrows(SwiftPMConfig.Error.mirrorNotFound) {
            try mirrors.unset(originalOrMirrorURL: "https://github.com/apple/swift-argument-parser.git")
        }
    }

    func testEmptyMirrors() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/.swiftpm/config")
        let mirrors = try SwiftPMConfig(path: configFile, fs: fs)

        try mirrors.saveState()
        XCTAssertFalse(fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"
        mirrors.set(mirrorURL: mirrorURL, forURL: originalURL)

        XCTAssertFalse(fs.exists(configFile))

        try mirrors.saveState()
        XCTAssertTrue(fs.exists(configFile))

        try mirrors.unset(originalOrMirrorURL: originalURL)

        XCTAssertTrue(fs.exists(configFile))

        try mirrors.saveState()
        XCTAssertFalse(fs.exists(configFile))
    }
}
