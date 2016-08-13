/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Commands
import SourceControl
import Utility

import TestSupport

@testable import class Commands.Workspace

final class WorkspaceTests: XCTestCase {
    func testBasics() throws {
        mktmpdir { path in
            // Create a test repository.
            let testRepoPath = path.appending(component: "test-repo")
            let testRepoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "initial")
            let initialRevision = try GitRepository(path: testRepoPath).getCurrentRevision()

            // Add a couple files and a directory.
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "add", "test.txt"])
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "commit", "-m", "Add some files."])
            try tagGitRepo(testRepoPath, tag: "test-tag")
            let currentRevision = try GitRepository(path: testRepoPath).getCurrentRevision()
            
            // Create the initial workspace.
            do {
                let workspace = try Workspace(rootPackage: path)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository.url }, [])

                // Do a low-level clone.
                let checkoutPath = try workspace.clone(repository: testRepoSpec, at: currentRevision)
                XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            }

            // Re-open the workspace, and check we know the checkout version.
            do {
                let workspace = try Workspace(rootPackage: path)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])
                if let dependency = workspace.dependencies.first(where: { _ in true }) {
                    XCTAssertEqual(dependency.repository, testRepoSpec)
                    XCTAssertEqual(dependency.currentRevision, currentRevision)
                }

                // Check we can move to a different revision.
                let checkoutPath = try workspace.clone(repository: testRepoSpec, at: initialRevision)
                XCTAssert(!localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            }

            // Re-check the persisted state.
            let statePath: AbsolutePath
            do {
                let workspace = try Workspace(rootPackage: path)
                statePath = workspace.statePath
                XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])
                if let dependency = workspace.dependencies.first(where: { _ in true }) {
                    XCTAssertEqual(dependency.repository, testRepoSpec)
                    XCTAssertEqual(dependency.currentRevision, initialRevision)
                }
            }

            // Blow away the workspace state file, and check we can get back to a good state.
            try removeFileTree(statePath)
            do {
                let workspace = try Workspace(rootPackage: path)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository.url }, [])
                _ = try workspace.clone(repository: testRepoSpec, at: currentRevision)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
