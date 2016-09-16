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
    func fetchingMissingRepositories(_ urls: Set<String>) {
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

    func testDependencyManifestLoading() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        //   \ AA: checked out (@v1)
        // \ B: missing
        
        mktmpdir { path in
            // Create the test repositories, we don't need them to have actual
            // contents (the manifests are mocked).
            var repos: [String: RepositorySpecifier] = [:]
            for name in ["A", "AA"] {
                let repoPath = path.appending(component: name)
                try makeDirectories(repoPath)
                initGitRepo(repoPath, tag: "initial")
                repos[name] = RepositorySpecifier(url: repoPath.asString)
            }

            // Create the mock manifests.
            let rootManifest = Manifest(
                path: AbsolutePath("/UNUSED"),
                url: path.asString,
                package: PackageDescription.Package(
                    name: "Root",
                    dependencies: [
                        .Package(url: repos["A"]!.url, majorVersion: 1),
                        .Package(url: "//B", majorVersion: 1)
                    ]),
                products: [],
                version: nil
            )
            let aManifest = Manifest(
                path: AbsolutePath("/UNUSED"),
                url: repos["A"]!.url,
                package: PackageDescription.Package(
                    name: "A",
                    dependencies: [
                        .Package(url: repos["AA"]!.url, majorVersion: 1)
                    ]),
                products: [],
                version: v1
            )
            let aaManifest = Manifest(
                path: AbsolutePath("/UNUSED"),
                url: repos["AA"]!.url,
                package: PackageDescription.Package(
                    name: "AA"),
                products: [],
                version: v1
            )
            let mockManifestLoader = MockManifestLoader(manifests: [
                    MockManifestLoader.Key(url: path.asString, version: nil): rootManifest,
                    MockManifestLoader.Key(url: repos["A"]!.url, version: v1): aManifest,
                    MockManifestLoader.Key(url: repos["AA"]!.url, version: v1): aaManifest
                ])
                    
            // Create the workspace.
            let workspace = try Workspace(rootPackage: path, manifestLoader: mockManifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have checkouts for A & AA.
            for name in ["A", "AA"] {
                let revision = try GitRepository(path: AbsolutePath(repos[name]!.url)).getCurrentRevision()
                _ = try workspace.clone(repository: repos[name]!, at: revision, for: v1)
            }

            // Load the "current" manifests.
            let manifests = try workspace.loadDependencyManifests()
            XCTAssertEqual(manifests.root.package, rootManifest.package)
            var dependencyManifests: [String: Manifest] = [:]
            for manifest in manifests.dependencies {
                dependencyManifests[manifest.package.name] = manifest
            }
            XCTAssertEqual(dependencyManifests.keys.sorted(), ["A", "AA"])
            XCTAssertEqual(dependencyManifests["A"]?.package, aManifest.package)
            XCTAssertEqual(dependencyManifests["A"]?.version, aManifest.version)
            XCTAssertEqual(dependencyManifests["AA"]?.package, aaManifest.package)
            XCTAssertEqual(dependencyManifests["AA"]?.version, aaManifest.version)
        }
    }

    /// Check the basic ability to load a graph from the workspace.
    func testPackageGraphLoadingBasics() {
        // We mock up the following dep graph:
        //
        // Root
        // \ A: checked out (@v1)
        //
        // FIXME: We need better infrastructure for mocking up the things we
        // want to test here.
        
        mktmpdir { path in
            // Create the test repositories, we don't need them to have actual
            // contents (the manifests are mocked).
            var repos: [String: RepositorySpecifier] = [:]
            for name in ["A"] {
                let repoPath = path.appending(component: name)
                try makeDirectories(repoPath)
                initGitRepo(repoPath, tag: "initial")
                repos[name] = RepositorySpecifier(url: repoPath.asString)
            }

            // Create the mock manifests.
            let rootManifest = Manifest(
                path: path.appending(component: Manifest.filename),
                url: path.asString,
                package: PackageDescription.Package(
                    name: "Root",
                    dependencies: [
                        .Package(url: repos["A"]!.url, majorVersion: 1),
                    ]),
                products: [],
                version: nil
            )
            let aManifest = Manifest(
                path: AbsolutePath(repos["A"]!.url).appending(component: Manifest.filename),
                url: repos["A"]!.url,
                package: PackageDescription.Package(name: "A"),
                products: [],
                version: v1
            )
            let mockManifestLoader = MockManifestLoader(manifests: [
                    MockManifestLoader.Key(url: path.asString, version: nil): rootManifest,
                    MockManifestLoader.Key(url: repos["A"]!.url, version: v1): aManifest,
                ])
                    
            // Create the workspace.
            let workspace = try Workspace(rootPackage: path, manifestLoader: mockManifestLoader, delegate: TestWorkspaceDelegate())

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(repos[name]!.url)).getCurrentRevision()
                _ = try workspace.clone(repository: repos[name]!, at: revision, for: v1)
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
        //
        // FIXME: We need better infrastructure for mocking up the things we
        // want to test here.
        
        mktmpdir { path in
            // Create the test repositories, we don't need them to have actual
            // contents (the manifests are mocked).
            var repos: [String: RepositorySpecifier] = [:]
            for name in ["A", "AA", "B"] {
                let repoPath = path.appending(component: name)
                try makeDirectories(repoPath)
                initGitRepo(repoPath, tag: "initial")
                // FIXME: This sucks, the combination of mocking + real
                // repositories here is quite unfortunate. We should find a
                // better solution.
                try tagGitRepo(repoPath, tag: "v1.0.0")
                repos[name] = RepositorySpecifier(url: repoPath.asString)
            }

            // Create the mock manifests.
            let rootManifest = Manifest(
                path: path.appending(component: Manifest.filename),
                url: path.asString,
                package: PackageDescription.Package(
                    name: "Root",
                    dependencies: [
                        .Package(url: repos["A"]!.url, majorVersion: 1),
                        .Package(url: repos["B"]!.url, majorVersion: 1),
                    ]),
                products: [],
                version: nil
            )
            let aManifest = Manifest(
                path: AbsolutePath(repos["A"]!.url).appending(component: Manifest.filename),
                url: repos["A"]!.url,
                package: PackageDescription.Package(
                    name: "A",
                    dependencies: [
                        .Package(url: repos["AA"]!.url, majorVersion: 1)
                    ]),
                products: [],
                version: v1
            )
            let aaManifest = Manifest(
                path: AbsolutePath(repos["AA"]!.url).appending(component: Manifest.filename),
                url: repos["AA"]!.url,
                package: PackageDescription.Package(
                    name: "AA"),
                products: [],
                version: v1
            )
            let bManifest = Manifest(
                path: AbsolutePath(repos["B"]!.url).appending(component: Manifest.filename),
                url: repos["B"]!.url,
                package: PackageDescription.Package(name: "B"),
                products: [],
                version: v1
            )
            let mockManifestLoader = MockManifestLoader(manifests: [
                    MockManifestLoader.Key(url: path.asString, version: nil): rootManifest,
                    MockManifestLoader.Key(url: repos["A"]!.url, version: v1): aManifest,
                    MockManifestLoader.Key(url: repos["AA"]!.url, version: v1): aaManifest,
                    MockManifestLoader.Key(url: repos["B"]!.url, version: v1): bManifest,
                ])
                    
            // Create the workspace.
            let delegate = TestWorkspaceDelegate()
            let workspace = try Workspace(rootPackage: path, manifestLoader: mockManifestLoader, delegate: delegate)

            // Ensure we have a checkout for A.
            for name in ["A"] {
                let revision = try GitRepository(path: AbsolutePath(repos[name]!.url)).getCurrentRevision()
                _ = try workspace.clone(repository: repos[name]!, at: revision, for: v1)
            }

            // Load the package graph.
            let graph = try workspace.loadPackageGraph()

            // Validate the graph has the correct basic structure.
            XCTAssertEqual(graph.packages.count, 4)
            XCTAssertEqual(graph.packages.map{ $0.name }.sorted(), [
                    "A", "AA", "B", "Root"])
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testDependencyManifestLoading", testDependencyManifestLoading),
        ("testPackageGraphLoadingBasics", testPackageGraphLoadingBasics),
        ("testPackageGraphLoadingWithCloning", testPackageGraphLoadingWithCloning),
    ]
}
