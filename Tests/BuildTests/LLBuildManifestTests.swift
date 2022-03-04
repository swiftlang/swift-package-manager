/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
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
        try ManifestWriter(fileSystem: fs).write(manifest, at: AbsolutePath("/manifest.yaml"))

        let contents: String = try fs.readFileContents(AbsolutePath("/manifest.yaml"))

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

    func testShellCommands() throws {
        var manifest = BuildManifest()

        manifest.defaultTarget = "main"
        manifest.addShellCmd(
            name: "shelley",
            description: "Shelley, Keats, and Byron",
            inputs: [
                .file(AbsolutePath("/file.in]"))
            ],
            outputs: [
                .file(AbsolutePath("/file.out"))
            ],
            arguments: [
                "foo", "bar", "baz"
            ],
            environment: [
                "ABC": "DEF",
                "G H": "I J K",
            ],
            workingDirectory: "/wdir",
            allowMissingInputs: true
        )

        manifest.addNode(.file(AbsolutePath("/file.out")), toTarget: "main")

        let fs = InMemoryFileSystem()
        try ManifestWriter(fileSystem: fs).write(manifest, at: AbsolutePath("/manifest.yaml"))

        let contents: String = try fs.readFileContents(AbsolutePath("/manifest.yaml"))

        XCTAssertEqual(contents, """
            client:
              name: basic
            tools: {}
            targets:
              "main": ["/file.out"]
            default: "main"
            commands:
              "shelley":
                tool: shell
                inputs: ["/file.in]"]
                outputs: ["/file.out"]
                description: "Shelley, Keats, and Byron"
                args: ["foo","bar","baz"]
                env:
                  "ABC": "DEF"
                  "G H": "I J K"
                working-directory: "/wdir"
                allow-missing-inputs: true


            """)
    }
}
