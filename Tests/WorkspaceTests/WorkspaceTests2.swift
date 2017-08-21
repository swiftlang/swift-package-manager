/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageLoading
import PackageDescription4
import PackageModel
import PackageGraph
import SourceControl
import Utility
@testable import Workspace

import TestSupport

final class WorkspaceTests2: XCTestCase {

    func testBasics() throws {

        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar"]),
                        TestTarget(name: "Bar", dependencies: ["Baz"]),
                        TestTarget(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(targets: "Bar", "Baz", "Foo")
                result.check(testModules: "BarTests")
                result.check(dependencies: "Bar", target: "Foo")
                result.check(dependencies: "Baz", target: "Bar")
                result.check(dependencies: "Bar", target: "BarTests")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

	func testMultipleRootPackages() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Baz", requirement: .exact("1.0.1")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.0.3", "1.0.5", "1.0.8"]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Bar", "Foo")
                result.check(packages: "Bar", "Baz", "Foo")
                result.check(dependencies: "Baz", target: "Foo")
                result.check(dependencies: "Baz", target: "Bar")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.1")))
        }
    }
}

// MARK:- Test Infrastructure

private class TestWorkspaceDelegate: WorkspaceDelegate {

    func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>) {
    }

    func repositoryWillUpdate(_ repository: String) {
    }

    func fetchingWillBegin(repository: String) {
    }

    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
    }

    func cloning(repository: String) {
    }

    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
    }

    func removing(repository: String) {
    }

    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
    }
}

private final class TestWorkspace {

    let sandbox: AbsolutePath
    var fs: FileSystem
    let roots: [TestPackage]
    let packages: [TestPackage]
    var manifestLoader: MockManifestLoader
    var repoProvider: InMemoryGitRepositoryProvider

    fileprivate init(
        sandbox: AbsolutePath,
        fs: FileSystem,
        roots: [TestPackage],
        packages: [TestPackage]
    ) throws {
        precondition(Set(roots.map({$0.name})).count == roots.count, "Root packages should be unique")
        self.sandbox = sandbox
        self.fs = fs
        self.roots = roots
        self.packages = packages

        self.manifestLoader = MockManifestLoader(manifests: [:])
        self.repoProvider = InMemoryGitRepositoryProvider()

        try create()
    }

    var rootsDir: AbsolutePath {
        return sandbox.appending(component: "roots")
    }

    var packagesDir: AbsolutePath {
        return sandbox.appending(component: "pkgs")
    }

    func create() throws {
        // Remove the sandbox if present.
        try fs.removeFileTree(sandbox)

        // Create directories.
        try fs.createDirectory(sandbox, recursive: true)
        try fs.createDirectory(rootsDir)
        try fs.createDirectory(packagesDir)

        var manifests: [MockManifestLoader.Key: Manifest] = [:]

        func create(package: TestPackage, basePath: AbsolutePath, isRoot: Bool) throws {
            let packagePath = basePath.appending(component: package.name)
            let sourcesDir = packagePath.appending(component: "Sources")

            // Create targets on disk.
            let repo = InMemoryGitRepository(path: packagePath, fs: fs as! InMemoryFileSystem)
            for target in package.targets {
                let targetDir = sourcesDir.appending(component: target.name)
                try repo.createDirectory(targetDir, recursive: true)
                try repo.writeFileContents(targetDir.appending(component: "file.swift"), bytes: "")
            }
            repo.commit()

            let url = (isRoot ? packagePath : packagesDir.appending(component: package.name)).asString
            let versions: [String?] = isRoot ? [nil] : package.versions

            for version in versions {
                let v = version.flatMap(Version.init(string:))
                manifests[.init(url: url, version: v)] = Manifest(
                    path: packagePath.appending(component: Manifest.filename),
                    url: url,
                    package: .v4(.init(
                        name: package.name,
                        products: package.products.map({ .library(name: $0.name, targets: $0.targets) }),
                        dependencies: package.dependencies.map({ $0.convert(baseURL: packagesDir) }),
                        targets: package.targets.map({ $0.convert() })
                    )),
                    version: v
                )
                if let version = version {
                    try repo.tag(name: version)
                }
            }

            repoProvider.add(specifier: RepositorySpecifier(url: url), repository: repo)
        }

        // Create root packages.
        for package in roots {
            try create(package: package, basePath: rootsDir, isRoot: true)
        }

        // Create dependency packages.
        for package in packages {
            try create(package: package, basePath: packagesDir, isRoot: false)
        }

        self.manifestLoader = MockManifestLoader(manifests: manifests)
    }

    func createWorkspace() -> Workspace {
        if let workspace = _workspace {
            return workspace
        }
        _workspace = Workspace(
            dataPath: sandbox.appending(component: ".build"),
            editablesPath: sandbox.appending(component: "edits"),
            pinsFile: sandbox.appending(component: "Package.resolved"),
            manifestLoader: manifestLoader,
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: TestWorkspaceDelegate(),
            fileSystem: fs,
            repositoryProvider: repoProvider
        )
        return _workspace!
    }
    var _workspace: Workspace? = nil

    func rootPaths(for packages: [String]) -> [AbsolutePath] {
        return packages.map({ rootsDir.appending(component: $0) })
    }

    func checkPackageGraph(roots: [String], _ result: (PackageGraph, DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(packages: rootPaths(for: roots))
        let graph = workspace.loadPackageGraph(root: rootInput, diagnostics: diagnostics)
        result(graph, diagnostics)
    }

    struct ManagedDependencyResult {

        let managedDependencies: ManagedDependencies

        init(_ managedDependencies: ManagedDependencies) {
            self.managedDependencies = managedDependencies
        }

        enum State {
            enum CheckoutState {
                case version(Utility.Version)
                case revision(String)
            }
            case checkout(CheckoutState)
            case edited
        }

        func check(dependency name: String, at state: State) {
            guard let dependency = managedDependencies[forIdentity: name] else {
                XCTFail("\(name) does not exists")
                return
            }
            switch state {
            case .checkout(let state):
                switch state {
                case .version(let version):
                    XCTAssertEqual(dependency.checkoutState?.version, version)
                case .revision:
                    XCTFail("Unimplemented")
                }
            case .edited:
                XCTFail("Unimplemented")
            }
        }
    }

    func checkManagedDependencies(_ result: (ManagedDependencyResult) throws -> ()) {
        do {
            let workspace = createWorkspace()
            try result(ManagedDependencyResult(workspace.managedDependencies))
        } catch {
            XCTFail("Failed with error \(error)")
        }
    }
}

private struct TestTarget {

    enum `Type` {
        case regular, test
    }

    let name: String
    let dependencies: [String]
    let type: Type

    fileprivate init(
        name: String,
        dependencies: [String] = [],
        type: Type = .regular
    ) {
        self.name = name
        self.dependencies = dependencies
        self.type = type
    }

    func convert() -> PackageDescription4.Target {
        switch type {
        case .regular:
            return .target(name: name, dependencies: dependencies.map({ .byName(name: $0) }))
        case .test:
            return .testTarget(name: name, dependencies: dependencies.map({ .byName(name: $0) }))
        }
    }
}

private struct TestProduct {

    let name: String
    let targets: [String]

    fileprivate init(name: String, targets: [String]) {
        self.name = name
        self.targets = targets
    }
}

private struct TestDependency {
    let name: String
    let requirement: Requirement
    typealias Requirement = PackageDescription4.Package.Dependency.Requirement

    fileprivate init(name: String, requirement: Requirement) {
        self.name = name
        self.requirement = requirement
    }

    func convert(baseURL: AbsolutePath) -> PackageDescription4.Package.Dependency {
        return .package(url: baseURL.appending(component: name).asString, requirement)
    }
}

private struct TestPackage {

    let name: String
    let targets: [TestTarget]
    let products: [TestProduct]
    let dependencies: [TestDependency]
    let versions: [String]

    fileprivate init(
        name: String,
        targets: [TestTarget],
        products: [TestProduct],
        dependencies: [TestDependency] = [],
        versions: [String] = []
    ) {
        self.name = name
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
    }
}
