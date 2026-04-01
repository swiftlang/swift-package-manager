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

@testable import Basics
import Foundation
import _InternalTestSupport
import Testing

import class Basics.AsyncProcess

@Suite(.tags(.TestSize.large))
struct SourceArchiveTests {

    @Test("git ls-remote parsing pipeline against a real local bare repo")
    func gitLsRemoteAgainstLocalBareRepo() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
            let bareRepoPath = tmpDir.appending(component: "test-repo.git")
            let workTreePath = tmpDir.appending(component: "work")

            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "init", "--bare", bareRepoPath.pathString]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "clone", bareRepoPath.pathString, workTreePath.pathString]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "config", "user.email", "test@test.com"]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "config", "user.name", "Test"]
            )

            let packageSwift = workTreePath.appending(component: "Package.swift")
            try localFileSystem.writeFileContents(
                packageSwift,
                string: "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"TestPkg\")\n"
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "add", "."]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "commit", "-m", "Initial commit"]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "tag", "1.0.0"]
            )

            try localFileSystem.writeFileContents(
                workTreePath.appending(component: "README.md"),
                string: "# Test\n"
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "add", "."]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "commit", "-m", "Add README"]
            )
            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "tag", "-a", "v2.0.0", "-m", "Release 2.0.0"]
            )

            try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "-C", workTreePath.pathString, "push", "origin", "HEAD", "--tags"]
            )

            let lsRemoteOutput = try await AsyncProcess.checkNonZeroExit(
                arguments: ["git", "ls-remote", "--tags", bareRepoPath.pathString]
            )

            let rawTags = SourceArchiveResolver.parseLsRemoteOutput(lsRemoteOutput)
            #expect(rawTags.count >= 3)

            let tagNames = Set(rawTags.map(\.tagName))
            #expect(tagNames.contains("1.0.0"))
            #expect(tagNames.contains("v2.0.0"))

            let peeled = SourceArchiveResolver.peelTags(rawTags)
            let semverTags = SourceArchiveResolver.filterSemverTags(peeled)

            #expect(semverTags.map(\.name).contains("1.0.0"))
            #expect(semverTags.map(\.name).contains("v2.0.0"))

            for tag in semverTags {
                #expect(tag.sha.count == 40)
                #expect(tag.sha.allSatisfy { $0.isHexDigit })
            }

            // Annotated tag should resolve to the commit SHA, not the tag object SHA.
            let v2Refs = rawTags.filter { $0.tagName == "v2.0.0" }
            if v2Refs.count == 2 {
                let tagObjectSHA = v2Refs.first { !$0.isPeeled }?.sha
                let commitSHA = v2Refs.first { $0.isPeeled }?.sha
                #expect(tagObjectSHA != commitSHA)
                #expect(semverTags.first { $0.name == "v2.0.0" }?.sha == commitSHA)
            }
        }
    }
}
