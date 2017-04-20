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
import class PackageDescription4.Package
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
    var managedDependenciesData = [AnySequence<ManagedDependency>]()

    typealias PartialGraphData = (currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>)
    var partialGraphs = [PartialGraphData]()

    func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>) {
        partialGraphs.append((currentGraph, dependencies, missingURLs))
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

    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
        managedDependenciesData.append(dependencies)
    }
}

extension Workspace {

    fileprivate static func createWith(
        rootPackage path: AbsolutePath,
        manifestLoader: ManifestLoaderProtocol = sharedManifestLoader,
        delegate: WorkspaceDelegate = TestWorkspaceDelegate(),
        fileSystem: FileSystem = localFileSystem,
        repositoryProvider: RepositoryProvider = GitRepositoryProvider()
    ) -> Workspace {
        return Workspace(
            dataPath: path.appending(component: ".build"),
            editablesPath: path.appending(component: "Packages"),
            pinsFile: path.appending(component: "Package.pins"),
            manifestLoader: manifestLoader,
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            fileSystem: fileSystem,
            repositoryProvider: repositoryProvider)
    }

    @discardableResult
    fileprivate func loadPackageGraph(rootPackages: [AbsolutePath], diagnostics: DiagnosticsEngine) -> PackageGraph {
        return loadPackageGraph(root: WorkspaceRoot(packages: rootPackages), diagnostics: diagnostics)
    }

    fileprivate func updateDependencies(rootPackages: [AbsolutePath], diagnostics: DiagnosticsEngine, repin: Bool = false) {
        return updateDependencies(root: WorkspaceRoot(packages: rootPackages), diagnostics: diagnostics, repin: repin)
    }

    fileprivate func pin(
        dependency: ManagedDependency,
        packageName: String,
        rootPackages: [AbsolutePath],
        diagnostics: DiagnosticsEngine,
        version: Version? = nil,
        branch: String? = nil,
        revision: String? = nil,
        reason: String? = nil
    ) throws {
        try pin(
            dependency: dependency,
            packageName: packageName,
            root: WorkspaceRoot(packages: rootPackages),
            diagnostics: diagnostics,
            version: version,
            branch: branch,
            revision: revision,
            reason: reason)
    }
}

extension ManagedDependency {
    var checkoutState: CheckoutState? {
        if case .checkout(let checkoutState) = state {
            return checkoutState
        }
        return nil
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
            initGitRepo(testRepoPath)
            let testRepo = GitRepository(path: testRepoPath)

            try localFileSystem.writeFileContents(testRepoPath.appending(component: "Package.swift")) {
                $0 <<< "import PackageDescription" <<< "\n"
                $0 <<< "let package = Package(" <<< "\n"
                $0 <<< "    name: \"test-repo\"" <<< "\n"
                $0 <<< ")" <<< "\n"
            }
            try testRepo.stage(file: "Package.swift")
            try testRepo.commit()
            try testRepo.tag(name: "initial")
            let initialRevision = try testRepo.getCurrentRevision()

            // Add a couple files and a directory.
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            try testRepo.stage(file: "test.txt")
            try testRepo.commit()
            try testRepo.tag(name: "test-tag")
            let currentRevision = try testRepo.getCurrentRevision()

            // Create the initial workspace.
            do {
                let workspace = Workspace.createWith(rootPackage: path)
                XCTAssertTrue(workspace.managedDependencies.values.map{$0}.isEmpty)

                // Do a low-level clone.
                let state = CheckoutState(revision: currentRevision)
                let checkoutPath = try workspace.clone(repository: testRepoSpec, at: state)
                XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            }

            // Re-open the workspace, and check we know the checkout version.
            do {
                let workspace = Workspace.createWith(rootPackage: path)
                let dependencies = workspace.managedDependencies
                XCTAssertEqual(dependencies.values.map{ $0.repository }, [testRepoSpec])
                if let dependency = dependencies[testRepoSpec] {
                    XCTAssertEqual(dependency.name, "test-repo")
                    XCTAssertEqual(dependency.repository, testRepoSpec)
                    XCTAssertEqual(dependency.checkoutState?.revision, currentRevision)
                }

                // Check we can move to a different revision.
                let state = CheckoutState(revision: initialRevision)
                let checkoutPath = try workspace.clone(repository: testRepoSpec, at: state)
                XCTAssert(!localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            }

            // Re-check the persisted state.
            let statePath: AbsolutePath
            do {
                let workspace = Workspace.createWith(rootPackage: path)
                let dependencies = workspace.managedDependencies
                statePath = dependencies.statePath
                XCTAssertEqual(dependencies.values.map{ $0.repository }, [testRepoSpec])
                if let dependency = dependencies[testRepoSpec] {
                    XCTAssertEqual(dependency.name, "test-repo")
                    XCTAssertEqual(dependency.repository, testRepoSpec)
                    XCTAssertEqual(dependency.checkoutState?.revision, initialRevision)
                }
            }

            // Blow away the workspace state file, and check we can get back to a good state.
            try removeFileTree(statePath)
            do {
                let workspace = Workspace.createWith(rootPackage: path)
                XCTAssert(workspace.managedDependencies.values.map{$0}.isEmpty)
                let state = CheckoutState(revision: currentRevision)
                _ = try workspace.clone(repository: testRepoSpec, at: state)
                XCTAssertEqual(workspace.managedDependencies.values.map{$0.repository}, [testRepoSpec])
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: graph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have checkouts for A & AA.
            for name in ["A", "AA"] {
                let revision = try GitRepository(path: AbsolutePath(graph.repo(name).url)).getCurrentRevision()
                let state = CheckoutState(revision: revision, version: v1)
                _ = try workspace.clone(repository: graph.repo(name), at: state)
            }

            // Load the "current" manifests.
            let diagnostics = DiagnosticsEngine()
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssertEqual(manifests.root.manifests[0], graph.rootManifest)
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(manifestGraph.repo(name).url)).getCurrentRevision()
                let state = CheckoutState(revision: revision, version: v1)
                _ = try workspace.clone(repository: manifestGraph.repo(name), at: state)
            }

            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            // Validate the graph has the correct basic structure.
            XCTAssertEqual(graph.packages.count, 2)
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
        let delegate = TestWorkspaceDelegate()
        let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate, fileSystem: fs, repositoryProvider: manifestGraph.repoProvider!)
        let diagnostics = DiagnosticsEngine()
        let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssertEqual(graph.packages.count, 2)
        XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])

        let partialGraph = delegate.partialGraphs[0]
        XCTAssertEqual(partialGraph.currentGraph.packages.map{$0.name}, ["Root"])
        XCTAssertEqual(partialGraph.missingURLs, ["/RootPkg/A"])
        XCTAssertTrue(partialGraph.dependencies.map{$0}.isEmpty)

        workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssertEqual(delegate.partialGraphs.count, 1)
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)

            // Ensure delegates haven't been called yet.
            XCTAssert(delegate.fetched.isEmpty)
            XCTAssert(delegate.cloned.isEmpty)
            XCTAssert(delegate.checkedOut.isEmpty)

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(manifestGraph.repo(name).url)).getCurrentRevision()
                let state = CheckoutState(revision: revision, version: v1)
                _ = try workspace.clone(repository: manifestGraph.repo(name), at: state)
            }

            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

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

    func testSymlinkedDependency() {
        mktmpdir { path in
            var fs = localFileSystem
            let root = path.appending(components: "root")
            let dep = path.appending(components: "dep")
            let depSym = path.appending(components: "depSym")

            // Create root package.
            try fs.writeFileContents(root.appending(components: "Sources", "root", "main.swift")) { $0 <<< "" }
            try fs.writeFileContents(root.appending(component: "Package.swift")) {
                $0 <<< "// swift-tools-version:4.0" <<< "\n"
                $0 <<< "import PackageDescription" <<< "\n"
                $0 <<< "let package = Package(" <<< "\n"
                $0 <<< "    name: \"root\"," <<< "\n"
                $0 <<< "    dependencies: [.package(url: \"../depSym\", from: \"1.0.0\")]," <<< "\n"
                $0 <<< "    targets: [.target(name: \"root\", dependencies: [\"dep\"])]" <<< "\n"
                $0 <<< ")" <<< "\n"
            }

            // Create dependency.
            try fs.writeFileContents(dep.appending(components: "Sources", "dep", "lib.swift")) { $0 <<< "" }
            try fs.writeFileContents(dep.appending(component: "Package.swift")) {
                $0 <<< "// swift-tools-version:4.0" <<< "\n"
                $0 <<< "import PackageDescription" <<< "\n"
                $0 <<< "let package = Package(" <<< "\n"
                $0 <<< "    name: \"dep\"," <<< "\n"
                $0 <<< "    products: [.library(name: \"dep\", targets: [\"dep\"])]," <<< "\n"
                $0 <<< "    targets: [.target(name: \"dep\")]" <<< "\n"
                $0 <<< ")" <<< "\n"
            }
            do {
                let depGit = GitRepository(path: dep)
                try depGit.create()
                try depGit.stageEverything()
                try depGit.commit()
                try depGit.tag(name: "1.0.0")
            }

            // Create symlink to the dependency.
            try createSymlink(depSym, pointingAt: dep)

            // Try to load.
            let workspace = Workspace.createWith(rootPackage: root)
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [root], diagnostics: diagnostics)
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(graph.lookup("dep").version, v1)
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
                return  Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            }

            do {
                // Create the workspace.
                let workspace = try createWorkspace()

                // Turn off auto pinning.
                try workspace.pinsStore.load().setAutoPin(on: false)
                // Ensure delegates haven't been called yet.
                XCTAssert(delegate.fetched.isEmpty)
                XCTAssert(delegate.cloned.isEmpty)
                XCTAssert(delegate.checkedOut.isEmpty)
                XCTAssert(delegate.removed.isEmpty)

                // Load the package graph.
                let diagnostics = DiagnosticsEngine()
                let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)

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
                let diagnostics = DiagnosticsEngine()
                workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                // Test the delegates after update.
                XCTAssert(delegate.fetched.count == 2)
                XCTAssert(delegate.cloned.count == 2)
                for (_, repoPath) in manifestGraph.repos {
                    XCTAssert(delegate.fetched.contains(repoPath.url))
                    XCTAssert(delegate.cloned.contains(repoPath.url))
                }
                XCTAssertEqual(delegate.checkedOut[repoPath.asString], "1.0.1")
                XCTAssertEqual(delegate.removed, [manifestGraph.repo("AA").url])

                let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
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
            initGitRepo(testRepoPath)

            let testRepo = GitRepository(path: testRepoPath)
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "Package.swift")) {
                $0 <<< "import PackageDescription" <<< "\n"
                $0 <<< "let package = Package(" <<< "\n"
                $0 <<< "    name: \"test-repo\"" <<< "\n"
                $0 <<< ")" <<< "\n"
            }
            try testRepo.stage(file: "Package.swift")
            try testRepo.commit()
            try testRepo.tag(name: "initial")

            let workspace = Workspace.createWith(rootPackage: path)
            let state = CheckoutState(revision: Revision(identifier: "initial"))
            let checkoutPath = try workspace.clone(repository: testRepoSpec, at: state)
            XCTAssertEqual(workspace.managedDependencies.values.map{ $0.repository }, [testRepoSpec])

            // Drop a build artifact in data directory.
            let buildArtifact = workspace.dataPath.appending(component: "test.o")
            try localFileSystem.writeFileContents(buildArtifact, bytes: "Hi")

            // Sanity checks.
            XCTAssert(localFileSystem.exists(buildArtifact))
            XCTAssert(localFileSystem.exists(checkoutPath))

            let diagnostics = DiagnosticsEngine()
            workspace.clean(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            XCTAssertEqual(workspace.managedDependencies.values.map{ $0.repository }, [testRepoSpec])
            XCTAssert(localFileSystem.exists(workspace.dataPath))
            // The checkout should be safe.
            XCTAssert(localFileSystem.exists(checkoutPath))
            // Build artifact should be removed.
            XCTAssertFalse(localFileSystem.exists(buildArtifact))

            // Add build artifact again.
            try localFileSystem.writeFileContents(buildArtifact, bytes: "Hi")
            XCTAssert(localFileSystem.exists(buildArtifact))

            workspace.reset(with: diagnostics)
            // Everything should go away.
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssertFalse(localFileSystem.exists(buildArtifact))
            XCTAssertFalse(localFileSystem.exists(checkoutPath))
            XCTAssertFalse(localFileSystem.exists(workspace.dataPath))
            XCTAssertTrue(workspace.managedDependencies.values.map{$0}.isEmpty)
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            // Sanity checks.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])

            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }

            func getDependency(_ manifest: Manifest) -> ManagedDependency {
                return workspace.managedDependencies[manifest.url]!
            }

            // Get the dependency for package A.
            let dependency = getDependency(aManifest)
            XCTAssertEqual(dependency.name, "A")
            // It should not be in edit mode.
            XCTAssert(dependency.state.isCheckout)
            // Put the dependency in edit mode at its current revision.
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision)
            XCTAssertFalse(diagnostics.hasErrors)

            let editedDependency = getDependency(aManifest)
            // It should be in edit mode.
            XCTAssert(editedDependency.state == .edited(nil))
            // Check the based on data.
            XCTAssertEqual(editedDependency.basedOn?.subpath, dependency.subpath)
            XCTAssertEqual(editedDependency.basedOn?.checkoutState, dependency.checkoutState)

            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            // Get the repo from edits path.
            let editRepo = GitRepository(path: editRepoPath)
            // Ensure that the editable checkout's remote points to the original repo path.
            XCTAssertEqual(try editRepo.remotes()[0].url, manifestGraph.repo("A").url)
            // Check revision and head.
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.checkoutState?.revision)
            // FIXME: Current checkout behavior seems wrong, it just resets and doesn't leave checkout to a detached head.
          #if false
            XCTAssertEqual(try popen([Git.tool, "-C", editRepoPath.asString, "rev-parse", "--abbrev-ref", "HEAD"]).chomp(), "HEAD")
          #endif

            workspace.edit(
                dependency: editedDependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision)
            XCTAssert(diagnostics.hasErrors)
            XCTAssert(diagnostics.diagnostics.contains(where: {
                $0.id == WorkspaceDiagnostics.DependencyAlreadyInEditMode.id
            }))

            do {
                // Reopen workspace and check if we maintained the state.
                let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
                let dependency = workspace.managedDependencies[aManifest.url]!
                XCTAssert(dependency.state == .edited(nil))
            }

            // Make the edited package "invalid" and ensure we can get the errors.
            do {
                localFileSystem.removeFileTree(path.appending(components: "A", "file.swift"))
                let diagnostics = DiagnosticsEngine()
                workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
                XCTAssertTrue(diagnostics.hasErrors)
            }

            // We should be able to unedit the dependency.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssert(getDependency(aManifest).state.isCheckout)
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            func getDependency(_ manifest: Manifest) -> ManagedDependency {
                return workspace.managedDependencies[manifest.url]!
            }
            // Get the dependency for package A.
            let dependency = getDependency(aManifest)

            // We should error out if we try to edit on a non existent revision.
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: Revision(identifier: "non-existent-revision"))
            XCTAssert(diagnostics.hasErrors)
            XCTAssert(diagnostics.diagnostics.contains(where: {
                $0.id == WorkspaceDiagnostics.RevisionDoesNotExist.id
            }))

            // Put the dependency in edit mode at its current revision on a new branch.
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision,
                checkoutBranch: "BugFix")
            XCTAssert(diagnostics.hasErrors)
            let editedDependency = getDependency(aManifest)
            XCTAssert(editedDependency.state == .edited(nil))

            let editRepoPath = workspace.editablesPath.appending(editedDependency.subpath)
            let editRepo = GitRepository(path: editRepoPath)
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.checkoutState?.revision)
            XCTAssertEqual(try editRepo.currentBranch(), "BugFix")
            // Unedit it.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssert(getDependency(aManifest).state.isCheckout)

            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision,
                checkoutBranch: "master")
            XCTAssert(diagnostics.hasErrors)
            XCTAssert(diagnostics.diagnostics.contains(where: {
                $0.id == WorkspaceDiagnostics.BranchAlreadyExists.id
            }))
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())
            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            // Sanity checks.
            XCTAssertEqual(graph.packages.count, 2)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "Root"])

            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            guard let aManifest = manifests.lookup(manifest: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            func getDependency(_ manifest: Manifest) -> ManagedDependency {
                return workspace.managedDependencies[manifest.url]!
            }
            let dependency = getDependency(aManifest)
            // Put the dependency in edit mode.
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision,
                checkoutBranch: "bugfix")
            XCTAssertFalse(diagnostics.hasErrors)

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
            } catch let error as WorkspaceDiagnostics.UncommitedChanges {
                XCTAssertEqual(error.repositoryPath, editRepoPath)
            }
            // Commit and try to unedit.
            try editRepo.commit()
            do {
                try workspace.unedit(dependency: editedDependency, forceRemove: false)
                XCTFail("Unexpected edit success")
            } catch let error as WorkspaceDiagnostics.UnpushedChanges {
                XCTAssertEqual(error.repositoryPath, editRepoPath)
            }
            // Force remove.
            try workspace.unedit(dependency: editedDependency, forceRemove: true)
            XCTAssert(getDependency(aManifest).state.isCheckout)
            XCTAssertFalse(exists(editRepoPath))
            XCTAssertFalse(exists(workspace.editablesPath))
        }
    }

    func testEditAndPinning() throws {
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
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!

        // Create the workspace.
        let workspace = Workspace.createWith(rootPackage: path,
                                             manifestLoader: manifestGraph.manifestLoader,
                                             delegate: TestWorkspaceDelegate(),
                                             fileSystem: fs,
                                             repositoryProvider: provider)
        // Load the package graph.
        let diagnostics = DiagnosticsEngine()
        let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        guard let aManifest = manifests.lookup(manifest: "A") else {
            return XCTFail("Expected manifest for package A not found")
        }

        func getDependency(_ manifest: Manifest) -> ManagedDependency {
            return workspace.managedDependencies[manifest.url]!
        }

        // Get the dependency for package A.
        let dependency = getDependency(aManifest)
        // It should not be in edit mode.
        XCTAssert(dependency.state.isCheckout)
        // Put the dependency in edit mode at its current revision.
        workspace.edit(
            dependency: dependency,
            packageName: aManifest.name,
            diagnostics: diagnostics,
            revision: dependency.checkoutState!.revision)
        XCTAssertFalse(diagnostics.hasErrors)

        let editedDependency = getDependency(aManifest)
        // It should be in edit mode.
        XCTAssert(editedDependency.state == .edited(nil))
        // Set up for pinning B to v1
        guard let (_, dep) = manifests.lookup(package: "B") else {
            return XCTFail("Expected manifest for package B not found")
        }
        // Attempt to pin dependency B.
        try workspace.pin(dependency: dep, packageName: "B", rootPackages: [path], diagnostics: diagnostics, version: v1)
        // Validate the versions.
        let reloadedGraph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssert(reloadedGraph.lookup("A").version == v1)
        XCTAssert(reloadedGraph.lookup("B").version == v1)
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        // We should still get v1 even though an update is available.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            workspace.reset(with: diagnostics)
        }

        // Updating dependencies shouldn't matter.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
        }

        // Updating dependencies with repinning should do the actual update.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("AA").version == v1)
            // We should have pin for AA automatically.
            XCTAssertNotNil(try workspace.pinsStore.load().pinsMap["A"])
            XCTAssertNotNil(try workspace.pinsStore.load().pinsMap["AA"])
        }

        // Unpin all of the dependencies.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.load().unpinAll()
            // Reset so we have a clean workspace.
            let diagnostics = DiagnosticsEngine()
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            try workspace.pinsStore.load().setAutoPin(on: false)
        }

        // Pin at A at v1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            try workspace.pin(dependency: dep, packageName: "A", rootPackages: [path], diagnostics: diagnostics, version: v1)

            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
        }

        // Updating and repinning shouldn't pin new deps which are introduced.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.1")
            XCTAssert(graph.lookup("AA").version == v1)
            XCTAssertNotNil(try workspace.pinsStore.load().pinsMap["A"])
            // We should not have pinned AA.
            XCTAssertNil(try workspace.pinsStore.load().pinsMap["AA"])
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Pins "A" at v1.
        func pin() throws {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            // Try unpinning something which is not pinned.
            XCTAssertThrows(PinOperationError.notPinned) {
                try workspace.pinsStore.load().unpin(package: "A")
            }
            try workspace.pin(dependency: dep, packageName: "A", rootPackages: [path], diagnostics: diagnostics, version: v1)
        }

        // Turn off autopin.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.load().setAutoPin(on: false)
        }

        // Package graph should load 1.0.1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.1")
        }

        // Pin package to v1.
        try pin()

        // Package graph should load v1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.0")
        }

        // Unpin package.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.load().unpin(package: "A")
            let diagnostics = DiagnosticsEngine()
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Package graph should load 1.0.1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.1")
        }

        // Pin package to v1.
        try pin()

        // Package *update* should load v1 after pinning.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == "1.0.0")
        }

        // Package *update* should load 1.0.1 with repinning.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Package graph should load v1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Pin the dependencies.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()

            let pinsStore = try workspace.pinsStore.load()
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            try workspace.pinAll(pinsStore: pinsStore, dependencyManifests: manifests)
            // Reset so we have a clean workspace.
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Add a new version of dependencies.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "1.0.1")

        // Loading the workspace now should load v1 of both dependencies.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Updating the dependencies shouldn't update to 1.0.1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
        }

        // Unpin all of the dependencies.
        do {
            let workspace = newWorkspace()
            try workspace.pinsStore.load().unpinAll()
            // Reset so we have a clean workspace.
            let diagnostics = DiagnosticsEngine()
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Loading the workspace now should load 1.0.1 of both dependencies.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // Load and pin the dependencies.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            XCTAssert(graph.lookup("B").version == v1)
            let pinsStore = try workspace.pinsStore.load()
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            try workspace.pinAll(pinsStore: pinsStore, dependencyManifests: manifests)
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Add a new version of dependencies.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")
        try provider.specifierMap[manifestGraph.repo("B")]!.tag(name: "1.0.1")

        // Updating the dependencies with repin should update to 1.0.1.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        func pin(at version: Version, diagnostics: DiagnosticsEngine) throws {
            let workspace = newWorkspace()
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            guard let (_, dep) = manifests.lookup(package: "A") else {
                return XCTFail("Expected manifest for package A not found")
            }
            try workspace.pin(dependency: dep, packageName: "A", rootPackages: [path], diagnostics: diagnostics, version: version)
        }

        // Pinning at v1 should work.
        do {
            let workspace = newWorkspace()
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            try pin(at: v1, diagnostics: diagnostics)
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Add a the tag which will make resolution unstatisfiable.
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        do {
            let workspace = newWorkspace()
            var diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(graph.lookup("A").version == v1)
            // Pinning non existant version should fail.
            try pin(at: "1.0.2", diagnostics: diagnostics)
            XCTAssertTrue(diagnostics.diagnostics[0].localizedDescription.contains("A @ 1.0.2"))

            // Pinning an unstatisfiable version should fail.
            diagnostics = DiagnosticsEngine()
            try pin(at: "1.0.1", diagnostics: diagnostics)

            // But we should still be able to repin at v1.
            diagnostics = DiagnosticsEngine()
            try pin(at: v1, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            // And also after unpinning.
            try workspace.pinsStore.load().unpinAll()
            try pin(at: v1, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
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
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs,
                repositoryProvider: provider)
        }

        // We should not be able to load package graph.
        do {
            let diagnostics = DiagnosticsEngine()
            newWorkspace().loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            // This output diagnostics isn't stable. It could be either A or B.
            XCTAssertTrue(diagnostics.diagnostics[0].localizedDescription.contains("@ 1.0.0..<1.0.1"))
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

        let provider = manifestGraph.repoProvider!

        func newWorkspace(with delegate: WorkspaceDelegate) -> Workspace {
            return Workspace.createWith(
                rootPackage: path,
                manifestLoader: manifestGraph.manifestLoader,
                delegate: delegate,
                fileSystem: fs,
                repositoryProvider: provider)
        }

        do {
            let delegate = TestWorkspaceDelegate()
            let workspace = newWorkspace(with: delegate)
            try workspace.pinsStore.load().setAutoPin(on: false)

            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            guard let (_, dep) = manifests.lookup(package: "B") else {
                return XCTFail("Expected manifest for package B not found")
            }
            try workspace.pin(dependency: dep, packageName: "B", rootPackages: [path], diagnostics: diagnostics, version: v1)
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Try updating with repin and versions shouldn't change.
        do {
            let delegate = TestWorkspaceDelegate()
            let workspace = newWorkspace(with: delegate)
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            let g = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(g.lookup("A").version == v1)
            XCTAssert(g.lookup("B").version == v1)
            workspace.reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.0.1")

        do {
            let delegate = TestWorkspaceDelegate()
            let workspace = newWorkspace(with: delegate)
            let diagnostics = DiagnosticsEngine()
            let g = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(g.lookup("A").version == "1.0.1")
            // FIXME: We also cloned B because it has a pin.
            XCTAssertNotNil(workspace.managedDependencies[manifestGraph.repo("B")])
        }

        do {
            let delegate = TestWorkspaceDelegate()
            let workspace = newWorkspace(with: delegate)
            XCTAssertTrue(delegate.warnings.isEmpty)
            let diagnostics = DiagnosticsEngine()
            workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(delegate.warnings.contains("Consider unpinning B, it is pinned at 1.0.0 but the dependency is not present."))
            let g = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssert(g.lookup("A").version == "1.0.1")
            // This dependency should be removed on updating dependencies because it is not referenced anywhere.
            XCTAssertNil(workspace.managedDependencies[manifestGraph.repo("B")])
        }
    }

    func testBranchAndRevision() throws {
        typealias Package = PackageDescription4.Package

        mktmpdir { path in
            let root = path.appending(component: "root")
            let dep1 = path.appending(component: "dep")
            let dep2 = path.appending(component: "dep2")
            let dep1File = dep1.appending(components: "Sources", "dep", "develop.swift")
            let dep2File = dep2.appending(components: "Sources", "dep2", "develop.swift")

            var manifests: [MockManifestLoader.Key: Manifest] = [:]

            for dep in [dep1, dep2] {
                try makeDirectories(dep)
                initGitRepo(dep)
                let name = dep.basename

                // Create package manifest.
                let pkg = Package(
                    name: name,
                    products: [
                        .library(name: name, targets: [name]),
                    ],
                    targets: [
                        .target(name: name),
                    ]
                )
                let manifest = Manifest(
                    path: dep.appending(component: Manifest.filename),
                    url: dep.asString,
                    package: .v4(pkg),
                    version: nil)
                manifests[MockManifestLoader.Key(url: dep.asString)] = manifest
            }

            let repo1 = GitRepository(path: dep1)
            try repo1.checkout(newBranch: "develop")
            try localFileSystem.createDirectory(dep1File.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(dep1File, bytes: "")
            try repo1.stageEverything()
            try repo1.commit()
            let dep1Revision = try repo1.getCurrentRevision()

            let repo2 = GitRepository(path: dep2)
            try localFileSystem.createDirectory(dep2File.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(dep2File, bytes: "")
            try repo2.stageEverything()
            try repo2.commit()
            let dep2Revision = try repo2.getCurrentRevision()

            do {
                try makeDirectories(root)
                initGitRepo(root)
                let sourceFile = root.appending(components: "Sources", "root", "source.swift")
                try localFileSystem.createDirectory(sourceFile.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(sourceFile, bytes: "")
                let manifest = Manifest(
                    path: root.appending(component: Manifest.filename),
                    url: root.asString,
                    package: .v4(.init(
                        name: "root",
                        dependencies: [
                            .package(url: dep1.asString, .branch("develop")),
                            .package(url: dep2.asString, .revision(dep2Revision.identifier)),
                        ],
                        targets: [.target(name: "root", dependencies: ["dep"])])
                    ),
                    version: nil)
                manifests[MockManifestLoader.Key(url: root.asString)] = manifest
            }


            func getWorkspace() -> Workspace {
                return Workspace.createWith(
                    rootPackage: root,
                    manifestLoader: MockManifestLoader(manifests: manifests))
            }

            do {
                let diagnostics = DiagnosticsEngine()
                getWorkspace().loadPackageGraph(rootPackages: [root], diagnostics: diagnostics)
                XCTAssertNoDiagnostics(diagnostics)
            }

            // Check dep1.
            do {
                let workspace = getWorkspace()
                let dependency = workspace.managedDependencies[dep1.asString]!
                XCTAssertEqual(dependency.checkoutState, CheckoutState(revision: dep1Revision, branch: "develop"))
                XCTAssertEqual(dep1Revision,
                    try GitRepository(path: workspace.checkoutsPath.appending(dependency.subpath)).getCurrentRevision())

            }

            // Check dep2.
            do {
                let workspace = getWorkspace()
                let dependency = workspace.managedDependencies[dep2.asString]!
                XCTAssertEqual(dependency.checkoutState, CheckoutState(revision: dep2Revision, branch: nil))
                XCTAssertEqual(dep2Revision,
                    try GitRepository(path: workspace.checkoutsPath.appending(dependency.subpath)).getCurrentRevision())
            }

            // Check pins.
            do {
                let workspace = getWorkspace()
                let dep1Pin = try workspace.pinsStore.load().pinsMap["dep"]!
                XCTAssertEqual(dep1Pin.state, CheckoutState(revision: dep1Revision, branch: "develop"))

                let dep2Pin = try workspace.pinsStore.load().pinsMap["dep2"]!
                XCTAssertEqual(dep2Pin.state, CheckoutState(revision: dep2Revision))
            }

            // Add a commit in the branch and check if update fetches it.
            try localFileSystem.writeFileContents(dep1File, bytes: "// update")
            try repo1.stageEverything()
            try repo1.commit()

            // Reset workspace.
            let diagnostics = DiagnosticsEngine()
            getWorkspace().reset(with: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            // Loading package graph shouldn't update the branches because of pin.
            do {
                let workspace = getWorkspace()
                let diagnostics = DiagnosticsEngine()
                workspace.loadPackageGraph(rootPackages: [root], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)

                let dependency = workspace.managedDependencies[dep1.asString]!
                XCTAssertEqual(dependency.checkoutState, CheckoutState(revision: dep1Revision, branch: "develop"))
                XCTAssertEqual(dep1Revision,
                    try GitRepository(path: workspace.checkoutsPath.appending(dependency.subpath)).getCurrentRevision())
            }

            // Do an update and check if branch is updated.
            do {
                let workspace = getWorkspace()
                let diagnostics = DiagnosticsEngine()
                workspace.updateDependencies(rootPackages: [root], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                let dependency = workspace.managedDependencies[dep1.asString]!
                let revision = try repo1.getCurrentRevision()
                XCTAssertEqual(dependency.checkoutState, CheckoutState(revision: revision, branch: "develop"))
                XCTAssertEqual(revision,
                    try GitRepository(path: workspace.checkoutsPath.appending(dependency.subpath)).getCurrentRevision())
            }
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
                return Workspace(
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
                try workspace.pinsStore.load().setAutoPin(on: false)
            }

            do {
                let workspace = try createWorkspace()
                // Load first two packages.
                let diagnostics = DiagnosticsEngine()
                let graph = workspace.loadPackageGraph(rootPackages: Array(roots[0..<2]), diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "B", "C", "root1", "root2"])
                XCTAssertEqual(graph.rootPackages.map{ $0.name }.sorted(), ["root1", "root2"])
                XCTAssertEqual(graph.lookup("A").version, "1.5.0")
            }

            // FIXME: We shouldn't need to reset workspace here, but we have to because we introduce
            // incompatible constraints via root package 3. This happens because when we add new dependencies and resolve in workspace
            // we constraint old manifests to previously resolved versions.
            do {
                let workspace = try createWorkspace()
                let diagnostics = DiagnosticsEngine()
                workspace.reset(with: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
            }

            do {
                let workspace = try createWorkspace()
                // Load all packages.
                let diagnostics = DiagnosticsEngine()
                let graph = workspace.loadPackageGraph(rootPackages: roots, diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), ["A", "B", "C", "D", "root1", "root2", "root3"])
                XCTAssertEqual(graph.rootPackages.map{ $0.name }.sorted(), ["root1", "root2", "root3"])
                XCTAssertEqual(graph.lookup("A").version, v1)

                // FIXME: We need to reset because we apply constraints for current checkouts (see the above note).
                workspace.reset(with: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)

                // Remove one of the packages.
                let newGraph = workspace.loadPackageGraph(rootPackages: Array(roots[0..<2]), diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
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
            let workspace = Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)

            // Put A in edit mode.
            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            let aManifest = manifests.lookup(manifest: "A")!
            let dependency = workspace.managedDependencies[aManifest.url]!
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                revision: dependency.checkoutState!.revision)
            XCTAssertFalse(diagnostics.hasErrors)

            // We should retain the original pin for a package which is in edit mode.
            XCTAssertEqual(try workspace.pinsStore.load().pinsMap["A"]?.state.version, v1)

            // Remove edited checkout.
            try removeFileTree(workspace.editablesPath)
            delegate.warnings.removeAll()
            workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
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
            func createWorkspace() -> Workspace {
                return  Workspace.createWith(rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: delegate)
            }

            do {
                let workspace = createWorkspace()
                let diagnostics = DiagnosticsEngine()
                workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
                let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)

                let bDependency = manifests.lookup(package: "B")!.dependency
                workspace.edit(
                    dependency: bDependency,
                    packageName: "B",
                    diagnostics: diagnostics,
                    revision: bDependency.checkoutState!.revision)
                XCTAssertFalse(diagnostics.hasErrors)

                XCTAssertEqual(manifests.lookup(package: "A")!.dependency.checkoutState?.version, v1)
                XCTAssertEqual(try workspace.pinsStore.load().pinsMap["A"]?.state.version, v1)
                XCTAssertEqual(try workspace.pinsStore.load().pinsMap["B"]?.state.version, v1)

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
                let workspace = createWorkspace()
                let diagnostics = DiagnosticsEngine()
                workspace.updateDependencies(rootPackages: [path], diagnostics: diagnostics, repin: true)
                XCTAssertFalse(diagnostics.hasErrors)
                let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
                let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
                XCTAssertFalse(diagnostics.hasErrors)
                XCTAssertEqual(manifests.lookup(package: "A")!.dependency.checkoutState?.version, "1.0.1")
                XCTAssertEqual(try workspace.pinsStore.load().pinsMap["A"]?.state.version, "1.0.1")
                XCTAssertTrue(manifests.lookup(package: "B")!.dependency.state == .edited(nil))
                XCTAssertEqual(try workspace.pinsStore.load().pinsMap["B"]?.state.version, v1)
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
            return Workspace(
                dataPath: AbsolutePath.root.appending(component: ".build"),
                editablesPath: AbsolutePath.root.appending(component: "Packages"),
                pinsFile: AbsolutePath.root.appending(component: "Package.pins"),
                manifestLoader: manifestLoader,
                currentToolsVersion: toolsVersion,
                delegate: TestWorkspaceDelegate(),
                fileSystem: fs)
        }

        // We should be able to load when no there is no swift-tools-version defined.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "3.1.0"))
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: roots, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Limit root0 to 3.1.0
        try fs.writeFileContents(swiftVersion(for: roots[0]), bytes: "// swift-tools-version:3.1")

        // Test one root package having swift-version.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "4.0.0"))
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: roots, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Limit root1 to 4.0.0
        try fs.writeFileContents(swiftVersion(for: roots[1]), bytes: "// swift-tools-version:4.0.0")

        // Test both having swift-version but different.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "4.0.0"))
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: roots, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
        }

        // Failing case.
        do {
            let workspace = try createWorkspace(ToolsVersion(version: "3.1.0"))
            let diagnostics = DiagnosticsEngine()
            workspace.loadPackageGraph(rootPackages: roots, diagnostics: diagnostics)
            let errorDesc = diagnostics.diagnostics[0].localizedDescription
            XCTAssertEqual(errorDesc, "The package at '/root1' requires a minimum Swift tools version of 4.0.0 but currently at 3.1.0")
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

            let workspace = Workspace.createWith(rootPackage: roots[0])

            let diagnostics = DiagnosticsEngine()
            let manifests = workspace.loadRootManifests(packages: roots, diagnostics: diagnostics)

            XCTAssertEqual(manifests.count, 1)
            XCTAssertEqual(diagnostics.diagnostics.count, 2)
        }
    }

    func testTOTPackageEdit() throws {
        mktmpdir { path in
            let manifestGraph = try MockManifestGraph(at: path,
                rootDeps: [
                    MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
                ],
                packages: [
                    MockPackage("A", version: v1),
                    MockPackage("A", version: nil),
                ]
            )
            // Create the workspace.
            let workspace = Workspace.createWith(
                rootPackage: path, manifestLoader: manifestGraph.manifestLoader, delegate: TestWorkspaceDelegate())

            func getDependency(_ manifest: Manifest) -> ManagedDependency {
                return workspace.managedDependencies[manifest.url]!
            }

            // Load the package graph.
            let diagnostics = DiagnosticsEngine()
            let graph = workspace.loadPackageGraph(rootPackages: [path], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssertEqual(graph.packages.count, 2)

            let rootManifests = workspace.loadRootManifests(packages: [path], diagnostics: diagnostics)
            let manifests = workspace.loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            let aManifest = manifests.lookup(manifest: "A")!

            // Get the dependency for package A.
            let dependency = getDependency(aManifest)

            // Edit it at ToT path.
            let tot = path.appending(component: "tot")
            workspace.edit(
                dependency: dependency,
                packageName: aManifest.name,
                diagnostics: diagnostics,
                path: tot)
            XCTAssertFalse(diagnostics.hasErrors)

            let editedDependency = getDependency(aManifest)

            switch editedDependency.state {
            case .edited(let path):
                XCTAssertEqual(path, tot)
            default: return XCTFail()
            }

            // Check the based on data.
            XCTAssertEqual(editedDependency.basedOn?.subpath, dependency.subpath)
            XCTAssertEqual(editedDependency.basedOn?.checkoutState, dependency.checkoutState)

            // Get the repo from edits path.
            let editRepo = GitRepository(path: tot)
            // Ensure that the editable checkout's remote points to the original repo path.
            XCTAssertEqual(try editRepo.remotes()[0].url, manifestGraph.repo("A").url)

            // Check revision and head.
            XCTAssertEqual(try editRepo.getCurrentRevision(), dependency.checkoutState?.revision)
            XCTAssertEqual(try editRepo.currentBranch(), "HEAD")

            // We should be able to unedit the dependency.
            try workspace.unedit(dependency: editedDependency, forceRemove: false)
            XCTAssert(getDependency(aManifest).state.isCheckout)
            XCTAssertTrue(exists(tot))
            XCTAssertFalse(exists(workspace.editablesPath))
        }
    }

    func testPackageGraphOnlyRootDependency() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
            ],
            packages: [
                MockPackage("B", version: v1),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!

        let workspace = Workspace.createWith(
            rootPackage: path,
            manifestLoader: manifestGraph.manifestLoader,
            delegate: TestWorkspaceDelegate(),
            fileSystem: fs,
            repositoryProvider: provider
        )
        let diagnostics = DiagnosticsEngine()
        let root = WorkspaceRoot(packages: [path], dependencies: [
            .init(url: "/RootPkg/B", requirement: .exact(v1.asPD4Version), location: "rootB"),
        ])

        let graph = workspace.loadPackageGraph(root: root, diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssertEqual(graph.rootPackages.map{$0.name}.sorted(), ["Root"])
        XCTAssertEqual(graph.packages.map{$0.name}.sorted(), ["B", "Root"])
        XCTAssertEqual(graph.targets.map{$0.name}.sorted(), ["B", "Root"])
        XCTAssertEqual(graph.products.map{$0.name}.sorted(), ["B"])
    }

    func testPackageGraphWithGraphRootDependencies() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: Version(1, 0, 0)..<Version(1, .max, .max)),
            ],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("A", version: "1.5.1"),
                MockPackage("B", version: v1),
            ],
            fs: fs
        )
        let provider = manifestGraph.repoProvider!
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.5.1")

        let workspace = Workspace.createWith(
            rootPackage: path,
            manifestLoader: manifestGraph.manifestLoader,
            delegate: TestWorkspaceDelegate(),
            fileSystem: fs,
            repositoryProvider: provider
        )
        let diagnostics = DiagnosticsEngine()
        let root = WorkspaceRoot(packages: [path], dependencies: [
            .init(url: "/RootPkg/B", requirement: .exact(v1.asPD4Version), location: "rootB"),
            .init(url: "/RootPkg/A", requirement: .exact(v1.asPD4Version), location: "rootA"),
        ])

        let graph = workspace.loadPackageGraph(root: root, diagnostics: diagnostics)
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssertEqual(graph.rootPackages.map{$0.name}.sorted(), ["Root"])
        XCTAssertEqual(graph.lookup("A").manifest.version, v1)
        XCTAssertEqual(graph.packages.map{$0.name}.sorted(), ["A", "B", "Root"])
        XCTAssertEqual(graph.targets.map{$0.name}.sorted(), ["A", "B", "Root"])
        XCTAssertEqual(graph.products.map{$0.name}.sorted(), ["A", "B"])
    }

    func testDeletedCheckoutDirectory() throws {
        fixture(name: "DependencyResolution/External/Simple") { path in
            let barRoot = path.appending(component: "Bar")

            let diagnostics = DiagnosticsEngine()
            let delegate = TestWorkspaceDelegate()
            let workspace = Workspace.createWith(rootPackage: barRoot, delegate: delegate)

            workspace.loadPackageGraph(rootPackages: [barRoot], diagnostics: diagnostics)

            try localFileSystem.set(attribute: .mutable, path: workspace.checkoutsPath, recursive: true)
            try removeFileTree(workspace.checkoutsPath)

            workspace.loadPackageGraph(rootPackages: [barRoot], diagnostics: diagnostics)
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssertTrue(delegate.warnings.contains(where: { $0.hasPrefix("Foo") && $0.hasSuffix(" is missing and has been cloned again.") }))
            XCTAssertTrue(isDirectory(workspace.checkoutsPath))
        }
    }

    func testGraphData() throws {
        let path = AbsolutePath("/RootPkg")
        let fs = InMemoryFileSystem()
        let manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [],
            packages: [
                MockPackage("A", version: v1),
                MockPackage("A", version: "1.5.1"),
                MockPackage("B", version: v1),
            ],
            fs: fs)
        let provider = manifestGraph.repoProvider!
        try provider.specifierMap[manifestGraph.repo("A")]!.tag(name: "1.5.1")

        let delegate = TestWorkspaceDelegate()
        let workspace = Workspace.createWith(
            rootPackage: path,
            manifestLoader: manifestGraph.manifestLoader,
            delegate: delegate,
            fileSystem: fs,
            repositoryProvider: provider)
        let diagnostics = DiagnosticsEngine()
        let root = WorkspaceRoot(packages: [], dependencies: [
            .init(url: "/RootPkg/B", requirement: .exact(v1.asPD4Version), location: "rootB"),
            .init(url: "/RootPkg/A", requirement: .exact(v1.asPD4Version), location: "rootA"),
        ])

        let data = workspace.loadGraphData(root: root, diagnostics: diagnostics)

        // Sanity.
        XCTAssertFalse(diagnostics.hasErrors)
        XCTAssertEqual(data.graph.rootPackages, [])
        XCTAssertEqual(data.graph.packages.map{$0.name}.sorted(), ["A", "B"])

        // Check package association.
        XCTAssertEqual(data.dependencyMap[data.graph.lookup("A")]?.name, "A")
        XCTAssertEqual(data.dependencyMap[data.graph.lookup("B")]?.name, "B")

        let currentDeps = workspace.managedDependencies.values.map{$0.name}
        // Check delegates.
        XCTAssertEqual(delegate.managedDependenciesData[0].map{$0.name}, currentDeps)

        // Load graph data again.
        do {
            let data = workspace.loadGraphData(root: root, diagnostics: diagnostics)
            // Check package association.
            XCTAssertEqual(data.dependencyMap[data.graph.lookup("A")]?.name, "A")
            XCTAssertEqual(data.dependencyMap[data.graph.lookup("B")]?.name, "B")
        }

        XCTAssertEqual(delegate.managedDependenciesData[1].map{$0.name}, currentDeps)
        XCTAssertEqual(delegate.managedDependenciesData.count, 2)
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testBranchAndRevision", testBranchAndRevision),
        ("testEditDependency", testEditDependency),
        ("testEditDependencyOnNewBranch", testEditDependencyOnNewBranch),
        ("testEditAndPinning", testEditAndPinning),
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
        ("testTOTPackageEdit", testTOTPackageEdit),
        ("testLoadingRootManifests", testLoadingRootManifests),
        ("testPackageGraphWithGraphRootDependencies", testPackageGraphWithGraphRootDependencies),
        ("testPackageGraphOnlyRootDependency", testPackageGraphOnlyRootDependency),
        ("testDeletedCheckoutDirectory", testDeletedCheckoutDirectory),
        ("testGraphData", testGraphData),
        ("testSymlinkedDependency", testSymlinkedDependency),
    ]
}

extension PackageGraph {
    /// Finds the package matching the given name.
    func lookup(_ name: String) -> PackageModel.ResolvedPackage {
        return packages.first{ $0.name == name }!
    }
}
