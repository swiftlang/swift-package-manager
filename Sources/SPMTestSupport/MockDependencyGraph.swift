/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import PackageLoading
import PackageModel
import PackageGraph
import SourceControl
import TSCUtility

/// Represents a mock package.
public struct MockPackage {
    /// The name of the package.
    public let name: String

    /// The current available version of the package.
    public let version: TSCUtility.Version?

    /// The dependencies of the package.
    public let dependencies: [MockDependency]

    public init(_ name: String, version: TSCUtility.Version?, dependencies: [MockDependency] = []) {
        self.name = name
        self.version = version
        self.dependencies = dependencies
    }
}

/// Represents a mock package dependency.
public struct MockDependency {
    /// The name of the dependency.
    public let name: String

    /// The allowed version range of this dependency.
    public let version: Range<TSCUtility.Version>

    public init(_ name: String, version: Range<TSCUtility.Version>) {
        self.name = name
        self.version = version
    }

    public init(_ name: String, version: TSCUtility.Version) {
        self.name = name
        self.version = version..<Version(version.major, version.minor, version.patch + 1)
    }
}

/// A mock manifest graph creator. It takes in a path where it creates empty repositories for mock packages.
/// For each mock package, it creates a manifest and maps it to the url and that version in mock manifest loader.
/// It provides basic functionality of getting the repo paths and manifests which can be later modified in tests.
public struct MockManifestGraph {
    /// The map of repositories created by this class where the key is name of the package.
    public let repos: [String: RepositorySpecifier]

    /// The generated mock manifest loader.
    public let manifestLoader: MockManifestLoader

    /// The generated root manifest.
    public let rootManifest: Manifest

    /// The map of external manifests created.
    public let manifests: [MockManifestLoader.Key: Manifest]

    /// Present if file system used is in inmemory.
    public let repoProvider: InMemoryGitRepositoryProvider?

    /// Convinience accessor for repository specifiers.
    public func repo(_ package: String) -> RepositorySpecifier {
        return repos[package]!
    }

    /// Convinience accessor for external manifests.
    public func manifest(_ package: String, version: TSCUtility.Version) -> Manifest {
        return manifests[MockManifestLoader.Key(url: repo(package).url, version: version)]!
    }

    /// Create instance with mocking on in memory file system.
    public init(
        at path: AbsolutePath,
        rootDeps: [MockDependency],
        packages: [MockPackage],
        fs: InMemoryFileSystem
        ) throws {
        try self.init(at: path, rootDeps: rootDeps, packages: packages, inMemory: (fs, InMemoryGitRepositoryProvider()))
    }

    public init(
        at path: AbsolutePath,
        rootDeps: [MockDependency],
        packages: [MockPackage],
        inMemory: (fs: InMemoryFileSystem, provider: InMemoryGitRepositoryProvider)? = nil
        ) throws {
        repoProvider = inMemory?.provider
        // Create the test repositories, we don't need them to have actual
        // contents (the manifests are mocked).
        let repos = Dictionary(uniqueKeysWithValues: try packages.map({ package -> (String, RepositorySpecifier) in
            let repoPath = path.appending(component: package.name)
            let tag = package.version?.description ?? "initial"
            let specifier = RepositorySpecifier(url: repoPath.pathString)

            // If this is in memory mocked graph.
            if let inMemory = inMemory {
                if !inMemory.fs.exists(repoPath) {
                    let repo = InMemoryGitRepository(path: repoPath, fs: inMemory.fs)
                    try repo.createDirectory(repoPath, recursive: true)
                    let filePath = repoPath.appending(component: "source.swift")
                    try repo.writeFileContents(filePath, bytes: "foo")
                    repo.commit()
                    try repo.tag(name: tag)
                    inMemory.provider.add(specifier: specifier, repository: repo)
                }
            } else {
                // Don't recreate repo if it is already there.
                if !localFileSystem.exists(repoPath) {
                    try makeDirectories(repoPath)
                    initGitRepo(repoPath, tag: package.version?.description ?? "initial")
                }
            }
            return (package.name, specifier)
        }))

        let src = path.appending(component: "Sources")
        if let fs = inMemory?.fs {
            try fs.createDirectory(src, recursive: true)
            try fs.writeFileContents(src.appending(component: "foo.swift"), bytes: "")
        } else {
            // Make a sources folder for our root package.
            try makeDirectories(src)
            try systemQuietly(["touch", src.appending(component: "foo.swift").pathString])
        }

        // Create the root manifest.
        rootManifest = Manifest(
            name: "Root",
            platforms: [],
            path: path.appending(component: Manifest.filename),
            url: path.pathString,
            version: nil,
            toolsVersion: .v4,
            packageKind: .root,
            dependencies: MockManifestGraph.createDependencies(repos: repos, dependencies: rootDeps)
        )

        // Create the manifests from mock packages.
        var manifests = Dictionary(uniqueKeysWithValues: packages.map({ package -> (MockManifestLoader.Key, Manifest) in
            let url = repos[package.name]!.url
            let manifest = Manifest(
                name: package.name,
                platforms: [],
                path: AbsolutePath(url).appending(component: Manifest.filename),
                url: url,
                version: package.version,
                toolsVersion: .v4,
                packageKind: .remote,
                dependencies: MockManifestGraph.createDependencies(repos: repos, dependencies: package.dependencies)
            )
            return (MockManifestLoader.Key(url: url, version: package.version), manifest)
        }))
        // Add the root manifest.
        manifests[MockManifestLoader.Key(url: path.pathString, version: nil)] = rootManifest

        manifestLoader = MockManifestLoader(manifests: manifests)
        self.manifests = manifests
        self.repos = repos
    }

    /// Maps MockDependencies into PackageDescription's Dependency array.
    private static func createDependencies(
        repos: [String: RepositorySpecifier],
        dependencies: [MockDependency]
    ) -> [PackageDependencyDescription] {
        return dependencies.map({ dependency in
            return PackageDependencyDescription(
                name: dependency.name,
                url: repos[dependency.name]?.url ?? "//\(dependency.name)",
                requirement: .range(dependency.version.lowerBound ..< dependency.version.upperBound))
        })
    }
}
