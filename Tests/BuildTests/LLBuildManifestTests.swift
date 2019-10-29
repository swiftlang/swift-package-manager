/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import LLBuildManifest

// FIXME: This should be in its own test target.
final class LLBuildManifestTests: XCTestCase {
    func testBasics() throws {
        var manifest = BuildManifest()

        manifest.defaultTarget = "main"
        manifest.addPhonyCmd(
            name: "C.Foo",
            inputs: [
                .file(AbsolutePath("/some/file.c")),
                .directory(AbsolutePath("/some/dir")),
                .directoryStructure(AbsolutePath("/some/dir/structure")),
            ],
            outputs: [.virtual("Foo")]
        )

        manifest.addNode(.virtual("Foo"), toTarget: "main")

        let fs = InMemoryFileSystem()
        try ManifestWriter(fs).write(manifest, at: AbsolutePath("/manifest.yaml"))

        let contents = try fs.readFileContents(AbsolutePath("/manifest.yaml"))

        XCTAssertEqual(contents, """
            client:
              name: basic
            tools: {}
            targets:
              "main": ["<Foo>"]
            default: "main"
            nodes:
              "/some/dir/structure/":
                is-directory-structure: true
            commands:
              "C.Foo":
                tool: phony
                inputs: ["/some/file.c","/some/dir/","/some/dir/structure/"]
                outputs: ["<Foo>"]


            """)
    }
}
