/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import class PackageDescription.Package
import PackageLoading
import PackageModel
import PackageGraph
import SourceControl
import Utility
import Workspace
@testable import class Workspace.Workspace

import TestSupport

private let sharedManifestLoader = ManifestLoader(resources: Resources.default)

fileprivate extension ResolvedPackage {
    var version: Version? {
        return manifest.version
    }
}

private class TestWorkspaceDelegate: WorkspaceDelegate {
    var fetched = [String]()
    var cloned = [String]()
    /// Map of checkedout repos with key as repository and value as the reference (version or revision).
    var checkedOut = [String: String]()
    var removed = [String]()
    var warnings = [String]()

    func fetchingMissingRepositories(_ urls: Set<String>) {
    }

    func fetching(repository: String) {
        fetched.append(repository)
    }

    func cloning(repository: String) {
        cloned.append(repository)
    }

    func checkingOut(repository: String, at reference: String) {
        checkedOut[repository] = reference
    }

    func removing(repository: String) {
        removed.append(repository)
    }

    func warning(message: String) {
        warnings.append(message)
    }
}

extension Workspace {

    static func createWith(
        rootPackage path: AbsolutePath,
        manifestLoader: ManifestLoaderProtocol = sharedManifestLoader,
        delegate: WorkspaceDelegate = TestWorkspaceDelegate(),
        fileSystem: FileSystem = localFileSystem,
        repositoryProvider: RepositoryProvider = GitRepositoryProvider()
    ) throws -> Workspace {
        let workspace = try Workspace(
            dataPath: path.appending(component: ".build"),
            editablesPath: path.appending(component: "Packages"),
            pinsFile: path.appending(component: "Package.pins"),
            manifestLoader: manifestLoader,
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            fileSystem: fileSystem,
            repositoryProvider: repositoryProvider)
        workspace.registerPackage(at: path)
        return workspace
    }

    func loadDependencyManifests() throws -> DependencyManifests {
        return try loadDependencyManifests(loadRootManifests())
    }
}

private let v1: Version = "1.0.0"

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
            let testRepo = GitRepository(path: testRepoPath)
            try testRepo.stage(file: "test.txt")
            try testRepo.commit()
            try testRepo.tag(name: "test-tag")
            let currentRevision = try GitRepository(path: testRepoPath).getCurrentRevision()

            // Create the initial workspace.
            do {
                let workspace = try Workspace.createWith(rootPackage: path)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository.url }, [])

                // Do a low-level clone.
                let checkoutPath = try workspace.clone(repository: testRepoSpec, at: currentRevision)
                XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            }

            // Re-open the workspace, and check we know the checkout version.
            do {
                let workspace = try Workspace.createWith(rootPackage: path)
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
                let workspace = try Workspace.createWith(rootPackage: path)
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
                let workspace = try Workspace.createWith(rootPackage: path)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository.url }, [])
                _ = try workspace.clone(repository: testRepoSpec, at: currentRevision)
                XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])
            }
        }
    }

    func testDependencyManifestLoading() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        //   \ AA: checked out (@v1)
        // \ B: missing
        mktmpdir { path in
            let graph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: v1),
                    MockDependency("B", version: v1),
                ],
                packages: [
                    MockPackage("A", version: v1, dependencies: [
                        MockDependency("AA", version: v1)
                    ]),
                    MockPackage("AA", version: v1),
                ]
            )
            // Create the workspace.
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: graph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have checkouts for A & AA.
            for name in ["A", "AA"] {
                let revision = try GitRepository(path: AbsolutePath(graph.repo(name).url)).getCurrentRevision()
                _ = try workspace.clone(repository: graph.repo(name), at: revision, for: v1)
            }

            // Load the "current" manifests.
            let manifests = try workspace.loadDependencyManifests()
            XCTAssertEqual(manifests.roots[0], graph.rootManifest)
            // B should be missing.
            XCTAssertEqual(manifests.missingURLs(), ["//B"])
            XCTAssertEqual(manifests.dependencies.map{$0.manifest.name}.sorted(), ["A", "AA"])
            let aManifest = graph.manifest("A", version: v1)
            XCTAssertEqual(manifests.lookup(manifest: "A"), aManifest)
            let aaManifest = graph.manifest("AA", version: v1)
            XCTAssertEqual(manifests.lookup(manifest: "AA"), aaManifest)
        }
    }

    /// Check the basic ability to load a graph from the workspace.
    func testPackageGraphLoadingBasics() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: v1),
                ],
                packages: [
                    MockPackage("A", version: v1),
                ]
            )

            // Create the workspace.
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(manifestGraph.repo(name).url)).getCurrentRevision()
                _ = try workspace.clone(repository: manifestGraph.repo(name), at: revision, for: v1)
            }

            // Load the package graph.
            let graph = workspace.loadPackageGraph()

            // Validate the graph has the correct basic structure.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])
        }
    }

    func testPackageGraphLoadingBasicsInMem() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: v1),
            ],
            packages: [
                MockPackage("A", version: v1),
            ],
            fs: fs
        )
        let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate(), fileSystem: fs, repositoryProvider: manifestGraph.repoProvider!)
        let graph = workspace.loadPackageGraph()
        XCTAssertTrue(graph.errors.isEmpty)
        XCTAssertEqual(graph.packages.count, 2)
        XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])
    }


    /// Check the ability to load a graph which requires cloning new packages.
    func testPackageGraphLoadingWithCloning() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        //   \ AA: missing
        // \ B: missing
        mktmpdir { path in

            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: v1),
                    MockDependency("B", version: v1),
                ],
                packages: [
                    MockPackage("A", version: v1, dependencies: [
                        MockDependency("AA", version: v1)
                    ]),
                    MockPackage("AA", version: v1),
                    MockPackage("B", version: v1),
                ]
            )
            // Create the workspace.
            let delegate = TestWorkspaceDelegate()
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)

            // Ensure delegates haven't been called yet.
            XCTAssert(delegate.fetched.isEmpty)
            XCTAssert(delegate.cloned.isEmpty)
            XCTAssert(delegate.checkedOut.isEmpty)

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(manifestGraph.repo(name).url)).getCurrentRevision()
                _ = try workspace.clone(repository: manifestGraph.repo(name), at: revision, for: v1)
            }

            // Load the package graph.
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)

            // Test the delegates.
            XCTAssertEqual(delegate.fetched.sorted(), manifestGraph.repos.values.map{$0.url}.sorted())
            XCTAssertEqual(delegate.cloned.sorted(), manifestGraph.repos.values.map{$0.url}.sorted())
            XCTAssertEqual(delegate.checkedOut.count, 3)
            for (_, repo) in manifestGraph.repos {
                XCTAssertEqual(delegate.checkedOut[repo.url], "1.0.0")
            }

            // Validate the graph has the correct basic structure.
            XCTAssertEqual(graph.packages.count, 4)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), [
                    "A", "AA", "B", "Root"])
        }
    }

    func testUpdate() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        //   \ AA: checked out (@v1)
        // Then update to:
        // Root
        // \ A: checked out (@v1.0.1)
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                ],
                packages: [
                    MockPackage("A", version: v1, dependencies: [
                        MockDependency("AA", version: v1),
                    ]),
                    MockPackage("A", version: "1.0.1"),
                    MockPackage("AA", version: v1),
                ]
            )
            let delegate = TestWorkspaceDelegate()
            let repoPath = AbsolutePath(manifestGraph.repo("A").url)

            func createWorkspace() throws -> Workspace {
                return  try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            }

            do {
                // Create the workspace.
                let workspace = try createWorkspace()

                // Turn off auto pinning.
                try workspace.pinsStore.setAutoPin(on: false)
                // Ensure delegates haven't been called yet.
                XCTAssert(delegate.fetched.isEmpty)
                XCTAssert(delegate.cloned.isEmpty)
                XCTAssert(delegate.checkedOut.isEmpty)
                XCTAssert(delegate.removed.isEmpty)

                // Load the package graph.
                let graph = workspace.loadPackageGraph()
                XCTAssertTrue(graph.errors.isEmpty)

                // Test the delegates.
                XCTAssert(delegate.fetched.count == 2)
                XCTAssert(delegate.cloned.count == 2)
                XCTAssert(delegate.removed.isEmpty)
                for (_, repoPath) in manifestGraph.repos {
                    XCTAssert(delegate.fetched.contains(repoPath.url))
                    XCTAssert(delegate.cloned.contains(repoPath.url))
                    XCTAssertEqual(delegate.checkedOut[repoPath.url], "1.0.0")
                }

                // Validate the graph has the correct basic structure.
                XCTAssertEqual(graph.packages.count, 3)
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "AA", "Root"])


                let file = repoPath.appending(component: "update.swift")
                try systemQuietly(["touch", file.asString])
                let testRepo = GitRepository(path: repoPath)
                try testRepo.stageEverything()
                try testRepo.commit(message: "update")
                try testRepo.tag(name: "1.0.1")
            }

            do {
                let workspace = try createWorkspace()
                try workspace.updateDependencies()
                // Test the delegates after update.
                XCTAssert(delegate.fetched.count == 2)
                XCTAssert(delegate.cloned.count == 2)
                for (_, repoPath) in manifestGraph.repos {
                    XCTAssert(delegate.fetched.contains(repoPath.url))
                    XCTAssert(delegate.cloned.contains(repoPath.url))
                }
                XCTAssertEqual(delegate.checkedOut[repoPath.asString], "1.0.1")
                XCTAssertEqual(delegate.removed, [manifestGraph.repo("AA").url])

                let graph = workspace.loadPackageGraph()
                XCTAssertTrue(graph.errors.isEmpty)
                XCTAssert(graph.packages.filter{ $0.name == "A" }.first!.version == "1.0.1")
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])
                XCTAssertEqual(delegate.removed.sorted(), [manifestGraph.repo("AA").url])
            }
        }
    }

    func testCleanAndReset() throws {
        mktmpdir { path in
            // Create a test repository.
            let testRepoPath = path.appending(component: "test-repo")
            let testRepoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "initial")

            let workspace = try Workspace.createWith(rootPackage: path)
            let checkoutPath = try workspace.clone(repository: testRepoSpec, at: Revision(identifier: "initial"))
            XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])

            // Drop a build artifact in data directory.
            let buildArtifact = workspace.dataPath.appending(component: "test.o")
            try localFileSystem.writeFileContents(buildArtifact, bytes: "Hi")

            // Sanity checks.
            XCTAssert(localFileSystem.exists(buildArtifact))
            XCTAssert(localFileSystem.exists(checkoutPath))

            try workspace.clean()

            XCTAssertEqual(workspace.dependencies.map{ $0.repository }, [testRepoSpec])
            XCTAssert(localFileSystem.exists(workspace.dataPath))
            // The checkout should be safe.
            XCTAssert(localFileSystem.exists(checkoutPath))
            // Build artifact should be removed.
            XCTAssertFalse(localFileSystem.exists(buildArtifact))

            // Add build artifact again.
            try localFileSystem.writeFileContents(buildArtifact, bytes: "Hi")
            XCTAssert(localFileSystem.exists(buildArtifact))

            try workspace.reset()
            // Everything should go away but cache directory should be present.
            XCTAssertFalse(localFileSystem.exists(buildArtifact))
            XCTAssertFalse(localFileSystem.exists(checkoutPath))
            XCTAssertTrue(localFileSystem.exists(workspace.dataPath))
            XCTAssertTrue(workspace.dependencies.map{$0}.isEmpty)
        }
    }

    func testEditDependency() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: nil), // To load the edited package manifest.
                ]
            )
            // Create the workspace.
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            // Sanity checks.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])

            let manifests = try workspace.loadDependencyManifests()
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }

            func getDependency(_ manifest: Manifest) -> Workspace.ManagedDependency {
                return workspace.dependencyMap[RepositorySpecifier(url: manifest.url)]!
            }

            // Get the dependency for package A.
            let dependency = getDependency(aManifest)
            // It should not be in edit mode.
            XCTAssert(dependency.state == .checkout)
            // Put the dependency in edit mode at its current revision.
            try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name)

            let editedDependency = getDependency(aManifest)
            // It should be in edit mode.
            XCTAssert(editedDependency.state == .edited)
            // Check the based on data.
            XCTAssertEqual(editedDependency.basedOn?.subpath, dependency.subpath)
            XCTAssertEqual(editedDependency.basedOn?.currentVersion, dependency.currentVersion)
            XCTAssertEqual(editedDependency.basedOn?.currentRevision, dependency.currentRevision)

            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            // Get the repo from edits path.
            let editRepo = GitRepository(path: editRepoPath)
            // Ensure that the editable checkout's remote points to the original repo path.
            XCTAssertEqual(try editRepo.remotes()[0].url, manifestGraph.repo("A").url)
            // Check revision and head.
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.currentRevision!)
            // FIXME: Current checkout behavior seems wrong, it just resets and doesn't leave checkout to a detached head.
          #if false
            XCTAssertEqual(try popen([Git.tool, "-C", editRepoPath.asString, "rev-parse", "--abbrev-ref", "HEAD"]).chomp(), "HEAD")
          #endif

            do {
                try workspace.edit(dependency: editedDependency, at: dependency.currentRevision!, packageName: aManifest.name)
                XCTFail("Unexpected success, \(editedDependency) is already in edit mode")
            } catch WorkspaceOperationError.dependencyAlreadyInEditMode {}

            do {
                // Reopen workspace and check if we maintained the state.
                let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
                let dependency = workspace.dependencyMap[RepositorySpecifier(url: aManifest.url)]!
                XCTAssert(dependency.state == .edited)
            }

            // We should be able to unedit the dependency.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssertEqual(getDependency(aManifest).state, .checkout)
            XCTAssertFalse(exists(editRepoPath))
            XCTAssertFalse(exists(workspace.editablesPath))
        }
    }

    func testEditDependencyOnNewBranch() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: nil), // To load the edited package manifest.
                ]
            )
            // Create the workspace.
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            let manifests = try workspace.loadDependencyManifests()
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            func getDependency(_ manifest: Manifest) -> Workspace.ManagedDependency {
                return workspace.dependencyMap[RepositorySpecifier(url: manifest.url)]!
            }
            // Get the dependency for package A.
            let dependency = getDependency(aManifest)
            // Put the dependency in edit mode at its current revision on a new branch.
            try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name, checkoutBranch: "BugFix")
            let editedDependency = getDependency(aManifest)
            XCTAssert(editedDependency.state == .edited)

            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            let editRepo = GitRepository(path: editRepoPath)
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.currentRevision!)
            XCTAssertEqual(try editRepo.currentBranch(), "BugFix")
            // Unedit it.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssertEqual(getDependency(aManifest).state, .checkout)

            do {
                try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name, checkoutBranch: "master")
                XCTFail("Unexpected edit success")
            } catch WorkspaceOperationError.branchAlreadyExists {}
        }
    }

    func testUneditDependency() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: nil), // To load the edited package manifest.
                ]
            )
            // Create the workspace.
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            // Sanity checks.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])

            let manifests = try workspace.loadDependencyManifests()
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            func getDependency(_ manifest: Manifest) -> Workspace.ManagedDependency {
                return workspace.dependencyMap[RepositorySpecifier(url: manifest.url)]!
            }
            let dependency = getDependency(aManifest)
            // Put the dependency in edit mode.
            try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name, checkoutBranch: "bugfix")

            let editedDependency = getDependency(aManifest)
            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            // Write something in repo.
            try localFileSystem.writeFileContents(editRepoPath.appending(component: "test.txt"), bytes: "Hi")
            let editRepo = GitRepository(path: editRepoPath)
            try editRepo.stage(file: "test.txt")
            // Try to unedit.
            do {
                try workspace.unedit(dependency: editedDependency, forceRemove: false)
                XCTFail("Unexpected edit success")
            } catch WorkspaceOperationError.hasUncommitedChanges(let repo) {
                XCTAssertEqual(repo, editRepoPath)
            }
            // Commit and try to unedit.
            try editRepo.commit()
            do {
                try workspace.unedit(dependency: editedDependency, forceRemove: false)
                XCTFail("Unexpected edit success")
            } catch WorkspaceOperationError.hasUnpushedChanges(let repo) {
                XCTAssertEqual(repo, editRepoPath)
            }
            // Force remove.
            try workspace.unedit(dependency: editedDependency, forceRemove: true)
            XCTAssertEqual(getDependency(aManifest).state, .checkout)
            XCTAssertFalse(exists(editRepoPath))
            XCTAssertFalse(exists(workspace.editablesPath))
        }
    }

    func testAutoPinning() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("A", version: "1.0.1", dependencies: [
                    MockDependency("AA", version: v1),
                ]),
                MockPackage("AA", version: v1),
            ],
            fs: fs
        )

        let provider = manifestGraph.repoProvider!

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            try workspace.reset()
        }

        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        // We should still get v1 even though an update is available.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            try workspace.reset()
        }

        // Updating dependencies shouldn't matter.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
        }

        // Updating dependencies with repinning should do the actual update.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies(repin: true)
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("AA").version == v1)
            // We should have pin for AA automatically.
            XCTAssertNotNil(workspace.pinsStore.pinsMap["A"])
            XCTAssertNotNil(workspace.pinsStore.pinsMap["AA"])
        }

        // Unpin all of the dependencies.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.unpinAll()
            // Reset so we have a clean workspace.
            try workspace.reset()
            try workspace.pinsStore.setAutoPin(on: false)
        }

        // Pin at A at v1.
        do {
            let workspace = newWorkspace()
            _ = workspace.loadPackageGraph()
            let manifests = try workspace.loadDependencyManifests()
            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            try workspace.pin(dependency: dep, packageName: "A", at: v1)
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
        }

        // Updating and repinning shouldn't pin new deps which are introduced.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies(repin: true)
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("AA").version == v1)
            XCTAssertNotNil(workspace.pinsStore.pinsMap["A"])
            // We should not have pinned AA.
            XCTAssertNil(workspace.pinsStore.pinsMap["AA"])
        }
    }

    func testPinning() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("A", version: "1.0.1"),
            ],
            fs: fs
        )

        let provider = manifestGraph.repoProvider!
        let aRepo = provider.specifierMap[manifestGraph.repo("A")]!
        try aRepo.tag(name: "1.0.1")

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Pins "A" at v1.
        func pin() throws {
            let workspace = newWorkspace()
            let manifests = try workspace.loadDependencyManifests()
            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            // Try unpinning something which is not pinned.
            XCTAssertThrows(PinOperationError.notPinned) {
                try workspace.pinsStore.unpin(package: "A")
            }
            try workspace.pin(dependency: dep, packageName: "A", at: v1)
        }

        // Turn off autopin.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.setAutoPin(on: false)
        }

        // Package graph should load 1.0.1.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
        }

        // Pin package to v1.
        try pin()

        // Package graph should load v1.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.0")
        }

        // Unpin package.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.unpin(package: "A")
            try workspace.reset()
        }

        // Package graph should load 1.0.1.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
        }

        // Pin package to v1.
        try pin()

        // Package *update* should load v1 after pinning.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.0")
        }

        // Package *update* should load 1.0.1 with repinning.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies(repin: true)
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
        }
    }

    func testPinAll() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                MockDependency("B", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("B", version: v1),
                MockPackage("A", version: "1.0.1"),
                MockPackage("B", version: "1.0.1"),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Package graph should load v1.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Pin the dependencies.
        do {
            let workspace = newWorkspace()
            try workspace.pinAll()
            // Reset so we have a clean workspace.
            try workspace.reset()
        }

        // Add a new version of dependencies.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "1.0.1")

        // Loading the workspace now should load v1 of both dependencies.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Updating the dependencies shouldn't update to 1.0.1.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Unpin all of the dependencies.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.unpinAll()
            // Reset so we have a clean workspace.
            try workspace.reset()
        }

        // Loading the workspace now should load 1.0.1 of both dependencies.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("B").version == "1.0.1")
        }
    }

    func testUpdateRepinning() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                MockDependency("B", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("B", version: v1),
                MockPackage("A", version: "1.0.1"),
                MockPackage("B", version: "1.0.1"),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Load and pin the dependencies.
        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
            try workspace.pinAll()
            try workspace.reset()
        }

        // Add a new version of dependencies.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "1.0.1")

        // Updating the dependencies with repin should update to 1.0.1.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies(repin: true)
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("B").version == "1.0.1")
        }
    }

    func testPinFailure() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                MockDependency("B", version: v1),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("A", version: "1.0.1", dependencies: [
                    MockDependency("B", version: "2.0.0")
                ]),
                MockPackage("B", version: v1),
                MockPackage("B", version: "2.0.0"),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "2.0.0")

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        func pin(at version: Version) throws {
            let workspace = newWorkspace()
            let manifests = try workspace.loadDependencyManifests()
            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            try workspace.pin(dependency: dep, packageName: "A", at: version)
        }

        // Pinning at v1 should work.
        do {
            let workspace = newWorkspace()
            _ = workspace.loadPackageGraph()
            try pin(at: v1)
            try workspace.reset()
        }

        // Add a the tag which will make resolution unstatisfiable.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        do {
            let workspace = newWorkspace()
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
            XCTAssert(graph.lookup("A").version == v1)
            // Pinning non existant version should fail.
            XCTAssertThrows(DependencyResolverError.unsatisfiable) {
                try pin(at: "1.0.2")
            }
            // Pinning an unstatisfiable version should fail.
            XCTAssertThrows(DependencyResolverError.unsatisfiable) {
                try pin(at: "1.0.1")
            }
            // But we should still be able to repin at v1.
            try pin(at: v1)
            // And also after unpinning.
            try workspace.pinsStore.unpinAll()
            try pin(at: v1)

        }
    }

    func testPinAllFailure() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: v1),
                MockDependency("B", version: v1),
            ],
            packages: [
                MockPackage("A", version: v1, dependencies: [
                    MockDependency("B", version: "2.0.0")
                ]),
                MockPackage("B", version: v1),
                MockPackage("B", version: "2.0.0"),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "2.0.0")
        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // We should not be able to load package graph.
        do {
            let graph = newWorkspace().loadPackageGraph()
            XCTAssertEqual(graph.errors.count, 1)
            // DependencyResolverError.unsatisfiable
        }
    }

    func testStrayPin() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1, dependencies: [
                    MockDependency("B", version: v1)
                ]),
                MockPackage("A", version: "1.0.1"),
                MockPackage("B", version: v1),
            ],
            fs: fs
        )
        let delegate = TestWorkspaceDelegate()
        let provider = manifestGraph.repoProvider!

        func newWorkspace() -> Workspace {
            return try! Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: delegate,
                fileSystem: fs,
                repositoryProvider: provider)
        }
        
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.setAutoPin(on: false)
            _ = workspace.loadPackageGraph()
            let manifests = try workspace.loadDependencyManifests()
            guard let (_, dep) = manifests.lookup(package: "B") else {
                return XCTFail("Expected manifest for package B not found")
            }
            try workspace.pin(dependency: dep, packageName: "B", at: v1)
            try workspace.reset()
        }

        // Try updating with repin and versions shouldn't change.
        do {
            let workspace = newWorkspace()
            try workspace.updateDependencies(repin: true)
            let g = workspace.loadPackageGraph()
            XCTAssertTrue(g.errors.isEmpty)
            XCTAssert(g.lookup("A").version == v1)
            XCTAssert(g.lookup("B").version == v1)
            try workspace.reset()
        }

        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        do {
            let workspace = newWorkspace()
            let g = workspace.loadPackageGraph()
            XCTAssertTrue(g.errors.isEmpty)
            XCTAssert(g.lookup("A").version == "1.0.1")
            // FIXME: We also cloned B because it has a pin.
            XCTAssertNotNil(workspace.dependencyMap[manifestGraph.repo("B")])
        }

        do {
            let workspace = newWorkspace()
            XCTAssertTrue(delegate.warnings.isEmpty)
            try workspace.updateDependencies(repin: true)
            XCTAssertEqual(delegate.warnings, ["Consider unpinning B, it is pinned at 1.0.0 but the dependency is not present."])
            let g = workspace.loadPackageGraph()
            XCTAssertTrue(g.errors.isEmpty)
            XCTAssert(g.lookup("A").version == "1.0.1")
            // This dependency should be removed on updating dependencies because it is not referenced anywhere.
            XCTAssertNil(workspace.dependencyMap[manifestGraph.repo("B")])
        }
    }

    func testMultipleRootPackages() throws {
        mktmpdir { path in
            var repos = [String: AbsolutePath]()
            var manifests = try Dictionary(items: ["A", "B", "C", "D"].map { pkg -> (MockManifestLoader.Key, Manifest) in
                let repoPath = path.appending(component: pkg)
                repos[pkg] = repoPath
                try makeDirectories(repoPath)
                initGitRepo(repoPath, tag: v1.description)

                let manifest = Manifest(
                    path: repoPath.appending(component: Manifest.filename),
                    url: repoPath.asString,
                    package: .v3(PackageDescription.Package(
                        name: pkg,
                        dependencies: [])),
                    version: v1)
                return (MockManifestLoader.Key(url: repoPath.asString, version: v1), manifest)
            })

            // Add a 1.5 version for A.
            do {
                let aPath = repos["A"]!
                let repo = GitRepository(path: aPath)
                try repo.tag(name: "1.5.0")
                let aManifest = Manifest(
                    path: aPath.appending(component: Manifest.filename),
                    url: aPath.asString,
                    package: .v3(PackageDescription.Package(name: "A", dependencies: [])),
                    version: "1.5.0")
                manifests[MockManifestLoader.Key(url: aPath.asString, version: "1.5.0")] = aManifest
            }

            let roots = (1...3).map { path.appending(component: "root\($0)") }

            var deps: [AbsolutePath: [PackageDescription.Package.Dependency]] = [:]
            deps[roots[0]] = [
                .Package(url: repos["A"]!.asString, versions: "1.0.0"..<"2.0.0"),
                .Package(url: repos["B"]!.asString, versions: "1.0.0"..<"2.0.0"),
            ]
            deps[roots[1]] = [
                .Package(url: repos["C"]!.asString, versions: "1.0.0"..<"2.0.0"),
            ]
            deps[roots[2]] = [
                .Package(url: repos["A"]!.asString, versions: "1.0.0"..<"1.5.0"),
                .Package(url: repos["D"]!.asString, versions: "1.0.0"..<"2.0.0"),
            ]

            for root in roots {
                try makeDirectories(root)
                try Process.checkNonZeroExit(
                    args: "touch", root.appending(component: "foo.swift").asString)
                let rootManifest = Manifest(
                    path: root.appending(component: Manifest.filename),
                    url: root.asString,
                    package: .v3(PackageDescription.Package(
                        name: root.basename,
                        dependencies: deps[root]!)),
                    version: nil
                )
                manifests[MockManifestLoader.Key(url: root.asString, version: nil)] = rootManifest
            }

            // We have mocked a graph with multiple root packages, now continue with workspace testing.

            func createWorkspace() throws -> Workspace {
                let buildPath = path.appending(components: "build")
                return try Workspace(
                    dataPath: buildPath,
                    editablesPath: buildPath.appending(component: "Packages"),
                    pinsFile: path.appending(component: "Package.pins"),
                    manifestLoader: MockManifestLoader(manifests: manifests),
                    delegate: TestWorkspaceDelegate()
                )
            }

            // Set auto pinning off.
            do {
                let workspace = try createWorkspace()
                try workspace.pinsStore.setAutoPin(on: false)
            }

            // Throw if we have not registered any packages but want to load things.
            do {
                let workspace = try createWorkspace()
                _ = try workspace.loadDependencyManifests()
                XCTFail("unexpected success")
            } catch let errors as Errors {
                switch errors.errors[0] {
                case WorkspaceOperationError.noRegisteredPackages: break
                default: XCTFail()
                }
            }

            do {
                let workspace = try createWorkspace()
                let graph = workspace.loadPackageGraph()
                switch graph.errors[0] {
                case WorkspaceOperationError.noRegisteredPackages: break
                default: XCTFail()
                }
            }

            // Throw if we try to unregister a path which doesn't exists in workspace.
            let fakePath = path.appending(component: "fake")
            do {
                let workspace = try createWorkspace()
                try workspace.unregisterPackage(at: fakePath)
                XCTFail("unexpected success")
            } catch WorkspaceOperationError.pathNotRegistered(let path) {
                XCTAssertEqual(path, fakePath)
            }

            do {
                let workspace = try createWorkspace()
                // Register first two packages.
                for root in roots[0..<2] {
                    workspace.registerPackage(at: root)
                }
                let graph = workspace.loadPackageGraph()
                XCTAssertTrue(graph.errors.isEmpty)
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "B", "C", "root1", "root2"])
                XCTAssertEqual(graph.rootPackages.map{ $0.name }.sorted(), ["root1", "root2"])
                XCTAssertEqual(graph.lookup("A").version, "1.5.0")
            }

            // FIXME: We shouldn't need to reset workspace here, but we have to because we introduce 
            // incompatible constraints via root package 3. This happens because when we add new dependencies and resolve in workspace
            // we constraint old manifests to previously resolved versions.
            do {
                let workspace = try createWorkspace()
                try workspace.reset()
            }

            do {
                let workspace = try createWorkspace()
                // Register all packages.
                for root in roots {
                    workspace.registerPackage(at: root)
                }
                let graph = workspace.loadPackageGraph()
                XCTAssertTrue(graph.errors.isEmpty)
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "B", "C", "D", "root1", "root2", "root3"])
                XCTAssertEqual(graph.rootPackages.map{ $0.name }.sorted(), ["root1", "root2", "root3"])
                XCTAssertEqual(graph.lookup("A").version, v1)

                // FIXME: We need to reset because we apply constraints for current checkouts (see the above note).
                try workspace.reset()

                // Remove one of the packages.
                try workspace.unregisterPackage(at: roots[2])
                let newGraph = workspace.loadPackageGraph()
                XCTAssertTrue(newGraph.errors.isEmpty)
                XCTAssertEqual(newGraph.packages.map{ $0.name }.sorted(), ["A", "B", "C", "root1", "root2"])
                XCTAssertEqual(newGraph.rootPackages.map{ $0.name }.sorted(), ["root1", "root2"])
                XCTAssertEqual(newGraph.lookup("A").version, "1.5.0")
            }
        }
    }

    func testWarnings() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: v1),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: nil),
                ]
            )

            let delegate = TestWorkspaceDelegate()
            let workspace = try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            workspace.loadPackageGraph()

            // Put A in edit mode.
            let aManifest = try workspace.loadDependencyManifests().lookup(manifest: "A")!
            let dependency = workspace.dependencyMap[RepositorySpecifier(url: aManifest.url)]!
            try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name)

            // We should retain the original pin for a package which is in edit mode.
            try workspace.pinAll(reset: true)
            XCTAssertEqual(workspace.pinsStore.pinsMap["A"]?.version, v1)

            // Remove edited checkout.
            try removeFileTree(workspace.editablesPath)
            delegate.warnings.removeAll()
            workspace.loadPackageGraph()
            XCTAssertTrue(delegate.warnings[0].hasSuffix("A was being edited but has been removed, falling back to original checkout."))
        }
    }

    func testDependencyResolutionWithEdit() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                    MockDependency("B", version: v1),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: "1.0.1"),
                    MockPackage("B", version: v1),
                    MockPackage("B", version: nil),
                ]
            )

            let delegate = TestWorkspaceDelegate()
            func createWorkspace() throws -> Workspace {
                return  try Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            }

            do {
                let workspace = try createWorkspace()
                workspace.loadPackageGraph()
                let manifests = try workspace.loadDependencyManifests()

                let bDependency = manifests.lookup(package: "B")!.dependency
                try workspace.edit(dependency: bDependency, at: bDependency.currentRevision!, packageName: "B")

                XCTAssertEqual(manifests.lookup(package: "A")!.dependency.currentVersion, v1)
                XCTAssertEqual(workspace.pinsStore.pinsMap["A"]?.version, v1)
                XCTAssertEqual(workspace.pinsStore.pinsMap["B"]?.version, v1)

                // Create update.
                let repoPath = AbsolutePath(manifestGraph.repo("A").url)
                try localFileSystem.writeFileContents(repoPath.appending(component: "update.swift"), bytes: "")
                let testRepo = GitRepository(path: repoPath)
                try testRepo.stageEverything()
                try testRepo.commit(message: "update")
                try testRepo.tag(name: "1.0.1")
            }

            // Update and check states.
            do {
                let workspace = try createWorkspace()
                try workspace.updateDependencies(repin: true)
                let manifests = try workspace.loadDependencyManifests()

                XCTAssertEqual(manifests.lookup(package: "A")!.dependency.currentVersion, "1.0.1")
                XCTAssertEqual(workspace.pinsStore.pinsMap["A"]?.version, "1.0.1")
                XCTAssertTrue(manifests.lookup(package: "B")!.dependency.state == .edited)
                XCTAssertEqual(workspace.pinsStore.pinsMap["B"]?.version, v1)
            }
        }
    }

    func testToolsVersionRootPackages() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/root0/foo.swift",
            "/root1/foo.swift")

        let roots: [AbsolutePath] = ["/root0", "/root1"].map(AbsolutePath.init)

        func swiftVersion(for root: AbsolutePath) -> AbsolutePath {
            return root.appending(component: "Package.swift")
        }

        for root in roots {
            try fs.writeFileContents(swiftVersion(for: root), bytes: "")
        }

        var manifests: [MockManifestLoader.Key: Manifest] = [:]
        for root in roots {
            let rootManifest = Manifest(
                path: AbsolutePath.root.appending(component: Manifest.filename),
                url: root.asString,
                package: .v3(.init(name: root.asString)),
                version: nil
            )
            manifests[MockManifestLoader.Key(url: root.asString, version: nil)] = rootManifest
        }
        let manifestLoader = MockManifestLoader(manifests: manifests)

        func createWorkspace(_ toolsVersion: ToolsVersion) throws -> Workspace {
            let workspace = try Workspace(
                dataPath: AbsolutePath.root.appending(component: ".build"),
                editablesPath: AbsolutePath.root.appending(component: "Packages"),
                pinsFile: AbsolutePath.root.appending(component: "Package.pins"),
                manifestLoader: manifestLoader,
                currentToolsVersion: toolsVersion,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs)
            workspace.registerPackage(at: roots[0])
            workspace.registerPackage(at: roots[1])
            return workspace
        }

        // We should be able to load when no there is no swift-tools-version defined.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "3.1.0"))
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
        } 

        // Limit root0 to 3.1.0
        try fs.writeFileContents(swiftVersion(for: roots[0]), bytes: "// swift-tools-version:3.1")

        // Test one root package having swift-version.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "4.0.0"))
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
        }

        // Limit root1 to 4.0.0
        try fs.writeFileContents(swiftVersion(for: roots[1]), bytes: "// swift-tools-version:4.0.0")

        // Test both having swift-version but different.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "4.0.0"))
            let graph = workspace.loadPackageGraph()
            XCTAssertTrue(graph.errors.isEmpty)
        }

        // Failing case.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "3.1.0"))
            let graph = workspace.loadPackageGraph()

            switch graph.errors[0] {
            case WorkspaceOperationError.incompatibleToolsVersion(let rootPackage, let required, let current):
                XCTAssertEqual(rootPackage, roots[1])
                XCTAssertEqual(required.description, "4.0.0")
                XCTAssertEqual(current.description, "3.1.0")
            default: XCTFail()
            }
        }
    }

    func testLoadingRootManifests() {
        mktmpdir{ path in
            let roots: [AbsolutePath] = ["root0", "root1", "root2"].map(path.appending(component:))
            for root in roots {
                try localFileSystem.createDirectory(root)
            }

            try localFileSystem.writeFileContents(roots[2].appending(components: Manifest.filename)) { stream in
                stream <<< "import PackageDescription" <<< "\n"
                stream <<< "let package = Package(name: \"root0\")"
            }

            let workspace = try Workspace.createWith(rootPackage: roots[0])
            workspace.registerPackage(at: roots[1])
            workspace.registerPackage(at: roots[2])

            let (manifests, errors) = workspace.loadRootManifestsSafely()
            XCTAssertEqual(manifests.count, 1)
            XCTAssertEqual(errors.count, 2)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testEditDependency", testEditDependency),
        ("testEditDependencyOnNewBranch", testEditDependencyOnNewBranch),
        ("testDependencyManifestLoading", testDependencyManifestLoading),
        ("testPackageGraphLoadingBasics", testPackageGraphLoadingBasics),
        ("testPackageGraphLoadingBasicsInMem", testPackageGraphLoadingBasicsInMem),
        ("testPackageGraphLoadingWithCloning", testPackageGraphLoadingWithCloning),
        ("testAutoPinning", testAutoPinning),
        ("testPinAll", testPinAll),
        ("testPinning", testPinning),
        ("testUpdateRepinning", testUpdateRepinning),
        ("testPinFailure", testPinFailure),
        ("testPinAllFailure", testPinAllFailure),
        ("testStrayPin", testStrayPin),
        ("testUpdate", testUpdate),
        ("testUneditDependency", testUneditDependency),
        ("testCleanAndReset", testCleanAndReset),
        ("testMultipleRootPackages", testMultipleRootPackages),
        ("testWarnings", testWarnings),
        ("testDependencyResolutionWithEdit", testDependencyResolutionWithEdit),
        ("testToolsVersionRootPackages", testToolsVersionRootPackages),
        ("testLoadingRootManifests", testLoadingRootManifests),
    ]
}

extension PackageGraph {
    /// Finds the package matching the given name.
    func lookup(_ name: String) -> PackageModel.ResolvedPackage {
        return packages.first{ $0.name == name }!
    }
}
