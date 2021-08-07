/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Configurations
import SPMTestSupport
import Workspace
import TSCBasic
import TSCUtility
import XCTest

// FIXME: move to new ConfigurationsTests module
final class MirrorsConfigurationTests: XCTestCase {
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

        let configuration = Configuration.Mirrors(fileSystem: fs, path: configFile)

        XCTAssertEqual(configuration.mirrorURL(for: "https://github.com/apple/swift-argument-parser.git"), "https://github.com/mona/swift-argument-parser.git")
        XCTAssertEqual(configuration.originalURL(for: "https://github.com/mona/swift-argument-parser.git"), "https://github.com/apple/swift-argument-parser.git")
    }

    func testThrowsMirrorNotFound() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/.swiftpm/config")
        let configuration = Configuration.Mirrors(fileSystem: fs, path: configFile)

        XCTAssertThrows(StringError("Mirror not found: 'https://github.com/apple/swift-argument-parser.git'")) {
            try configuration.withMapping { mapping  in
                try mapping.unset(originalOrMirrorURL: "https://github.com/apple/swift-argument-parser.git")
            }
        }
    }

    func testEmptyMirrors() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/.swiftpm/config")
        let configuration = Configuration.Mirrors(fileSystem: fs, path: configFile)

        try configuration.withMapping { _ in }
        XCTAssertFalse(fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"
        try configuration.withMapping { mapping in
            mapping.set(mirrorURL: mirrorURL, forURL: originalURL)
        }
        XCTAssertTrue(fs.exists(configFile))
        XCTAssertEqual(configuration.effectiveURL(for: originalURL), mirrorURL)

        try configuration.withMapping { mapping in
            try mapping.unset(originalOrMirrorURL: originalURL)
        }
        XCTAssertFalse(fs.exists(configFile))
    }
}
