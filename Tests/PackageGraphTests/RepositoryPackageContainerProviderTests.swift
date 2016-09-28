/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageDescription
import PackageLoading
import PackageModel
import PackageGraph
import SourceControl

import TestSupport

private class MockRepository: Repository {
    /// The fake URL of the repository.
    let url: String
    
    /// The known repository versions, as a map of tags to manifests.
    let versions: [Version: Manifest]
    
    init(url: String, versions: [Version: Manifest]) {
        self.url = url
        self.versions = versions
    }

    var specifier: RepositorySpecifier {
        return RepositorySpecifier(url: url)
    }

    var tags: [String] {
        return versions.keys.map{ String(describing: $0) }
    }

    func resolveRevision(tag: String) throws -> Revision {
        assert(versions.index(forKey: Version(tag)!) != nil)
        return Revision(identifier: tag)
    }

    func fetch() throws {
        fatalError("Unexpected API call")
    }

    func exists(revision: Revision) -> Bool {
        fatalError("Unexpected API call")
    }

    func remove() throws {
        fatalError("Unexpected API call")
    }

    func openFileView(revision: Revision) throws -> FileSystem {
        assert(versions.index(forKey: Version(revision.identifier)!) != nil)
        // This isn't actually used, see `MockManifestLoader`.
        return InMemoryFileSystem()
    }
}

private class MockRepositories: RepositoryProvider {
    /// The known repositories, as a map of URL to repository.
    let repositories: [String: MockRepository]

    /// A mock manifest loader for all repositories.
    let manifestLoader: MockManifestLoader

    init(repositories repositoryList: [MockRepository]) {
        var allManifests: [MockManifestLoader.Key: Manifest] = [:]
        var repositories: [String: MockRepository] = [:]
        for repository in repositoryList {
            assert(repositories.index(forKey: repository.url) == nil)
            repositories[repository.url] = repository
            for (version, manifest) in repository.versions {
                allManifests[MockManifestLoader.Key(url: repository.url, version: version)] = manifest
            }
        }

        self.repositories = repositories
        self.manifestLoader = MockManifestLoader(manifests: allManifests)
    }

    func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // No-op.
        assert(repositories.index(forKey: repository.url) != nil)
    }
    
    func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository {
        return repositories[repository.url]!
    }

    func cloneCheckout(repository: RepositorySpecifier, at sourcePath: AbsolutePath, to destinationPath: AbsolutePath, editable: Bool) throws {
        fatalError("unexpected API call")
    }

    func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        fatalError("unexpected API call")
    }
}

private class MockResolverDelegate: DependencyResolverDelegate, RepositoryManagerDelegate {
    typealias Identifier = RepositoryPackageContainer.Identifier

    var addedContainers: [Identifier] = []
    var fetched = [RepositorySpecifier]()

    func added(container identifier: Identifier) {
        addedContainers.append(identifier)
    }

    func fetching(handle: RepositoryManager.RepositoryHandle, to path: AbsolutePath) {
        fetched += [handle.repository]
    }
}

private struct MockDependencyResolver {
    let tmpDir: TemporaryDirectory
    let repositories: MockRepositories
    let delegate: MockResolverDelegate
    private let resolver: DependencyResolver<RepositoryPackageContainerProvider, MockResolverDelegate>

    init(repositories: MockRepository...) {
        self.tmpDir = try! TemporaryDirectory()
        self.repositories = MockRepositories(repositories: repositories)
        self.delegate = MockResolverDelegate()
        let repositoryManager = RepositoryManager(path: self.tmpDir.path, provider: self.repositories, delegate: self.delegate)
        let provider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager, manifestLoader: self.repositories.manifestLoader)
        self.resolver = DependencyResolver(provider, delegate)
    }

    func resolve(constraints: [RepositoryPackageConstraint]) throws -> [(container: RepositorySpecifier, version: Version)] {
        return try resolver.resolve(constraints: constraints)
    }
}

// Some handy versions & ranges.
//
// The convention is that the name matches how specific the version is, so "v1"
// means "any 1.?.?", and "v1_1" means "any 1.1.?".

private let v1: Version = "1.0.0"
private let v2: Version = "2.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")

class RepositoryPackageContainerProviderTests: XCTestCase {
    func testBasics() {
        mktmpdir{ path in
            let repoA = MockRepository(
                url: "A",
                versions: [
                    v1: Manifest(
                        path: AbsolutePath("/Package.swift"),
                        url: "A",
                        package: PackageDescription.Package(
                            name: "Foo",
                            dependencies: [
                                .Package(url: "B", majorVersion: 2)
                            ]
                        ),
                        products: [],
                        version: v1
                    )
                ])
            let repoB = MockRepository(
                url: "B",
                versions: [
                    v2: Manifest(
                        path: AbsolutePath("/Package.swift"),
                        url: "B",
                        package: PackageDescription.Package(
                            name: "Bar"),
                        products: [],
                        version: v2
                    )
                ])
            let resolver = MockDependencyResolver(repositories: repoA, repoB)

            let constraints = [
                RepositoryPackageConstraint(
                    container: repoA.specifier,
                    versionRequirement: v1Range)
            ]
            let result = try resolver.resolve(constraints: constraints)
            XCTAssertEqual(result, [
                    repoA.specifier: v1,
                    repoB.specifier: v2,
                ])
            XCTAssertEqual(resolver.delegate.addedContainers, [repoA.specifier, repoB.specifier])
            XCTAssertEqual(resolver.delegate.fetched, [repoA.specifier, repoB.specifier])
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
