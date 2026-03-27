//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
@testable import Basics
@testable import PackageLoading
import SourceControl
import Testing

import enum TSCUtility.Git

struct ManifestGitInformationCacheTests {
    @Test
    func cacheReusesGitInformationAcrossDirectoriesInSameRepository() async throws {
        try await testWithTemporaryDirectory { path in
            let repository = try Self.createRepository(at: path)

            let packageAPath = path.appending(components: "Packages", "A")
            let packageBPath = path.appending(components: "Packages", "B")
            try localFileSystem.createDirectory(packageAPath, recursive: true)
            try localFileSystem.createDirectory(packageBPath, recursive: true)

            let packageAReadme = packageAPath.appending("README.md")
            let packageBReadme = packageBPath.appending("README.md")
            try localFileSystem.writeFileContents(packageAReadme, string: "A")
            try localFileSystem.writeFileContents(packageBReadme, string: "B")
            try repository.stage(file: packageAReadme.pathString)
            try repository.stage(file: packageBReadme.pathString)
            try repository.commit(message: "add package directories")

            let transientFile = path.appending("dirty.txt")
            try localFileSystem.writeFileContents(transientFile, string: "dirty")

            let cache = ManifestGitInformationCache()

            let first = cache.gitInformation(for: packageAPath)
            #expect(first?.hasUncommittedChanges == true)

            try localFileSystem.removeFileTree(transientFile)

            let second = cache.gitInformation(for: packageBPath)
            #expect(second?.hasUncommittedChanges == true)
            #expect(second?.currentCommit == first?.currentCommit)
            #expect(second?.currentTag == first?.currentTag)
        }
    }

    @Test
    func clearDropsCachedRepositoryState() async throws {
        try await testWithTemporaryDirectory { path in
            _ = try Self.createRepository(at: path)

            let packageAPath = path.appending(components: "Packages", "A")
            let packageBPath = path.appending(components: "Packages", "B")
            try localFileSystem.createDirectory(packageAPath, recursive: true)
            try localFileSystem.createDirectory(packageBPath, recursive: true)

            let dirtyFile = path.appending("dirty.txt")
            try localFileSystem.writeFileContents(dirtyFile, string: "dirty")

            let cache = ManifestGitInformationCache()

            let first = cache.gitInformation(for: packageAPath)
            #expect(first?.hasUncommittedChanges == true)

            try localFileSystem.removeFileTree(dirtyFile)
            cache.clear()

            let second = cache.gitInformation(for: packageBPath)
            #expect(second?.hasUncommittedChanges == false)
            #expect(second?.currentCommit == first?.currentCommit)
            #expect(second?.currentTag == first?.currentTag)
        }
    }

    @Test
    func cacheDetectsGitDirPointerRepository() async throws {
        try await testWithTemporaryDirectory { path in
            let repositoryRoot = path.appending("repo")
            try localFileSystem.createDirectory(repositoryRoot, recursive: true)
            let repository = try Self.createRepository(at: repositoryRoot)

            let trackedFile = repositoryRoot.appending("tracked.txt")
            try localFileSystem.writeFileContents(trackedFile, string: "hello")
            try repository.stage(file: trackedFile.pathString)
            try repository.commit(message: "initial")

            let worktreePath = path.appending("worktree")
            _ = try await AsyncProcess.checkNonZeroExit(
                args: Git.tool,
                "-C", repositoryRoot.pathString,
                "worktree", "add", "--detach", worktreePath.pathString
            )

            #expect(localFileSystem.isFile(worktreePath.appending(component: ".git")))

            let nestedPath = worktreePath.appending(components: "Nested", "Package")
            try localFileSystem.createDirectory(nestedPath, recursive: true)

            let cache = ManifestGitInformationCache()
            let cachedInfo = cache.gitInformation(for: nestedPath)
            let expectedCommit = try GitRepository(path: worktreePath).getCurrentRevision().identifier

            #expect(cachedInfo?.currentCommit == expectedCommit)
        }
    }

    private static func createRepository(at path: AbsolutePath) throws -> GitRepository {
        let repository = GitRepository(path: path)
        try repository.create()

        let bootstrapFile = path.appending("bootstrap.txt")
        try localFileSystem.writeFileContents(bootstrapFile, string: "bootstrap")
        try repository.stage(file: bootstrapFile.pathString)
        try repository.commit(message: "bootstrap")

        return repository
    }
}
