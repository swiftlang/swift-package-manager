//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
import SourceControl
import Testing

@Suite(
    .tags(
        .FunctionalArea.Workspace,
    ),
)
struct ShallowCloneTests {

    @Test(.tags(.TestSize.medium))
    func shallowCloneLocalBareRepo() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
            let fs = localFileSystem

            let bareRepo = tmpDir.appending("bare.git")
            let workRepo = tmpDir.appending("work")

            try await run(["git", "init", "--bare", bareRepo.pathString])
            try await run(["git", "clone", bareRepo.pathString, workRepo.pathString])

            try fs.writeFileContents(
                workRepo.appending("Package.swift"),
                string: "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"TestPkg\")\n"
            )
            try await run(["git", "-C", workRepo.pathString, "add", "."])
            try await run(["git", "-C", workRepo.pathString, "-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "Initial commit"])
            try await run(["git", "-C", workRepo.pathString, "tag", "1.0.0"])
            try await run(["git", "-C", workRepo.pathString, "push", "origin", "HEAD", "--tags"])

            let destination = tmpDir.appending("cloned")
            let provider = GitRepositoryProvider()
            let repository = RepositorySpecifier(path: bareRepo)

            try await provider.shallowClone(
                repository: repository,
                tag: "1.0.0",
                to: destination,
                recurseSubmodules: false
            )

            #expect(fs.exists(destination.appending("Package.swift")))

            try fs.removeFileTree(destination)
            #expect(!fs.exists(destination))
        }
    }

    @Test(.tags(.TestSize.medium))
    func shallowCloneFailsForInvalidTag() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
            let bareRepo = tmpDir.appending("bare.git")
            try await run(["git", "init", "--bare", bareRepo.pathString])

            let destination = tmpDir.appending("cloned")
            let provider = GitRepositoryProvider()
            let repository = RepositorySpecifier(path: bareRepo)

            await #expect(throws: (any Error).self) {
                try await provider.shallowClone(
                    repository: repository,
                    tag: "nonexistent-tag",
                    to: destination,
                    recurseSubmodules: false
                )
            }
        }
    }

    // MARK: - Helpers

    private func run(_ arguments: [String]) async throws {
        let process = AsyncProcess(arguments: arguments)
        _ = try process.launch()
        let result = try await process.waitUntilExit()
        guard result.exitStatus == .terminated(code: 0) else {
            let stderr = (try? result.utf8stderrOutput()) ?? ""
            throw StringError("command failed: \(arguments.joined(separator: " "))\n\(stderr)")
        }
    }
}
