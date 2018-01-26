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

private let sharedManifestLoader = ManifestLoader(resources: Resources.default)

extension Workspace {
    static func create(at tempPath: AbsolutePath) -> Workspace {
        let sandbox = tempPath.appending(component: "ws")
        return Workspace(
            dataPath: sandbox.appending(component: ".build"),
            editablesPath: sandbox.appending(component: "edits"),
            pinsFile: sandbox.appending(component: "Package.resolved"),
            manifestLoader: sharedManifestLoader,
            delegate: TestWorkspaceDelegate()
        )
    }
}


final class WorkspaceTests: XCTestCase {

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
                    versions: ["1.0.0", "1.5.0"]
                ),
                TestPackage(
                    name: "Quix",
                    targets: [
                        TestTarget(name: "Quix"),
                    ],
                    products: [
                        TestProduct(name: "Quix", targets: ["Quix"]),
                    ],
                    versions: ["1.0.0", "1.2.0"]
                ),
            ]
        )

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Quix", requirement: .upToNextMajor(from: "1.0.0")),
            .init(name: "Baz", requirement: .exact("1.0.0")),
        ]
        workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Quix")
                result.check(targets: "Bar", "Baz", "Foo", "Quix")
                result.check(testModules: "BarTests")
                result.check(dependencies: "Bar", target: "Foo")
                result.check(dependencies: "Baz", target: "Bar")
                result.check(dependencies: "Bar", target: "BarTests")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "quix", at: .checkout(.version("1.2.0")))
        }

        // Close and reopen workspace.
        workspace.closeWorkspace()
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "quix", at: .checkout(.version("1.2.0")))
        }

        // Remove state file and check we get back to a clean state.
        try fs.removeFileTree(workspace.createWorkspace().managedDependencies.statePath)
        workspace.closeWorkspace()
        workspace.checkManagedDependencies() { result in
            result.checkEmpty()
        }
    }

    func testInterpreterFlags() throws {
        let fs = localFileSystem
        mktmpdir { path in
            let foo = path.appending(component: "foo")
            try fs.writeFileContents(foo.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version:4.0
                import PackageDescription
                let package = Package(
                    name: "foo"
                )
                """
            }
            let ws = Workspace.create(at: path)
            XCTAssertMatch((ws.interpreterFlags(for: foo)), [.contains("swift/pm/4")])
            XCTAssertMatch((ws.interpreterFlags(for: foo)), [.equal("-swift-version"), .equal("4")])
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

    /// Test that the remote repository is not resolved when a root package with same name is already present.
    func testRootAsDependency1() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["BazAB"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "BazA"),
                        TestTarget(name: "BazB"),
                    ],
                    products: [
                        TestProduct(name: "BazAB", targets: ["BazA", "BazB"]),
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

        workspace.checkPackageGraph(roots: ["Foo", "Baz"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Baz", "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(targets: "BazA", "BazB", "Foo")
                result.check(dependencies: "BazAB", target: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(notPresent: "baz")
        }
        XCTAssertNoMatch(workspace.delegate.events, [.equal("fetching repo: /tmp/ws/pkgs/Baz")])
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
    }

    /// Test that a root package can be used as a dependency when the remote version was resolved previously.
    func testRootAsDependency2() throws {
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
                    name: "Baz",
                    targets: [
                        TestTarget(name: "BazA"),
                        TestTarget(name: "BazB"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["BazA", "BazB"]),
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

        // Load only Foo right now so Baz is loaded from remote.
        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(targets: "Baz", "Foo")
                result.check(dependencies: "Baz", target: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("fetching repo: /tmp/ws/pkgs/Baz")])
        XCTAssertMatch(workspace.delegate.events, [.equal("will resolve dependencies")])

        // Now load with Baz as a root package.
        workspace.delegate.events = []
        workspace.checkPackageGraph(roots: ["Foo", "Baz"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Baz", "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(targets: "BazA", "BazB", "Foo")
                result.check(dependencies: "Baz", target: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(notPresent: "baz")
        }
        XCTAssertNoMatch(workspace.delegate.events, [.equal("fetching repo: /tmp/ws/pkgs/Baz")])
        XCTAssertMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
        XCTAssertMatch(workspace.delegate.events, [.equal("removing repo: /tmp/ws/pkgs/Baz")])
    }

    func testGraphRootDependencies() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let dependencies: [PackageGraphRootInput.PackageDependency] = [
            .init(
                url: workspace.packagesDir.appending(component: "Bar").asString,
                requirement: .upToNextMajor(from: "1.0.0"),
                location: ""
            ),
            .init(
                url: "file://" + workspace.packagesDir.appending(component: "Foo").asString + "/",
                requirement: .upToNextMajor(from: "1.0.0"),
                location: ""
            ),
        ]

        workspace.checkPackageGraph(dependencies: dependencies) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo")
                result.check(targets: "Bar", "Foo")
                result.check(dependencies: "Bar", target: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testCanResolveWithIncompatiblePins() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "AA", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "AA", requirement: .exact("2.0.0")),
                    ],
                    versions: ["1.0.1"]
                ),
                TestPackage(
                    name: "AA",
                    targets: [
                        TestTarget(name: "AA"),
                    ],
                    products: [
                        TestProduct(name: "AA", targets: ["AA"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        // Resolve when A = 1.0.0.
        do {
            let deps: [TestWorkspace.PackageDependency] = [
                .init(name: "A", requirement: .exact("1.0.0"))
            ]
            workspace.checkPackageGraph(deps: deps) { (graph, diagnostics) in
                PackageGraphTester(graph) { result in
                    result.check(packages: "A", "AA")
                    result.check(targets: "A", "AA")
                    result.check(dependencies: "AA", target: "A")
                }
                XCTAssertNoDiagnostics(diagnostics)
            }
            workspace.checkManagedDependencies() { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.0")))
                result.check(dependency: "aa", at: .checkout(.version("1.0.0")))
            }
            workspace.checkResolved() { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.0")))
                result.check(dependency: "aa", at: .checkout(.version("1.0.0")))
            }
        }

        // Resolve when A = 1.0.1.
        do {
            let deps: [TestWorkspace.PackageDependency] = [
                .init(name: "A", requirement: .exact("1.0.1"))
            ]
            workspace.checkPackageGraph(deps: deps) { (graph, diagnostics) in
                PackageGraphTester(graph) { result in
                    result.check(dependencies: "AA", target: "A")
                }
                XCTAssertNoDiagnostics(diagnostics)
            }
            workspace.checkManagedDependencies() { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.1")))
                result.check(dependency: "aa", at: .checkout(.version("2.0.0")))
            }
            workspace.checkResolved() { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.1")))
                result.check(dependency: "aa", at: .checkout(.version("2.0.0")))
            }
            XCTAssertMatch(workspace.delegate.events, [.equal("updating repo: /tmp/ws/pkgs/A")])
            XCTAssertMatch(workspace.delegate.events, [.equal("updating repo: /tmp/ws/pkgs/AA")])
            XCTAssertEqual(workspace.delegate.events.filter({ $0.hasPrefix("updating repo") }).count, 2)
        }
    }

    func testResolverCanHaveError() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "AA", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "B",
                    targets: [
                        TestTarget(name: "B", dependencies: ["AA"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "AA", requirement: .exact("2.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "AA",
                    targets: [
                        TestTarget(name: "AA"),
                    ],
                    products: [
                        TestProduct(name: "AA", targets: ["AA"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "A", requirement: .exact("1.0.0")),
            .init(name: "B", requirement: .exact("1.0.0")),
        ]
        workspace.checkPackageGraph(deps: deps) { (_, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("dependency graph is unresolvable;"), behavior: .error)
            }
        }
        // There should be no extra fetches.
        XCTAssertNoMatch(workspace.delegate.events, [.contains("updating repo")])
    }

    func testIsResolutionRequired() throws {
        let aRepo = RepositorySpecifier(url: "/A")
        let bRepo = RepositorySpecifier(url: "/B")
        let cRepo = RepositorySpecifier(url: "/C")
        let aRef = PackageReference(identity: "a", path: aRepo.url)
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)
        let v1 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.0")
        let v1_1 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.1")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")
        let v2 = CheckoutState(revision: Revision(identifier: "hello"), version: "2.0.0")

        let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")
        let v2Range: VersionSetSpecifier = .range("2.0.0" ..< "3.0.0")

        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A"),
                    ],
                    products: []
                ),
            ],
            packages: []
        ).createWorkspace()

        let pinsStore = try workspace.pinsStore.load()

        // Test Empty case.
        do {
            let result = workspace.isResolutionRequired(dependencies: [], pinsStore: pinsStore)
            XCTAssertEqual(result.resolve, false)
        }

        // Fill the pinsStore.
        pinsStore.pin(packageRef: aRef, state: v1)
        pinsStore.pin(packageRef: bRef, state: v1_5)
        pinsStore.pin(packageRef: cRef, state: v2)

        // Fill ManagedDependencies (all different than pins).
        let managedDependencies = workspace.managedDependencies
        managedDependencies[forIdentity: aRef.identity] = ManagedDependency(
            packageRef: aRef, subpath: RelativePath("A"), checkoutState: v1_1)
        managedDependencies[forIdentity: bRef.identity] = ManagedDependency(
            packageRef: bRef, subpath: RelativePath("B"), checkoutState: v1_5)
        managedDependencies[forIdentity: bRef.identity] = managedDependencies[forIdentity: bRef.identity]?.editedDependency(
            subpath: RelativePath("B"), unmanagedPath: nil)

        // We should need to resolve if input is not satisfiable.
        do {
            let result = workspace.isResolutionRequired(dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: aRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.count, 3)
        }

        // We should need to resolve when pins don't satisfy the inputs.
        do {
            let result = workspace.isResolutionRequired(dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v1Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.map({$0.identifier.repository.url}).sorted(), ["/A", "/B"])
        }

        // We should need to resolve if managed dependencies is out of sync with pins.
        do {
            let result = workspace.isResolutionRequired(dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.map({$0.identifier.repository.url}).sorted(), ["/A", "/B", "/C"])
        }

        // We shouldn't need to resolve if everything is fine.
        do {
            managedDependencies[forIdentity: aRef.identity] = ManagedDependency(
                packageRef: aRef, subpath: RelativePath("A"), checkoutState: v1)
            managedDependencies[forIdentity: bRef.identity] = ManagedDependency(
                packageRef: bRef, subpath: RelativePath("B"), checkoutState: v1_5)
            managedDependencies[forIdentity: cRef.identity] = ManagedDependency(
                packageRef: cRef, subpath: RelativePath("C"), checkoutState: v2)

            let result = workspace.isResolutionRequired(dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, false)
            XCTAssertEqual(result.validPins, [])
        }
    }

    func testGraphData() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
            ],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A"),
                    ],
                    products: [],
                    versions: ["1.0.0", "1.5.1"]
                ),
                TestPackage(
                    name: "B",
                    targets: [
                        TestTarget(name: "B"),
                    ],
                    products: [],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "A", requirement: .exact("1.0.0")),
            .init(name: "B", requirement: .exact("1.0.0")),
        ]
        workspace.checkGraphData(deps: deps) { (graph, dependencyMap, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "A", "B")
                result.check(targets: "A", "B")
            }

            // Check package association.
            XCTAssertEqual(dependencyMap[graph.lookup("A")]?.packageRef.identity, "a")
            XCTAssertEqual(dependencyMap[graph.lookup("B")]?.packageRef.identity, "b")
            XCTAssertNoDiagnostics(diagnostics)
        }
        // Check delegates.
        let currentDeps = workspace.createWorkspace().managedDependencies.values.map{$0.packageRef}
        XCTAssertEqual(workspace.delegate.managedDependenciesData[0].map{$0.packageRef}, currentDeps)

        // Load graph data again.
        workspace.checkGraphData(deps: deps) { (graph, dependencyMap, diagnostics) in
            // Check package association.
            XCTAssertEqual(dependencyMap[graph.lookup("A")]?.packageRef.identity, "a")
            XCTAssertEqual(dependencyMap[graph.lookup("B")]?.packageRef.identity, "b")
            XCTAssertNoDiagnostics(diagnostics)
        }
        // Check delegates.
        XCTAssertEqual(workspace.delegate.managedDependenciesData[1].map{$0.packageRef}, currentDeps)
        XCTAssertEqual(workspace.delegate.managedDependenciesData.count, 2)
    }

    func testLoadingRootManifests() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                .genericPackage1(named: "A"),
                .genericPackage1(named: "B"),
                .genericPackage1(named: "C"),
            ],
            packages: []
        )

        workspace.checkPackageGraph(roots: ["A", "B", "C"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "A", "B", "C")
                result.check(targets: "A", "B", "C")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testUpdate() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        TestProduct(name: "Root", targets: ["Root"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.5.0"]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Do an intial run, capping at Foo at 1.0.0.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .exact("1.0.0")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run update.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("removing repo: /tmp/ws/pkgs/Bar")])
        
        // Run update again.
        // Ensure that up-to-date delegate is called when there is nothing to update.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("Everything is already up-to-date")])
    }

    func testCleanAndReset() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        TestProduct(name: "Root", targets: ["Root"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Load package graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Drop a build artifact in data directory.
        let ws = workspace.createWorkspace()
        let buildArtifact = ws.dataPath.appending(component: "test.o")
        try fs.writeFileContents(buildArtifact, bytes: "Hi")

        // Sanity checks.
        XCTAssert(fs.exists(buildArtifact))
        XCTAssert(fs.exists(ws.checkoutsPath))

        // Check clean.
        workspace.checkClean { diagnostics in
            // Only the build artifact should be removed.
            XCTAssertFalse(fs.exists(buildArtifact))
            XCTAssert(fs.exists(ws.checkoutsPath))
            XCTAssert(fs.exists(ws.dataPath))

            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Add the build artifact again.
        try fs.writeFileContents(buildArtifact, bytes: "Hi")

        // Check reset.
        workspace.checkReset { diagnostics in
            // Only the build artifact should be removed.
            XCTAssertFalse(fs.exists(buildArtifact))
            XCTAssertFalse(fs.exists(ws.checkoutsPath))
            XCTAssertFalse(fs.exists(ws.dataPath))

            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.checkEmpty()
        }
    }

    func testDependencyManifestLoading() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root1",
                    targets: [
                        TestTarget(name: "Root1", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                TestPackage(
                    name: "Root2",
                    targets: [
                        TestTarget(name: "Root2", dependencies: ["Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                .genericPackage1(named: "Foo"),
                .genericPackage1(named: "Bar"),
            ]
        )

        // Check that we can compute missing dependencies.
        workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { (manifests, diagnostics) in
            XCTAssertEqual(manifests.missingPackageIdentities().map{$0}.sorted(), ["bar", "foo"])
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Load the graph with one root.
        workspace.checkPackageGraph(roots: ["Root1"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "Foo", "Root1")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Check that we compute the correct missing dependencies.
        workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { (manifests, diagnostics) in
            XCTAssertEqual(manifests.missingPackageIdentities().map{$0}.sorted(), ["bar"])
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Load the graph with both roots.
        workspace.checkPackageGraph(roots: ["Root1", "Root2"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo", "Root1", "Root2")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Check that we compute the correct missing dependencies.
        workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { (manifests, diagnostics) in
            XCTAssertEqual(manifests.missingPackageIdentities().map{$0}.sorted(), [])
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testBranchAndRevision() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .branch("develop")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["develop"]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["boo"]
                ),
            ]
        )

        // Get some revision identifier of Bar.
        let bar = RepositorySpecifier(url: "/tmp/ws/pkgs/Bar")
        let barRevision = workspace.repoProvider.specifierMap[bar]!.revisions[0]

        // We request Bar via revision.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bar", requirement: .revision(barRevision))
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
            result.check(dependency: "bar", at: .checkout(.revision(barRevision)))
        }
    }

    func testResolve() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.3"]
                ),
            ]
        )

        // Load initial version.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.3")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.3")))
        }

        // Resolve to an older version.
        workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.0.0") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Check failure.
        workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.3.0") { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("tmp/ws/pkgs/Foo @ 1.3.0"), behavior: .error)
            }
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testDeletedCheckoutDirectory() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                .genericPackage1(named: "Foo"),
            ]
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        try fs.removeFileTree(workspace.createWorkspace().checkoutsPath)

        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("dependency 'foo' is missing; cloning again"), behavior: .warning)
            }
        }
    }

    func testToolsVersionRootPackages() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: []
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: []
                ),
            ],
            packages: [],
            toolsVersion: ToolsVersion(version: "4.0.0")
        )

        let roots = workspace.rootPaths(for: ["Foo", "Bar"]).map({ $0.appending(component: "Package.swift") })

        try fs.writeFileContents(roots[0], bytes: "// swift-tools-version:4.0")
        try fs.writeFileContents(roots[1], bytes: "// swift-tools-version:4.1.0")

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkPackageGraph(roots: ["Bar"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package at '/tmp/ws/roots/Bar' requires a minimum Swift tools version of 4.1.0 (currently 4.0.0)"), behavior: .error, location: "/tmp/ws/roots/Bar")
            }
        }
        workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package at '/tmp/ws/roots/Bar' requires a minimum Swift tools version of 4.1.0 (currently 4.0.0)"), behavior: .error, location: "/tmp/ws/roots/Bar")
            }
        }
    }

    func testEditDependency() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                        ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                        ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Edit foo.
        let fooPath = workspace.createWorkspace().editablesPath.appending(component: "Foo")
        workspace.checkEdit(packageName: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        XCTAssertTrue(fs.exists(fooPath))

        // Try re-editing foo.
        workspace.checkEdit(packageName: "Foo") { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("dependency 'Foo' already in edit mode"), behavior: .error)
            }
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Try editing bar at bad revision.
        workspace.checkEdit(packageName: "Bar", revision: Revision(identifier: "dev")) { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("revision 'dev' does not exist"), behavior: .error)
            }
        }

        // Edit bar at a custom path and branch (ToT).
        let barPath = AbsolutePath("/tmp/ws/custom/bar")
        workspace.checkEdit(packageName: "Bar", path: barPath, checkoutBranch: "dev") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .edited(barPath))
        }
        let barRepo = try workspace.repoProvider.openCheckout(at: barPath) as! InMemoryGitRepository
        XCTAssert(barRepo.revisions.contains("dev"))

        // Test unediting.
        workspace.checkUnedit(packageName: "Foo", roots: ["Root"]) { diagnostics in
            XCTAssertFalse(fs.exists(fooPath))
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkUnedit(packageName: "Bar", roots: ["Root"]) { diagnostics in
            XCTAssert(fs.exists(barPath))
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testMissingEditCanRestoreOriginalCheckout() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { _, _ in }

        // Edit foo.
        let fooPath = workspace.createWorkspace().editablesPath.appending(component: "Foo")
        workspace.checkEdit(packageName: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        XCTAssertTrue(fs.exists(fooPath))

        // Remove the edited package.
        try fs.removeFileTree(fooPath)
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("dependency 'foo' was being edited but is missing; falling back to original checkout"), behavior: .warning)
            }
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testCanUneditRemovedDependencies() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
        ]
        let ws = workspace.createWorkspace()

        // Load the graph and edit foo.
        workspace.checkPackageGraph(deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkEdit(packageName: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Remove foo.
        workspace.checkUpdate { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("removing repo: /tmp/ws/pkgs/Foo")])
        workspace.checkPackageGraph(deps: []) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }

        // There should still be an entry for `foo`, which we can unedit.
        let editedDependency = try ws.managedDependencies.dependency(forNameOrIdentity: "foo")
        XCTAssertNil(editedDependency.basedOn)
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Unedit foo.
        workspace.checkUnedit(packageName: "Foo", roots: []) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.checkEmpty()
        }
    }

    func testDependencyResolutionWithEdit() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.0", "1.3.2"]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .exact("1.0.0")),
        ]
        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Edit bar.
        workspace.checkEdit(packageName: "Bar") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Now, resolve foo at a different version.
        workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.2.0") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
            result.check(notPresent: "bar")
        }

        // Try package update.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(notPresent: "bar")
        }

        // Unedit should get the Package.resolved entry back.
        workspace.checkUnedit(packageName: "bar", roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    // Test that changing a particular dependency re-resolves the graph.
    func testChangeOneDependency() throws {
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
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        // Initial resolution.
        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Check that changing the requirement to 1.5.0 triggers re-resolution.
        //
        // FIXME: Find a cleaner way to change a dependency requirement.
        let package = workspace.manifestLoader.manifests[MockManifestLoader.Key(url: "Foo")]!.package.pkg
        package.dependencies[0] = .package(url: package.dependencies[0].url, .exact("1.5.0"))

        workspace.checkPackageGraph(roots: ["Foo"]) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }
    }

    func testResolutionFailureWithEditedDependency() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkEdit(packageName: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Try resolving a bad graph.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bar", requirement: .exact("1.1.0")),
        ]
        workspace.checkUpdate(roots: ["Root"], deps: deps) { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("/tmp/ws/pkgs/Bar @ 1.1.0"), behavior: .error)
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testCanResolveWithIncompatiblePins", testCanResolveWithIncompatiblePins),
        ("testGraphData", testGraphData),
        ("testIsResolutionRequired", testIsResolutionRequired),
        ("testMultipleRootPackages", testMultipleRootPackages),
        ("testResolverCanHaveError", testResolverCanHaveError),
        ("testRootAsDependency1", testRootAsDependency1),
        ("testRootAsDependency2", testRootAsDependency1),
        ("testLoadingRootManifests", testLoadingRootManifests),
        ("testUpdate", testUpdate),
        ("testCleanAndReset", testCleanAndReset),
        ("testDependencyManifestLoading", testDependencyManifestLoading),
        ("testBranchAndRevision", testBranchAndRevision),
        ("testResolve", testResolve),
        ("testDeletedCheckoutDirectory", testDeletedCheckoutDirectory),
        ("testToolsVersionRootPackages", testToolsVersionRootPackages),
        ("testEditDependency", testEditDependency),
        ("testMissingEditCanRestoreOriginalCheckout", testMissingEditCanRestoreOriginalCheckout),
        ("testCanUneditRemovedDependencies", testCanUneditRemovedDependencies),
        ("testInterpreterFlags", testInterpreterFlags),
        ("testDependencyResolutionWithEdit", testDependencyResolutionWithEdit),
        ("testChangeOneDependency", testChangeOneDependency),
        ("testResolutionFailureWithEditedDependency", testResolutionFailureWithEditedDependency),
    ]
}

extension Manifest.RawPackage {
    var pkg: PackageDescription4.Package {
        switch self {
        case .v4(let pkg): return pkg
        default: fatalError()
        }
    }
}

// MARK:- Test Infrastructure

private class TestWorkspaceDelegate: WorkspaceDelegate {

    var events = [String]()
    var managedDependenciesData = [AnySequence<ManagedDependency>]()

    func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>) {
    }

    func repositoryWillUpdate(_ repository: String) {
        events.append("updating repo: \(repository)")
    }

    func dependenciesUpToDate() {
        events.append("Everything is already up-to-date")
    }
    
    func fetchingWillBegin(repository: String) {
        events.append("fetching repo: \(repository)")
    }

    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
        events.append("finished fetching repo: \(repository)")
    }

    func cloning(repository: String) {
        events.append("cloning repo: \(repository)")
    }

    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
        events.append("checking out repo: \(repository)")
    }

    func removing(repository: String) {
        events.append("removing repo: \(repository)")
    }

    func willResolveDependencies() {
        events.append("will resolve dependencies")
    }

    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
        managedDependenciesData.append(dependencies)
    }
}

private final class TestWorkspace {

    let sandbox: AbsolutePath
    let fs: FileSystem
    let roots: [TestPackage]
    let packages: [TestPackage]
    var manifestLoader: MockManifestLoader
    var repoProvider: InMemoryGitRepositoryProvider
    let delegate = TestWorkspaceDelegate()
    let toolsVersion: ToolsVersion

    fileprivate init(
        sandbox: AbsolutePath,
        fs: FileSystem,
        roots: [TestPackage],
        packages: [TestPackage],
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion
    ) throws {
        precondition(Set(roots.map({$0.name})).count == roots.count, "Root packages should be unique")
        self.sandbox = sandbox
        self.fs = fs
        self.roots = roots
        self.packages = packages

        self.manifestLoader = MockManifestLoader(manifests: [:])
        self.repoProvider = InMemoryGitRepositoryProvider()
        self.toolsVersion = toolsVersion

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
            let url = (isRoot ? packagePath : packagesDir.appending(component: package.name)).asString
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

    func createWorkspace() -> Workspace {
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
            repositoryProvider: repoProvider
        )
        return _workspace!
    }
    var _workspace: Workspace? = nil

    func closeWorkspace() {
        _workspace = nil
    }

    func rootPaths(for packages: [String]) -> [AbsolutePath] {
        return packages.map({ rootsDir.appending(component: $0) })
    }

    struct PackageDependency {
        typealias Requirement = PackageGraphRoot.PackageDependency.Requirement

        let name: String
        let requirement: Requirement

        init(name: String, requirement: Requirement) {
            self.name = name
            self.requirement = requirement
        }

        func convert(_ packagesDir: AbsolutePath) -> PackageGraphRootInput.PackageDependency {
            return PackageGraphRootInput.PackageDependency(
                url: packagesDir.appending(component: name).asString,
                requirement: requirement,
                location: name
            )
        }
    }

    func checkEdit(
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

    func checkUnedit(
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

    func checkResolve(pkg: String, roots: [String], version: Utility.Version, _ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        let rootInput = PackageGraphRootInput(packages: rootPaths(for: roots))
        workspace.resolve(packageName: pkg, root: rootInput, version: version, branch: nil, revision: nil, diagnostics: diagnostics)
        result(diagnostics)
    }

    func checkClean(_ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        workspace.clean(with: diagnostics)
        result(diagnostics)
    }

    func checkReset(_ result: (DiagnosticsEngine) -> ()) {
        let diagnostics = DiagnosticsEngine()
        let workspace = createWorkspace()
        workspace.reset(with: diagnostics)
        result(diagnostics)
    }

    func checkUpdate(
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

    func checkPackageGraph(
        roots: [String] = [],
        deps: [TestWorkspace.PackageDependency],
        _ result: (PackageGraph, DiagnosticsEngine) -> ()
    ) {
        let dependencies = deps.map({ $0.convert(packagesDir) })
        checkPackageGraph(roots: roots, dependencies: dependencies, result)
    }

    func checkPackageGraph(
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

    func checkGraphData(
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

    enum State {
        enum CheckoutState {
            case version(Utility.Version)
            case revision(String)
            case branch(String)
        }
        case checkout(CheckoutState)
        case edited(AbsolutePath?)
    }

    struct ManagedDependencyResult {

        let managedDependencies: ManagedDependencies

        init(_ managedDependencies: ManagedDependencies) {
            self.managedDependencies = managedDependencies
        }

        func check(notPresent name: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssert(managedDependencies[forIdentity: name] == nil, "Unexpectedly found \(name) in managed dependencies", file: file, line: line)
        }

        func checkEmpty(file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(managedDependencies.values.map{$0}.count, 0, file: file, line: line)
        }

        func check(dependency name: String, at state: State, file: StaticString = #file, line: UInt = #line) {
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
            }
        }
    }

    func loadDependencyManifests(
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

    func checkManagedDependencies(file: StaticString = #file, line: UInt = #line, _ result: (ManagedDependencyResult) throws -> ()) {
        do {
            let workspace = createWorkspace()
            try result(ManagedDependencyResult(workspace.managedDependencies))
        } catch {
            XCTFail("Failed with error \(error)", file: file, line: line)
        }
    }

    struct ResolvedResult {
        let store: PinsStore

        init(_ store: PinsStore) {
            self.store = store
        }

        func check(notPresent name: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssert(store.pinsMap[name] == nil, "Unexpectedly found \(name) in Package.resolved", file: file, line: line)
        }

        func check(dependency package: String, at state: State, file: StaticString = #file, line: UInt = #line) {
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
            case .edited:
                XCTFail("Unimplemented", file: file, line: line)
            }
        }
    }

    func checkResolved(file: StaticString = #file, line: UInt = #line, _ result: (ResolvedResult) throws -> ()) {
        do {
            let workspace = createWorkspace()
            try result(ResolvedResult(workspace.pinsStore.load()))
        } catch {
            XCTFail("Failed with error \(error)", file: file, line: line)
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
    let versions: [String?]

    fileprivate init(
        name: String,
        targets: [TestTarget],
        products: [TestProduct],
        dependencies: [TestDependency] = [],
        versions: [String?] = []
    ) {
        self.name = name
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
    }

    static func genericPackage1(named name: String) -> TestPackage {
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

extension PackageGraph {
    /// Finds the package matching the given name.
    func lookup(_ name: String) -> PackageModel.ResolvedPackage {
        return packages.first{ $0.name == name }!
    }
}
