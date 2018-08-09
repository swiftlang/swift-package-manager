/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
import PackageLoading
@testable import Workspace
import PackageGraph
import SourceControl

public final class TestWorkspace {

    let sandbox: AbsolutePath
    let fs: FileSystem
    let roots: [TestPackage]
    let packages: [TestPackage]
    public var manifestLoader: MockManifestLoader
    public var repoProvider: InMemoryGitRepositoryProvider
    public let delegate = TestWorkspaceDelegate()
    let toolsVersion: ToolsVersion
    let skipUpdate: Bool

    public init(
        sandbox: AbsolutePath,
        fs: FileSystem,
        roots: [TestPackage],
        packages: [TestPackage],
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        skipUpdate: Bool = false
    ) throws {
        precondition(Set(roots.map({$0.name})).count == roots.count, "Root packages should be unique")
        self.sandbox = sandbox
        self.fs = fs
        self.roots = roots
        self.packages = packages

        self.manifestLoader = MockManifestLoader(manifests: [:])
        self.repoProvider = InMemoryGitRepositoryProvider()
        self.toolsVersion = toolsVersion
        self.skipUpdate = skipUpdate

        try create()
    }

    private var rootsDir: AbsolutePath {
        return sandbox.appending(component: "roots")
    }

    public var packagesDir: AbsolutePath {
        return sandbox.appending(component: "pkgs")
    }

    private func create() throws {
        // Remove the sandbox if present.
        try fs.removeFileTree(sandbox)

        // Create directories.
        try fs.createDirectory(sandbox, recursive: true)
        try fs.createDirectory(rootsDir)
        try fs.createDirectory(packagesDir)

        var manifests: [MockManifestLoader.Key: Manifest] = [:]

        func create(package: TestPackage, basePath: AbsolutePath, isRoot: Bool) throws {
            let packagePath = basePath.appending(RelativePath(package.path ?? package.name))

            let sourcesDir = packagePath.appending(component: "Sources")
            let url = (isRoot ? packagePath : packagesDir.appending(RelativePath(package.path ?? package.name))).asString
            let specifier = RepositorySpecifier(url: url)
            
            // Create targets on disk.
            let repo = repoProvider.specifierMap[specifier] ?? InMemoryGitRepository(path: packagePath, fs: fs as! InMemoryFileSystem)
            for target in package.targets {
                let targetDir = sourcesDir.appending(component: target.name)
                try repo.createDirectory(targetDir, recursive: true)
                try repo.writeFileContents(targetDir.appending(component: "file.swift"), bytes: "")
            }
            repo.commit()

            let versions: [String?] = isRoot ? [nil] : package.versions
            for version in versions {
                let v = version.flatMap(Version.init(string:))
                manifests[.init(url: url, version: v)] = Manifest(
                    name: package.name,
                    path: packagePath.appending(component: Manifest.filename),
                    url: url,
                    version: v,
                    manifestVersion: .v4,
                    dependencies: package.dependencies.map({ $0.convert(baseURL: packagesDir) }),
                    products: package.products.map({ ProductDescription(name: $0.name, type: .library(.automatic), targets: $0.targets) }),
                    targets: package.targets.map({ $0.convert() })
                )
                if let version = version {
                    try repo.tag(name: version)
                }
            }

            repoProvider.add(specifier: specifier, repository: repo)
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

    public func createWorkspace() -> Workspace {
        if let workspace = _workspace {
            return workspace
        }

        _workspace = Workspace(
            dataPath: sandbox.appending(component: ".build"),
            editablesPath: sandbox.appending(component: "edits"),
            pinsFile: sandbox.appending(component: "Package.resolved"),
            manifestLoader: manifestLoader,
            currentToolsVersion: toolsVersion,
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            fileSystem: fs,
            repositoryProvider: repoProvider,
            skipUpdate: skipUpdate
        )
        return _workspace!
    }
    private var _workspace: Workspace? = nil

    public func closeWorkspace() {
        _workspace = nil
    }

    public func rootPaths(for packages: [String]) -> [AbsolutePath] {
        return packages.map({ rootsDir.appending(component: $0) })
    }

    public struct PackageDependency {
        public typealias Requirement = PackageGraphRoot.PackageDependency.Requirement

        public let name: String
        public let requirement: Requirement

        public init(name: String, requirement: Requirement) {
            self.name = name
            self.requirement = requirement
        }

        fileprivate func convert(_ packagesDir: AbsolutePath) -> PackageGraphRootInput.PackageDependency {
            return PackageGraphRootInput.PackageDependency(
                url: packagesDir.appending(RelativePath(name)).asString,
                requirement: requirement,
                location: name
            )
        }
    }

    public func checkEdit(
        packageName: String,
        path: AbsolutePath? = nil,
        revision: Revision? = nil,
        checkoutBranch: String? = nil,
        _ result: (DiagnosticsEngine) -> ()
    ) {
        let ws = createWorkspace()
        let diagnostics = DiagnosticsEngine()
        ws.edit(
            packageName: packageName,
            path: path,
            revision: revision,
            checkoutBranch: checkoutBranch,
            diagnostics: diagnostics
        )
        result(diagnostics)
    }

    public func checkUnedit(
        packageName: String,
        roots: [String],
        forceRemove: Bool = false,
        _ result: (DiagnosticsEngine) -> ()
    ) {
        let ws = createWorkspace()
        let diagnostics = DiagnosticsEngine()
        let rootInput = PackageGraphRootInput(packages: rootPaths(for: roots))
        diagnostics.wrap {
            try ws.unedit(packageName: packageName, forceRemove: forceRemove, root: rootInput, diagnostics: diagnostics)
        }
        result(diagnostics)
    }

    public func checkResolve(pkg: String, roots: [String], version: Utility.Version, _ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(packages: rootPaths(for: roots))
        workspace.resolve(packageName: pkg, root: rootInput, version: version, branch: nil, revision: nil, diagnostics: diagnostics)
        result(diagnostics)
    }

    public func checkClean(_ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        workspace.clean(with: diagnostics)
        result(diagnostics)
    }

    public func checkReset(_ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        workspace.reset(with: diagnostics)
        result(diagnostics)
    }

    public func checkUpdate(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency] = [],
        _ result: (DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir) })
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        workspace.updateDependencies(root: rootInput, diagnostics: diagnostics)
        result(diagnostics)
    }

    public func checkPackageGraph(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency],
        _ result: (PackageGraph, DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir) })
        checkPackageGraph(roots: roots, dependencies: dependencies, result)
    }

    public func checkPackageGraph(
        roots: [String] = [],
        dependencies: [PackageGraphRootInput.PackageDependency] = [],
        _ result: (PackageGraph, DiagnosticsEngine) -> ()
    ) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        let graph = workspace.loadPackageGraph(root: rootInput, diagnostics: diagnostics)
        result(graph, diagnostics)
    }

    public func checkGraphData(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency],
        _ result: (PackageGraph, [ResolvedPackage: ManagedDependency], DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir) })
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        let graphData = workspace.loadGraphData(root: rootInput, diagnostics: diagnostics)
        result(graphData.graph, graphData.dependencyMap, diagnostics)
    }

    public enum State {
        public enum CheckoutState {
            case version(Utility.Version)
            case revision(String)
            case branch(String)
        }
        case checkout(CheckoutState)
        case edited(AbsolutePath?)
        case local
    }

    public struct ManagedDependencyResult {

        public let managedDependencies: ManagedDependencies

        public init(_ managedDependencies: ManagedDependencies) {
            self.managedDependencies = managedDependencies
        }

        public func check(notPresent name: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssert(managedDependencies[forIdentity: name] == nil, "Unexpectedly found \(name) in managed dependencies", file: file, line: line)
        }

        public func checkEmpty(file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(managedDependencies.values.map{$0}.count, 0, file: file, line: line)
        }

        public func check(dependency name: String, at state: State, file: StaticString = #file, line: UInt = #line) {
            guard let dependency = managedDependencies[forIdentity: name] else {
                XCTFail("\(name) does not exists", file: file, line: line)
                return
            }
            switch state {
            case .checkout(let checkoutState):
                switch checkoutState {
                case .version(let version):
                    XCTAssertEqual(dependency.checkoutState?.version, version, file: file, line: line)
                case .revision(let revision):
                    XCTAssertEqual(dependency.checkoutState?.revision.identifier, revision, file: file, line: line)
                case .branch(let branch):
                    XCTAssertEqual(dependency.checkoutState?.branch, branch, file: file, line: line)
                }
            case .edited(let path):
                if dependency.state != .edited(path) {
                    XCTFail("Expected edited dependency", file: file, line: line)
                }
            case .local:
                if dependency.state != .local {
                    XCTFail("Expected local dependency", file: file, line: line)
                }
            }
        }
    }

    public func loadDependencyManifests(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency] = [],
        _ result: (Workspace.DependencyManifests, DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir) })
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        let rootManifests = workspace.loadRootManifests(packages: rootInput.packages, diagnostics: diagnostics)
        let graphRoot = PackageGraphRoot(input: rootInput, manifests: rootManifests)
        let manifests = workspace.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)
        result(manifests, diagnostics)
    }

    public func checkManagedDependencies(file: StaticString = #file, line: UInt = #line, _ result: (ManagedDependencyResult) throws -> ()) {
        do {
            let workspace = createWorkspace()
            try result(ManagedDependencyResult(workspace.managedDependencies))
        } catch {
            XCTFail("Failed with error \(error)", file: file, line: line)
        }
    }

    public struct ResolvedResult {
        public let store: PinsStore

        public init(_ store: PinsStore) {
            self.store = store
        }

        public func check(notPresent name: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssert(store.pinsMap[name] == nil, "Unexpectedly found \(name) in Package.resolved", file: file, line: line)
        }

        public func check(dependency package: String, at state: State, file: StaticString = #file, line: UInt = #line) {
            guard let pin = store.pinsMap[package] else {
                XCTFail("Pin for \(package) not found", file: file, line: line)
                return
            }
            switch state {
            case .checkout(let state):
                switch state {
                case .version(let version):
                    XCTAssertEqual(pin.state.version, version, file: file, line: line)
                case .revision, .branch:
                    XCTFail("Unimplemented", file: file, line: line)
                }
            case .edited, .local:
                XCTFail("Unimplemented", file: file, line: line)
            }
        }
    }

    public func checkResolved(file: StaticString = #file, line: UInt = #line, _ result: (ResolvedResult) throws -> ()) {
        do {
            let workspace = createWorkspace()
            try result(ResolvedResult(workspace.pinsStore.load()))
        } catch {
            XCTFail("Failed with error \(error)", file: file, line: line)
        }
    }
}

public struct TestTarget {

    public enum `Type` {
        case regular, test
    }

    public let name: String
    public let dependencies: [String]
    public let type: Type

    public init(
        name: String,
        dependencies: [String] = [],
        type: Type = .regular
    ) {
        self.name = name
        self.dependencies = dependencies
        self.type = type
    }

    fileprivate func convert() -> TargetDescription {
        switch type {
        case .regular:
            return TargetDescription(name: name, dependencies: dependencies.map({ .byName(name: $0) }), path: nil, exclude: [], sources: nil, publicHeadersPath: nil, type: .regular)
        case .test:
            return TargetDescription(name: name, dependencies: dependencies.map({ .byName(name: $0) }), path: nil, exclude: [], sources: nil, publicHeadersPath: nil, type: .test)
        }
    }
}

public struct TestProduct {

    public let name: String
    public let targets: [String]

    public init(name: String, targets: [String]) {
        self.name = name
        self.targets = targets
    }
}

public struct TestDependency {
    public let name: String
    public let requirement: Requirement
    public typealias Requirement = PackageDependencyDescription.Requirement

    public init(name: String, requirement: Requirement) {
        self.name = name
        self.requirement = requirement
    }

    public func convert(baseURL: AbsolutePath) -> PackageDependencyDescription {
        return PackageDependencyDescription(url: baseURL.appending(RelativePath(name)).asString, requirement: requirement)
    }
}

public struct TestPackage {

    public let name: String
    public let path: String?
    public let targets: [TestTarget]
    public let products: [TestProduct]
    public let dependencies: [TestDependency]
    public let versions: [String?]

    public init(
        name: String,
        path: String? = nil,
        targets: [TestTarget],
        products: [TestProduct],
        dependencies: [TestDependency] = [],
        versions: [String?] = []
    ) {
        self.name = name
        self.path = path
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
    }

    public static func genericPackage1(named name: String) -> TestPackage {
        return TestPackage(
            name: name,
            targets: [
                TestTarget(name: name),
            ],
            products: [
                TestProduct(name: name, targets: [name]),
            ],
            versions: ["1.0.0"]
        )
    }
}

public final class TestWorkspaceDelegate: WorkspaceDelegate {

    public var events = [String]()
    public var managedDependenciesData = [AnySequence<ManagedDependency>]()

    public init() {}

    public func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>) {
    }

    public func repositoryWillUpdate(_ repository: String) {
        events.append("updating repo: \(repository)")
    }

    public func dependenciesUpToDate() {
        events.append("Everything is already up-to-date")
    }
    
    public func fetchingWillBegin(repository: String) {
        events.append("fetching repo: \(repository)")
    }

    public func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
        events.append("finished fetching repo: \(repository)")
    }

    public func cloning(repository: String) {
        events.append("cloning repo: \(repository)")
    }

    public func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
        events.append("checking out repo: \(repository)")
    }

    public func removing(repository: String) {
        events.append("removing repo: \(repository)")
    }

    public func willResolveDependencies() {
        events.append("will resolve dependencies")
    }

    public func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
        managedDependenciesData.append(dependencies)
    }
}
