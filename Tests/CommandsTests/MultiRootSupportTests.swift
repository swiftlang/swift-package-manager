//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
import Commands
import _InternalTestSupport
import Workspace
import Testing

@Suite(
    .tags(
        .TestSize.large,
    ),
)
struct MultiRootSupportTests {
    @Test
    func workspaceLoader() throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/tmp/test/dep/Package.swift",
            "/tmp/test/local/Package.swift",
        ])
        let path = AbsolutePath("/tmp/test/Workspace.xcworkspace")
        try fs.writeFileContents(
            path.appending("contents.xcworkspacedata"),
            string:
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Workspace
                version = "1.0">
                <FileRef
                    location = "absolute:/tmp/test/dep">
                </FileRef>
                <FileRef
                    location = "group:local">
                </FileRef>
                </Workspace>
                """
        )

        let observability = ObservabilitySystem.makeForTesting()
        let result = try XcodeWorkspaceLoader(fileSystem: fs, observabilityScope: observability.topScope).load(workspace: path)

        expectNoDiagnostics(observability.diagnostics)
        let actual = result.map { $0.pathString }.sorted()
        let expected = [AbsolutePath("/tmp/test/dep").pathString, AbsolutePath("/tmp/test/local").pathString]
        #expect(actual == expected)
    }
}
