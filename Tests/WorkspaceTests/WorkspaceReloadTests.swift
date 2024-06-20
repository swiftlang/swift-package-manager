//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import SPMTestSupport
import Workspace
import XCTest

final class WorkspaceReloadTests: XCTestCase {
    func testHeaderReloading() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: []),
                    ]
                ),
            ]
        )

        try workspace.checkPackageGraph(roots: ["Foo"], deps: []) { graph, diagnostics in
            try XCTAssertFalse(
                workspace.getOrCreateWorkspace().fileAffectsSwiftOrClangBuildSettings(
                    filePath: "/tmp/ws/.build/header.h",
                    packageGraph: graph
                )
            )
            XCTAssertNoDiagnostics(diagnostics)
        }
    }
}
