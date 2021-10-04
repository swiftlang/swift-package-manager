/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
@testable import Workspace
import XCTest

final class WorkspaceStateTests: XCTestCase {
    private var fs: FileSystem! = nil

    override func setUp() {
        super.setUp()

        fs = InMemoryFileSystem()
    }

    func testSavedDependenciesAreSorted() throws {
        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending(component: "workspace-state.json")
        try fs.writeFileContents(statePath) {
            $0 <<<
                """
                {
                    "object": {
                        "artifacts": [],
                        "dependencies": [
                            {
                                "basedOn": null,
                                "packageRef": {
                                  "identity": "yams",
                                  "kind": "remoteSourceControl",
                                  "location": "https://github.com/jpsim/Yams.git",
                                  "name": "Yams"
                                },
                                "state": {
                                  "checkoutState": {
                                    "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                    "version": "4.0.6"
                                  },
                                  "name": "checkout"
                                },
                                "subpath": "Yams"
                            },
                            {
                                "basedOn": null,
                                "packageRef": {
                                  "identity": "swift-argument-parser",
                                  "kind": "remoteSourceControl",
                                  "location": "https://github.com/apple/swift-argument-parser.git",
                                  "name": "swift-argument-parser"
                                },
                                "state": {
                                  "checkoutState": {
                                    "revision": "83b23d940471b313427da226196661856f6ba3e0",
                                    "version": "0.4.4"
                                  },
                                  "name": "checkout"
                                },
                                "subpath": "swift-argument-parser"
                            }
                        ]
                    },
                    "version": 4
                }
                """
        }

        let state = WorkspaceState(dataPath: buildDir, fileSystem: fs)
        try state.save()

        let serialized = try fs.readFileContents(statePath).description

        let argpRange = try XCTUnwrap(serialized.range(of: "swift-argument-parser"))
        let yamsRange = try XCTUnwrap(serialized.range(of: "yams"))

        XCTAssertTrue(argpRange.lowerBound < yamsRange.lowerBound)
    }
}
