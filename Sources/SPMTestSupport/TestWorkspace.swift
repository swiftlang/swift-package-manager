/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import PackageModel
import PackageLoading
import Workspace
import PackageGraph
import SourceControl

public final class TestWorkspace {

    let sandbox: AbsolutePath
    let fs: FileSystem
    let roots: [TestPackage]
    let packages: [TestPackage]
    public let config: SwiftPMConfig
    public var manifestLoader: MockManifestLoader
    public var repoProvider: InMemoryGitRepositoryProvider
    public let delegate = TestWorkspaceDelegate()
    let toolsVersion: ToolsVersion
    let skipUpdate: Bool
    let enablePubGrub: Bool

    public init(
        sandbox: AbsolutePath,
        fs: FileSystem,
        roots: [TestPackage],
        packages: [TestPackage],
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        skipUpdate: Bool = false,
        enablePubGrub: Bool = true
    ) throws {
        self.sandbox = sandbox
        self.fs = fs
        self.config = SwiftPMConfig(path: sandbox.appending(component: "swiftpm"), fs: fs)
        self.roots = roots
        self.packages = packages

        self.manifestLoader = MockManifestLoader(manifests: [:])
        self.repoProvider = InMemoryGitRepositoryProvider()
        self.toolsVersion = toolsVersion
        self.skipUpdate = skipUpdate
        self.enablePubGrub = enablePubGrub

        try create()
    }

    private var rootsDir: AbsolutePath {
        return sandbox.appending(component: "roots")
    }

    public var packagesDir: AbsolutePath {
        return sandbox.appending(component: "pkgs")
    }

    public func urlForPackage(withName name: String) -> String {
        return packagesDir.appending(RelativePath(name)).pathString
    }

    private func url(for package: TestPackage) -> String {
        return packagesDir.appending(RelativePath(package.path ?? package.name)).pathString
    }

    private func create() throws {
        // Remove the sandbox if present.
        try fs.removeFileTree(sandbox)

        // Create directories.
        try fs.createDirectory(sandbox, recursive: true)
        try fs.createDirectory(rootsDir)
        try fs.createDirectory(packagesDir)

        var manifests: [MockManifestLoader.Key: Manifest] = [:]

        func create(package: TestPackage, basePath: AbsolutePath, packageKind: PackageReference.Kind) throws {
            let packagePath = basePath.appending(RelativePath(package.path ?? package.name))

            let sourcesDir = packagePath.appending(component: "Sources")
            let url = (packageKind == .root ? packagePath : packagesDir.appending(RelativePath(package.path ?? package.name))).pathString
            let specifier = RepositorySpecifier(url: url)
            let manifestPath = packagePath.appending(component: Manifest.filename)

            // Create targets on disk.
            let repo = repoProvider.specifierMap[specifier] ?? InMemoryGitRepository(path: packagePath, fs: fs as! InMemoryFileSystem)
            for target in package.targets {
                let targetDir = sourcesDir.appending(component: target.name)
                try repo.createDirectory(targetDir, recursive: true)
                try repo.writeFileContents(targetDir.appending(component: "file.swift"), bytes: "")
            }
            let toolsVersion = package.toolsVersion ?? .currentToolsVersion
            try repo.writeFileContents(manifestPath, bytes: "")
            try writeToolsVersion(at: packagePath, version: toolsVersion, fs: repo)
            repo.commit()

            let versions: [String?] = packageKind == .remote ? package.versions : [nil]
            for version in versions {
                let v = version.flatMap(Version.init(string:))
                manifests[.init(url: url, version: v)] = Manifest(
                    name: package.name,
                    platforms: package.platforms,
                    path: manifestPath,
                    url: url,
                    version: v,
                    toolsVersion: toolsVersion,
                    packageKind: packageKind,
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
            try create(package: package, basePath: rootsDir, packageKind: .root)
        }

        // Create dependency packages.
        for package in packages {
            try create(package: package, basePath: packagesDir, packageKind: .remote)
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
            config: config,
            fileSystem: fs,
            repositoryProvider: repoProvider,
            enablePubgrubResolver: enablePubGrub,
            skipUpdate: skipUpdate
        )
        return _workspace!
    }
    private var _workspace: Workspace? = nil

    public func closeWorkspace() {
        _workspace = nil
    }

    public func rootPaths(for packages: [String]) -> [AbsolutePath] {
        return packages.map({ rootsDir.appending(RelativePath($0)) })
    }

    public struct PackageDependency {
        public typealias Requirement = PackageGraphRoot.PackageDependency.Requirement

        public let name: String
        public let requirement: Requirement

        public init(name: String, requirement: Requirement) {
            self.name = name
            self.requirement = requirement
        }

        fileprivate func convert(_ packagesDir: AbsolutePath, url: String) -> PackageGraphRootInput.PackageDependency {
            return PackageGraphRootInput.PackageDependency(
                url: url,
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

    public func checkResolve(pkg: String, roots: [String], version: TSCUtility.Version, _ result: (DiagnosticsEngine) -> ()) {
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
        packages: [String] = [],
        _ result: (DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir, url: urlForPackage(withName: $0.name)) })
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        workspace.updateDependencies(root: rootInput, packages: packages, diagnostics: diagnostics)
        result(diagnostics)
    }
    
    public func checkUpdateDryRun(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency] = [],
        _ result: ([(PackageReference, Workspace.PackageStateChange)]?, DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir, url: urlForPackage(withName: $0.name)) })
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        let changes = workspace.updateDependencies(root: rootInput, diagnostics: diagnostics, dryRun: true)
        result(changes, diagnostics)
    }

    public func checkPackageGraph(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency],
        _ result: (PackageGraph, DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir, url: urlForPackage(withName: $0.name)) })
        checkPackageGraph(roots: roots, dependencies: dependencies, result)
    }

    public func checkPackageGraph(
        roots: [String] = [],
        dependencies: [PackageGraphRootInput.PackageDependency] = [],
        forceResolvedVersions: Bool = false,
        _ result: (PackageGraph, DiagnosticsEngine) -> ()
    ) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: rootPaths(for: roots), dependencies: dependencies)
        let graph = workspace.loadPackageGraph(
            root: rootInput, forceResolvedVersions: forceResolvedVersions, diagnostics: diagnostics)
        result(graph, diagnostics)
    }

    public struct ResolutionPrecomputationResult {
        public let result: Workspace.ResolutionPrecomputationResult
        public let diagnostics: DiagnosticsEngine
    }

    public func checkPrecomputeResolution(
        pins: [PackageReference: CheckoutState],
        managedDependencies: [ManagedDependency],
        _ check: (ResolutionPrecomputationResult) -> ()
    ) throws {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let pinsStore = try workspace.pinsStore.load()

        let rootInput = PackageGraphRootInput(packages: rootPaths(for: roots.map({ $0.name })), dependencies: [])
        let rootManifests = workspace.loadRootManifests(packages: rootInput.packages, diagnostics: diagnostics)
        let root = PackageGraphRoot(input: rootInput, manifests: rootManifests)

        for (ref, state) in pins {
            pinsStore.pin(packageRef: ref, state: state)
        }

        let deps = workspace.managedDependencies
        for dependency in managedDependencies {
            try fs.createDirectory(workspace.path(for: dependency), recursive: true)
            deps[forURL: dependency.packageRef.path] = dependency
        }
        try deps.saveState()

        let dependencyManifests = workspace.loadDependencyManifests(root: root, diagnostics: diagnostics)

        let result = workspace.precomputeResolution(
            root: root,
            dependencyManifests: dependencyManifests,
            pinsStore: pinsStore,
            extraConstraints: []
        )

        check(ResolutionPrecomputationResult(result: result, diagnostics: diagnostics))
    }

    public enum State {
        public enum CheckoutState {
            case version(TSCUtility.Version)
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
            let dependency = try? managedDependencies.dependency(forNameOrIdentity: name)
            XCTAssert(dependency == nil, "Unexpectedly found \(name) in managed dependencies", file: file, line: line)
        }

        public func checkEmpty(file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(managedDependencies.values.map{$0}.count, 0, file: file, line: line)
        }

        public func check(dependency name: String, at state: State, file: StaticString = #file, line: UInt = #line) {
            guard let dependency = try? managedDependencies.dependency(forNameOrIdentity: name) else {
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
                    XCTFail("Expected edited dependency; found '\(dependency.state)' instead", file: file, line: line)
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
        let dependencies = deps.map({ $0.convert(packagesDir, url: urlForPackage(withName: $0.name)) })
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
                case .revision(let revision):
                    XCTAssertEqual(pin.state.revision.identifier, revision, file: file, line: line)
                case .branch(let branch):
                    XCTAssertEqual(pin.state.branch, branch, file: file, line: line)
                }
            case .edited, .local:
                XCTFail("Unimplemented", file: file, line: line)
            }
        }

        public func check(dependency package: String, url: String, file: StaticString = #file, line: UInt = #line) {
            guard let pin = store.pinsMap[package] else {
                XCTFail("Pin for \(package) not found", file: file, line: line)
                return
            }

            XCTAssertEqual(pin.packageRef.path, url, file: file, line: line)
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
    public let settings: [TargetBuildSettingDescription.Setting]
    public let type: Type

    public init(
        name: String,
        dependencies: [String] = [],
        type: Type = .regular,
        settings: [TargetBuildSettingDescription.Setting] = []
    ) {
        self.name = name
        self.dependencies = dependencies
        self.type = type
        self.settings = settings
    }

    fileprivate func convert() -> TargetDescription {
        switch type {
        case .regular:
            return TargetDescription(name: name, dependencies: dependencies.map({ .byName(name: $0) }), path: nil, exclude: [], sources: nil, publicHeadersPath: nil, type: .regular, settings: settings)
        case .test:
            return TargetDescription(name: name, dependencies: dependencies.map({ .byName(name: $0) }), path: nil, exclude: [], sources: nil, publicHeadersPath: nil, type: .test, settings: settings)
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
        return PackageDependencyDescription(
            name: name,
            url: baseURL.appending(RelativePath(name)).pathString,
            requirement: requirement
        )
    }
}

public struct TestPackage {

    public let name: String
    public let platforms: [PlatformDescription]
    public let path: String?
    public let targets: [TestTarget]
    public let products: [TestProduct]
    public let dependencies: [TestDependency]
    public let versions: [String?]
    // FIXME: This should be per-version.
    public let toolsVersion: ToolsVersion?

    public init(
        name: String,
        platforms: [PlatformDescription] = [],
        path: String? = nil,
        targets: [TestTarget],
        products: [TestProduct],
        dependencies: [TestDependency] = [],
        versions: [String?] = [],
        toolsVersion: ToolsVersion? = nil
    ) {
        self.name = name
        self.platforms = platforms
        self.path = path
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
        self.toolsVersion = toolsVersion
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

    public init() {}

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

    public func willResolveDependencies(reason: WorkspaceResolveReason) {
        events.append("will resolve dependencies")
    }
}
