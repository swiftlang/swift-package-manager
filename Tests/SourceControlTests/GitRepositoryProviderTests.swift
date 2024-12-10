//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
@testable import SourceControl
import XCTest

class GitRepositoryProviderTests: XCTestCase {
    func testIsValidDirectory() throws {
        try testWithTemporaryDirectory { sandbox in
            let provider = GitRepositoryProvider()

            // standard repository
            let repositoryPath = sandbox.appending("test")
            try localFileSystem.createDirectory(repositoryPath)
            initGitRepo(repositoryPath)
            XCTAssertTrue(try provider.isValidDirectory(repositoryPath))

            // no-checkout bare repository
            let noCheckoutRepositoryPath = sandbox.appending("test-no-checkout")
            try localFileSystem.copy(from: repositoryPath.appending(".git"), to: noCheckoutRepositoryPath)
            XCTAssertTrue(try provider.isValidDirectory(noCheckoutRepositoryPath))

            // non-git directory
            let notGitPath = sandbox.appending("test-not-git")
            XCTAssertThrowsError(try provider.isValidDirectory(notGitPath))

            // non-git child directory of a git directory
            let notGitChildPath = repositoryPath.appending("test-not-git")
            XCTAssertThrowsError(try provider.isValidDirectory(notGitChildPath))
        }
    }

    func testIsValidDirectoryThrowsPrintableError() throws {
        try testWithTemporaryDirectory { temp in
            let provider = GitRepositoryProvider()
            let expectedErrorMessage = "not a git repository"
            XCTAssertThrowsError(try provider.isValidDirectory(temp)) { error in
                let errorString = String(describing: error)
                XCTAssertTrue(
                    errorString.contains(expectedErrorMessage),
                    "Error string '\(errorString)' should contain '\(expectedErrorMessage)'"
                )
            }
        }
    }

    func testGitShellErrorIsPrintable() throws {
        let stdOut = "An error from Git - stdout"
        let stdErr = "An error from Git - stderr"
        let arguments = ["git", "error"]
        let command = "git error"
        let result = AsyncProcessResult(
            arguments: arguments,
            environment: [:],
            exitStatus: .terminated(code: 1),
            output: .success(Array(stdOut.utf8)),
            stderrOutput: .success(Array(stdErr.utf8))
        )
        let error = GitShellError(result: result)
        let errorString = "\(error)"
        XCTAssertTrue(
            errorString.contains(stdOut),
            "Error string '\(errorString)' should contain '\(stdOut)'"
        )
        XCTAssertTrue(
            errorString.contains(stdErr),
            "Error string '\(errorString)' should contain '\(stdErr)'"
        )
        XCTAssertTrue(
            errorString.contains(command),
            "Error string '\(errorString)' should contain '\(command)'"
        )
    }

    func testGitShellErrorEmptyStdOut() throws {
        let stdErr = "An error from Git - stderr"
        let result = AsyncProcessResult(
            arguments: ["git", "error"],
            environment: [:],
            exitStatus: .terminated(code: 1),
            output: .success([]),
            stderrOutput: .success(Array(stdErr.utf8))
        )
        let error = GitShellError(result: result)
        let errorString = "\(error)"
        XCTAssertTrue(
            errorString.contains(stdErr),
            "Error string '\(errorString)' should contain '\(stdErr)'"
        )
    }

    func testGitShellErrorEmptyStdErr() throws {
        let stdOut = "An error from Git - stdout"
        let result = AsyncProcessResult(
            arguments: ["git", "error"],
            environment: [:],
            exitStatus: .terminated(code: 1),
            output: .success(Array(stdOut.utf8)),
            stderrOutput: .success([])
        )
        let error = GitShellError(result: result)
        let errorString = "\(error)"
        XCTAssertTrue(
            errorString.contains(stdOut),
            "Error string '\(errorString)' should contain '\(stdOut)'"
        )
    }
}
