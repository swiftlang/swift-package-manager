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
import PackageDescription
import PackageLoading
import PackageModel
import SourceControl
import Utility

import struct TestSupport.MockManifestLoader

import TestSupport

@testable import class Commands.Workspace

private let sharedManifestLoader = ManifestLoader(resources: Resources())

private class TestWorkspaceDelegate: WorkspaceDelegate {
    var fetched = [String]()
    var cloned = [String]()
    /// Map of checkedout repos with key as repository and value as the reference (version or revision).
    var checkedOut = [String: String]()
    var removed = [String]()

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
}

extension Workspace {
    convenience init(rootPackage path: AbsolutePath) throws {
        try self.init(rootPackage: path, manifestLoader: sharedManifestLoader, delegate: TestWorkspaceDelegate())
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
            let workspace = try Workspace(rootPackage: path, manifestLoader: graph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have checkouts for A & AA.
            for name in ["A", "AA"] {
                let revision = try GitRepository(path: AbsolutePath(graph.repo(name).url)).getCurrentRevision()
                _ = try workspace.clone(repository: graph.repo(name), at: revision, for: v1)
            }

            // Load the "current" manifests.
            let manifests = try workspace.loadDependencyManifests()
            XCTAssertEqual(manifests.root.package, graph.rootManifest.package)
            // B should be missing.
            XCTAssertEqual(manifests.missingURLs(), ["//B"])
            XCTAssertEqual(manifests.dependencies.map{$0.manifest.name}.sorted(), ["A", "AA"])
            let aManifest = graph.manifest("A", version: v1)
            XCTAssertEqual(manifests.lookup(manifest: "A")?.package, aManifest.package)
            XCTAssertEqual(manifests.lookup(manifest: "A")?.version, aManifest.version)
            let aaManifest = graph.manifest("AA", version: v1)
            XCTAssertEqual(manifests.lookup(manifest: "AA")?.package, aaManifest.package)
            XCTAssertEqual(manifests.lookup(manifest: "AA")?.version, aaManifest.version)
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
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(manifestGraph.repo(name).url)).getCurrentRevision()
                _ = try workspace.clone(repository: manifestGraph.repo(name), at: revision, for: v1)
            }

            // Load the package graph.
            let graph = try workspace.loadPackageGraph()

            // Validate the graph has the correct basic structure.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])
        }
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
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)

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
            let graph = try workspace.loadPackageGraph()

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
            // Create the workspace.
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)

            // Ensure delegates haven't been called yet.
            XCTAssert(delegate.fetched.isEmpty)
            XCTAssert(delegate.cloned.isEmpty)
            XCTAssert(delegate.checkedOut.isEmpty)
            XCTAssert(delegate.removed.isEmpty)

            // Load the package graph.
            var graph = try workspace.loadPackageGraph()

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

            let repoPath = AbsolutePath(manifestGraph.repo("A").url)

            let file = repoPath.appending(component: "update.swift")
            try systemQuietly(["touch", file.asString])
            let testRepo = GitRepository(path: repoPath)
            try testRepo.stageEverything()
            try testRepo.commit(message: "update")
            try testRepo.tag(name: "1.0.1")

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

            graph = try workspace.loadPackageGraph()
            XCTAssert(graph.packages.filter{ $0.name == "A" }.first!.version == "1.0.1")
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])
            XCTAssertEqual(delegate.removed.sorted(), [manifestGraph.repo("AA").url])
        }
    }

    func testCleanAndReset() throws {
        mktmpdir { path in
            // Create a test repository.
            let testRepoPath = path.appending(component: "test-repo")
            let testRepoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "initial")

            let workspace = try Workspace(rootPackage: path)
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
            // Everything should go away.
            XCTAssertFalse(localFileSystem.exists(workspace.dataPath))
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
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = try workspace.loadPackageGraph()
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
            XCTAssert(!dependency.isInEditableState)
            // Put the dependency in edit mode at its current revision.
            try workspace.edit(dependency: dependency, at: dependency.currentRevision!, packageName: aManifest.name)

            let editedDependency = getDependency(aManifest)
            // It should be in edit mode.
            XCTAssert(editedDependency.isInEditableState)
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
                let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
                let dependency = workspace.dependencyMap[RepositorySpecifier(url: aManifest.url)]!
                XCTAssert(dependency.isInEditableState)
            }

            // We should be able to unedit the dependency.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssertEqual(getDependency(aManifest).isInEditableState, false)
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
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = try workspace.loadPackageGraph()
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
            XCTAssert(editedDependency.isInEditableState)

            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            let editRepo = GitRepository(path: editRepoPath)
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.currentRevision!)
            XCTAssertEqual(try editRepo.currentBranch(), "BugFix")
            // Unedit it.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssertEqual(getDependency(aManifest).isInEditableState, false)

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
            let workspace = try Workspace(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let graph = try workspace.loadPackageGraph()
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
            XCTAssertEqual(getDependency(aManifest).isInEditableState, false)
            XCTAssertFalse(exists(editRepoPath))
            XCTAssertFalse(exists(workspace.editablesPath))
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testEditDependency", testEditDependency),
        ("testEditDependencyOnNewBranch", testEditDependencyOnNewBranch),
        ("testDependencyManifestLoading", testDependencyManifestLoading),
        ("testPackageGraphLoadingBasics", testPackageGraphLoadingBasics),
        ("testPackageGraphLoadingWithCloning", testPackageGraphLoadingWithCloning),
        ("testUpdate", testUpdate),
        ("testUneditDependency", testUneditDependency),
        ("testCleanAndReset", testCleanAndReset),
    ]
}

/// Represents a mock package.
struct MockPackage {
    /// The name of the package.
    let name: String

    /// The current available version of the package.
    let version: Version?

    /// The dependencies of the package.
    let dependencies: [MockDependency]

    init(_ name: String, version: Version?, dependencies: [MockDependency] = []) {
        self.name = name
        self.version = version
        self.dependencies = dependencies
    }
}

/// Represents a mock package dependency.
struct MockDependency {
    /// The name of the dependency.
    let name: String

    /// The allowed version range of this dependency.
    let version: Range<Version>

    init(_ name: String, version: Range<Version>) {
        self.name = name
        self.version = version
    }

    init(_ name: String, version: Version) {
        self.name = name
        self.version = version..<version.successor()
    }
}

/// A mock manifest graph creator. It takes in a path where it creates empty repositories for mock packages.
/// For each mock package, it creates a manifest and maps it to the url and that version in mock manifest loader.
/// It provides basic functionality of getting the repo paths and manifests which can be later modified in tests.
struct MockManifestGraph {
    /// The map of repositories created by this class where the key is name of the package.
    let repos: [String: RepositorySpecifier]

    /// The generated mock manifest loader.
    let manifestLoader: MockManifestLoader

    /// The generated root manifest.
    let rootManifest: Manifest

    /// The map of external manifests created.
    let manifests: [MockManifestLoader.Key: Manifest]

    /// Convinience accessor for repository specifiers.
    func repo(_ package: String) -> RepositorySpecifier {
        return repos[package]!
    }

    /// Convinience accessor for external manifests.
    func manifest(_ package: String, version: Version) -> Manifest {
        return manifests[MockManifestLoader.Key(url: repo(package).url, version: version)]!
    }

    init(at path: AbsolutePath, rootDeps: [MockDependency], packages: [MockPackage]) throws {
        // Create the test repositories, we don't need them to have actual
        // contents (the manifests are mocked).
        let repos = Dictionary(items: try packages.map { package -> (String, RepositorySpecifier) in
            let repoPath = path.appending(component: package.name)
            // Don't recreate repo if it is already there.
            if !exists(repoPath) {
                try makeDirectories(repoPath)
                initGitRepo(repoPath, tag: package.version?.description ?? "initial")
            }
            return (package.name, RepositorySpecifier(url: repoPath.asString))
        })

        // Create the root manifest.
        rootManifest = Manifest(
            path: path.appending(component: Manifest.filename),
            url: path.asString,
            package: PackageDescription.Package(
                name: "Root",
                dependencies: MockManifestGraph.createDependencies(repos: repos, dependencies: rootDeps)),
            products: [],
            version: nil
        )

        // Create the manifests from mock packages.
        var manifests = Dictionary(items: packages.map { package -> (MockManifestLoader.Key, Manifest) in
            let url = repos[package.name]!.url
            let manifest = Manifest(
                path: path.appending(component: Manifest.filename),
                url: url,
                package: PackageDescription.Package(
                    name: package.name,
                    dependencies: MockManifestGraph.createDependencies(repos: repos, dependencies: package.dependencies)),
                products: [],
                version: package.version)
            return (MockManifestLoader.Key(url: url, version: package.version), manifest)
        })
        // Add the root manifest.
        manifests[MockManifestLoader.Key(url: path.asString, version: nil)] = rootManifest

        manifestLoader = MockManifestLoader(manifests: manifests)
        self.manifests = manifests
        self.repos = repos
    }

    /// Maps MockDependencies into PackageDescription's Dependency array.
    private static func createDependencies(repos: [String: RepositorySpecifier], dependencies: [MockDependency]) -> [PackageDescription.Package.Dependency] {
        return dependencies.map { dependency in
            return .Package(url: repos[dependency.name]?.url ?? "//\(dependency.name)", versions: dependency.version)
        }
    }
}
