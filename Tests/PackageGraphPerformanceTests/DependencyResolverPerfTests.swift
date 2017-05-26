/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph
import PackageLoading
import SourceControl

import struct Utility.Version

import TestSupport

private let v1: Version = "1.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")

class DependencyResolverPerfTests: XCTestCasePerf {

    func testTrivalResolution_X1000() {
        let N = 1000
        // Try resolving a trivial graph:
        //        ↗ C
        // A -> B
        //        ↘ D
        let provider = MockPackagesProvider(containers: [
            MockPackageContainer(name: "A", dependenciesByVersion: [
                v1: [(container: "B", versionRequirement: v1Range)]]),
            MockPackageContainer(name: "B", dependenciesByVersion: [
                v1: [
                    (container: "C", versionRequirement: v1Range),
                    (container: "D", versionRequirement: v1Range),
                ]
            ]),
            MockPackageContainer(name: "C", dependenciesByVersion: [
                v1: []]),
            MockPackageContainer(name: "D", dependenciesByVersion: [
                v1: []])
        ])
        let resolver = MockDependencyResolver(provider, MockResolverDelegate())
        measure {
            for _ in 0..<N {
                let result = try! resolver.resolveToVersion(constraints: [MockPackageConstraint(container: "A", versionRequirement: v1Range)])
                XCTAssertEqual(result, ["A": v1, "B": v1, "C": v1, "D": v1])
            }
        }
    }

    func testPrefilterPerf() {
        mktmpdir { path in
            var fs = localFileSystem
            let dep = path.appending(components: "dep")

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

            let depGit = GitRepository(path: dep)
            try depGit.create()

            // Create v1 tag.
            try depGit.stageEverything()
            try depGit.commit()
            try depGit.tag(name: "1.0.2")

            // Create v2 tags.
            let v2Versions = (0...5).map({ "2.0.\($0)" })
            for version in v2Versions {
                try depGit.stageEverything()
                try? depGit.commit()
                try depGit.tag(name: version)
            }

            let repositoryManager = RepositoryManager(
                path: path.appending(component: "repositories"),
                provider: GitRepositoryProvider(),
                delegate: GitRepositoryResolutionHelper.DummyRepositoryManagerDelegate()
            )

            let containerProvider = RepositoryPackageContainerProvider(
                repositoryManager: repositoryManager, manifestLoader: ManifestLoader(resources: Resources.default))

            let resolver = DependencyResolver(containerProvider, GitRepositoryResolutionHelper.DummyResolverDelegate())
            let constraints = RepositoryPackageConstraint(container: RepositorySpecifier(url: dep.asString), versionRequirement: .range("1.0.0"..<"2.0.0"))
            let result = try! resolver.resolve(constraints: [constraints])
            XCTAssert(result.count == 1)

            measure {
                for _ in 0..<2 {
                    let result = try! resolver.resolve(constraints: [constraints])
                    XCTAssert(result.count == 1)
                }
            }
        }
    }

    func testResolutionWith100Depth1Breadth() {
        let N = 1
        let depth = 100
        let breadth = 1

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith100Depth2Breadth() {
        let N = 1
        let depth = 100
        let breadth = 2

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith1Depth100Breadth() {
        let N = 1
        let depth = 1
        let breadth = 100

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith10Depth20Breadth() {
        let N = 1
        let depth = 10
        let breadth = 20

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWithGitRepositories() {
        mktmpdir { path in
            let testHelper = try GitRepositoryResolutionHelper(path)
            measure {
                let result = testHelper.resolve()
                XCTAssertEqual(result.count, 5)
            }
        }
    }

    func testResolutionWithGitRepositoriesAndPrefetching() {
        mktmpdir { path in
            let testHelper = try GitRepositoryResolutionHelper(path)
            measure {
                let result = testHelper.resolve(prefetchingEnabled: true)
                XCTAssertEqual(result.count, 5)
            }
        }
    }
}

class DependencyResolverRealWorldPerfTests: XCTestCasePerf {

    func testKitura_X100() throws {
        try runPackageTest(name: "kitura.json", N: 100)
    }

    func testZewoHTTPServer_X100() throws {
        try runPackageTest(name: "ZewoHTTPServer.json", N: 100)
    }

    func testPerfectHTTPServer_X100() throws {
        try runPackageTest(name: "PerfectHTTPServer.json", N: 100)
    }

    func testSourceKitten_X1000() throws {
        try runPackageTest(name: "SourceKitten.json", N: 1000)
    }
    
    func runPackageTest(name: String, N: Int = 1) throws {
        let graph = try mockGraph(for: name)
        let provider = MockPackagesProvider(containers: graph.containers)
        
        measure {
            for _ in 0 ..< N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolveToVersion(constraints: graph.constraints)
                graph.checkResult(result)
            }
        }
    }

    func mockGraph(for name: String) throws -> MockGraph {
        let input = AbsolutePath(#file).parentDirectory.appending(component: "Inputs").appending(component: name)
        let jsonString = try localFileSystem.readFileContents(input)
        let json = try JSON(bytes: jsonString)
        return MockGraph(json)
    }
}

/// Create dummpy graph with depth X breadth nodes.
///
/// This method creates a graph with `depth` number of main nodes. Each main node is dependent on the next main node and
/// `breadth` number of child nodes. This is how a graph looks like:
///     +---+    +---+    +---+    +---+
///     |   +--->+   +--->+   +--->+   |  Depth = 4
///     +-+-+    +-+-+    +-+-+    +-+-+
///       |        |        |        |
///       v        v        v        v
///     +-+-+    +-+-+    +-+-+    +-+-+
///     |   |    |   |    |   |    |   |
///     +-+-+    +-+-+    +-+-+    +-+-+
///       |        |        |        |
///       v        v        v        v
///     +-+-+    +-+-+    +-+-+    +-+-+
///     |   |    |   |    |   |    |   |
///     +---+    +---+    +---+    +---+
///
///                 Breadth = 3
///
/// - Parameters:
///   - depth: The number of main nodes.
///   - breadth: The number of child nodes dependent on each main node.
/// - Returns: A tuple with root constaint and the containers.
func createDummyGraph(depth: Int, breadth: Int) -> (rootConstraint: MockPackageConstraint, containers: [MockPackageContainer]) {
    precondition(breadth >= 1, "Minimum breadth should be 1")
    // Create an array to hold all the containers.
    var containers = [MockPackageContainer]()
    // Create main nodes.
    for depthLevel in 0..<depth {
        // Create dependencies for for this node.
        let dependencies = (0 ..< (breadth-1)).map { breadthLevel -> (container: String, versionRequirement: VersionSetSpecifier) in
            let name = "\(depthLevel)-\(breadthLevel)"
            // Append the container for this node.
            containers += [MockPackageContainer(name: name, dependenciesByVersion: [v1: []])]
            return (name, v1Range)
        }
        // Compute the next node, we're going to add it to dependency of this node.
        let nextNode: [(container: String, versionRequirement: VersionSetSpecifier)]
        nextNode = (depthLevel != depth - 1) ? [(String(depthLevel + 1), v1Range)] : []
        // Create container for this node.
        containers += [MockPackageContainer(name: String(depthLevel), dependenciesByVersion: [v1: dependencies + nextNode])]
    }
    // Return the root constaint and containers.
    return (MockPackageConstraint(container: "0", versionRequirement: v1Range), containers)
}

/// Helper class to run performance test of dependency resolution using git repositories.
struct GitRepositoryResolutionHelper {
    let manifestGraph: MockManifestGraph
    let path: AbsolutePath

    init(_ path: AbsolutePath) throws {
        self.path = path
        manifestGraph = try MockManifestGraph(at: path,
            rootDeps: [
                MockDependency("A", version: v1),
                MockDependency("B", version: v1),
                MockDependency("C", version: v1),
                MockDependency("D", version: v1),
            ],
            packages: [
                MockPackage("A", version: v1, dependencies: [
                    MockDependency("AA", version: v1)
                ]),
                MockPackage("AA", version: v1),
                MockPackage("B", version: v1),
                MockPackage("C", version: v1),
                MockPackage("D", version: v1),
            ]
        )
    }

    var constraints: [RepositoryPackageConstraint] { 
        return manifestGraph.rootManifest.package.dependencyConstraints()
    }

    func resolve(prefetchingEnabled: Bool = false) -> [(container: RepositorySpecifier, binding: BoundVersion)] {
        let repositoriesPath = path.appending(component: "repositories")
        _ = try? systemQuietly(["rm", "-r", repositoriesPath.asString])
        let repositoryManager = RepositoryManager(path: repositoriesPath, provider: GitRepositoryProvider(), delegate: DummyRepositoryManagerDelegate())
        let containerProvider = RepositoryPackageContainerProvider(repositoryManager: repositoryManager, manifestLoader: manifestGraph.manifestLoader)
        let resolver = DependencyResolver(containerProvider, DummyResolverDelegate(), isPrefetchingEnabled: prefetchingEnabled)
        let result = try! resolver.resolve(constraints: constraints)
        return result
    }

    class DummyResolverDelegate: DependencyResolverDelegate {
        typealias Identifier = RepositoryPackageContainer.Identifier
    }

    class DummyRepositoryManagerDelegate: RepositoryManagerDelegate {
        func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle) {
        }

        func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, error: Swift.Error?) {
        }
    }
}
