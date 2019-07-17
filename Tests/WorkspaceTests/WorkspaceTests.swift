/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import SPMBasic
import PackageLoading
import PackageModel
import PackageGraph
import SPMSourceControl
import SPMUtility
@testable import SPMWorkspace

import TestSupport

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

        let stateFile = workspace.createWorkspace().managedDependencies.statePath

        // Remove state file and check we can get the state back automatically.
        try fs.removeFileTree(stateFile)

        workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { _, _ in }
        XCTAssertTrue(fs.exists(stateFile))

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

            func createWorkspace(withManifest manifest: (OutputByteStream) -> ()) throws -> Workspace {
                try fs.writeFileContents(foo.appending(component: "Package.swift")) {
                    manifest($0)
                }

                let manifestLoader = ManifestLoader(manifestResources: Resources.default)

                let sandbox = path.appending(component: "ws")
                return Workspace(
                    dataPath: sandbox.appending(component: ".build"),
                    editablesPath: sandbox.appending(component: "edits"),
                    pinsFile: sandbox.appending(component: "Package.resolved"),
                    manifestLoader: manifestLoader,
                    delegate: TestWorkspaceDelegate()
                )
            }

            do {
                let ws = try createWorkspace {
                    $0 <<<
                        """
                        // swift-tools-version:4.0
                        import PackageDescription
                        let package = Package(
                            name: "foo"
                        )
                        """
                }

                XCTAssertMatch((ws.interpreterFlags(for: foo)), [.contains("swift/pm/4")])
                XCTAssertMatch((ws.interpreterFlags(for: foo)), [.equal("-swift-version"), .equal("4")])
            }

            do {
                let ws = try createWorkspace {
                    $0 <<<
                        """
                        // swift-tools-version:3.1
                        import PackageDescription
                        let package = Package(
                            name: "foo"
                        )
                        """
                }

                XCTAssertEqual(ws.interpreterFlags(for: foo), [])
            }
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

	func testRootPackagesOverride() throws {
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
                        TestDependency(name: "bazzz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: []
                ),
                TestPackage(
                    name: "Baz",
                    path: "Overridden/bazzz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Baz",
                    path: "bazzz",
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

        workspace.checkPackageGraph(roots: ["Foo", "Bar", "Overridden/bazzz"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Bar", "Foo", "Baz")
                result.check(packages: "Bar", "Baz", "Foo")
                result.check(dependencies: "Baz", target: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDependencyRefsAreIteratedInStableOrder() throws {
        // This graph has two references to Bar, one with .git suffix and one without.
        // The test ensures that we use the URL which appears first (i.e. the one with .git suffix).

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
                url: workspace.packagesDir.appending(component: "Foo").pathString,
                requirement: .upToNextMajor(from: "1.0.0"),
                location: ""
            ),
            .init(
                url: workspace.packagesDir.appending(component: "Bar").pathString + ".git",
                requirement: .upToNextMajor(from: "1.0.0"),
                location: ""
            ),
        ]

        // Add entry for the Bar.git package.
        do {
            let barKey = MockManifestLoader.Key(url: "/tmp/ws/pkgs/Bar", version: "1.0.0")
            let barGitKey = MockManifestLoader.Key(url: "/tmp/ws/pkgs/Bar.git", version: "1.0.0")
            let manifest = workspace.manifestLoader.manifests[barKey]!
            workspace.manifestLoader.manifests[barGitKey] = manifest.with(url: "/tmp/ws/pkgs/Bar.git")
        }

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
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", url: "/tmp/ws/pkgs/Bar.git")
        }
    }

	func testDuplicateRootPackages() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
                TestPackage(
                    name: "Foo",
                    path: "Nested/Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: []
        )

        workspace.checkPackageGraph(roots: ["Foo", "Nested/Foo"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("found multiple top-level packages named 'Foo'"), behavior: .error)
            }
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
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
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
                url: workspace.packagesDir.appending(component: "Bar").pathString,
                requirement: .upToNextMajor(from: "1.0.0"),
                location: ""
            ),
            .init(
                url: "file://\(workspace.packagesDir.appending(component: "Foo").pathString)/",
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
                result.check(diagnostic: .contains("the package dependency graph could not be resolved; possibly because of these requirements"), behavior: .error)
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

        let testWorkspace = try TestWorkspace(
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
        )

        let workspace = testWorkspace.createWorkspace()
        let pinsStore = try workspace.pinsStore.load()

        let rootInput = PackageGraphRootInput(packages: testWorkspace.rootPaths(for: ["A"]))
        let rootManifests = workspace.loadRootManifests(packages: rootInput.packages, diagnostics: DiagnosticsEngine())
        let root = PackageGraphRoot(input: rootInput, manifests: rootManifests)

        // Test Empty case.
        do {
            let result = workspace.isResolutionRequired(root: root, dependencies: [], pinsStore: pinsStore)
            XCTAssertEqual(result.resolve, false)
        }

        // Fill the pinsStore.
        pinsStore.pin(packageRef: aRef, state: v1)
        pinsStore.pin(packageRef: bRef, state: v1_5)
        pinsStore.pin(packageRef: cRef, state: v2)

        // Fill ManagedDependencies (all different than pins).
        let managedDependencies = workspace.managedDependencies
        managedDependencies[forURL: aRef.path] = ManagedDependency(
            packageRef: aRef, subpath: RelativePath("A"), checkoutState: v1_1)
        managedDependencies[forURL: bRef.path] = ManagedDependency(
            packageRef: bRef, subpath: RelativePath("B"), checkoutState: v1_5)
        managedDependencies[forURL: bRef.path] = managedDependencies[forURL: bRef.path]?.editedDependency(
            subpath: RelativePath("B"), unmanagedPath: nil)

        // We should need to resolve if input is not satisfiable.
        do {
            let result = workspace.isResolutionRequired(root: root, dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: aRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.count, 3)
        }

        // We should need to resolve when pins don't satisfy the inputs.
        do {
            let result = workspace.isResolutionRequired(root: root, dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v1Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.map({$0.identifier.repository.url}).sorted(), ["/A", "/B"])
        }

        // We should need to resolve if managed dependencies is out of sync with pins.
        do {
            let result = workspace.isResolutionRequired(root: root, dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, true)
            XCTAssertEqual(result.validPins.map({$0.identifier.repository.url}).sorted(), ["/A", "/B", "/C"])
        }

        // We shouldn't need to resolve if everything is fine.
        do {
            managedDependencies[forURL: aRef.path] = ManagedDependency(
                packageRef: aRef, subpath: RelativePath("A"), checkoutState: v1)
            managedDependencies[forURL: bRef.path] = ManagedDependency(
                packageRef: bRef, subpath: RelativePath("B"), checkoutState: v1_5)
            managedDependencies[forURL: cRef.path] = ManagedDependency(
                packageRef: cRef, subpath: RelativePath("C"), checkoutState: v2)

            let result = workspace.isResolutionRequired(root: root, dependencies: [
                RepositoryPackageConstraint(container: aRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: bRef, versionRequirement: v1Range),
                RepositoryPackageConstraint(container: cRef, versionRequirement: v2Range),
            ], pinsStore: pinsStore)

            XCTAssertEqual(result.resolve, false)
            XCTAssertEqual(result.validPins, [])
        }
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
            XCTAssertEqual(manifests.missingPackageURLs().map{$0.path}.sorted(), ["/tmp/ws/pkgs/Bar", "/tmp/ws/pkgs/Foo"])
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
            XCTAssertEqual(manifests.missingPackageURLs().map{$0.path}.sorted(), ["/tmp/ws/pkgs/Bar"])
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
            XCTAssertEqual(manifests.missingPackageURLs().map{$0.path}.sorted(), [])
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDependencyManifestsOrder() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root1",
                    targets: [
                        TestTarget(name: "Root1", dependencies: ["Foo", "Bar", "Baz", "Bam"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                .genericPackage1(named: "Bar"),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz", dependencies: ["Bam"]),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                .genericPackage1(named: "Bam"),
            ]
        )

        workspace.checkPackageGraph(roots: ["Root1"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }

        workspace.loadDependencyManifests(roots: ["Root1"]) { (manifests, diagnostics) in
			// Ensure that the order of the manifests is stable.
			XCTAssertEqual(manifests.allManifests().map({$0.name}), ["Foo", "Baz", "Bam", "Bar"])
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

    func testMinimumRequiredToolsVersionInDependencyResolution() throws {
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
                    versions: ["1.0.0"],
                    toolsVersion: .v3
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("/tmp/ws/pkgs/Foo @ 1.0.0..<2.0.0"), behavior: .error)
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
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: []
                ),
            ],
            packages: [],
            toolsVersion: .v4
        )

        let roots = workspace.rootPaths(for: ["Foo", "Bar", "Baz"]).map({ $0.appending(component: "Package.swift") })

        try fs.writeFileContents(roots[0], bytes: "// swift-tools-version:4.0")
        try fs.writeFileContents(roots[1], bytes: "// swift-tools-version:4.1.0")
        try fs.writeFileContents(roots[2], bytes: "// swift-tools-version:3.1")

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkPackageGraph(roots: ["Bar"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package at '/tmp/ws/roots/Bar' is using Swift tools version 4.1.0 but the installed version is 4.0.0"), behavior: .error, location: "/tmp/ws/roots/Bar")
            }
        }
        workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package at '/tmp/ws/roots/Bar' is using Swift tools version 4.1.0 but the installed version is 4.0.0"), behavior: .error, location: "/tmp/ws/roots/Bar")
            }
        }
        workspace.checkPackageGraph(roots: ["Baz"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package at '/tmp/ws/roots/Baz' is using Swift tools version 3.1.0 which is no longer supported; consider using '// swift-tools-version:4.0' to specify the current tools version"), behavior: .error, location: "/tmp/ws/roots/Baz")
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

        workspace.loadDependencyManifests(roots: ["Root"]) { (manifests, diagnostics) in
            let editedPackages = manifests.editedPackagesConstraints()
            XCTAssertEqual(editedPackages.map({ $0.identifier.path }), [fooPath.pathString])
            XCTAssertNoDiagnostics(diagnostics)
        }

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

        // Add entry for the edited package.
        do {
            let barKey = MockManifestLoader.Key(url: "/tmp/ws/pkgs/Bar")
            let editedBarKey = MockManifestLoader.Key(url: "/tmp/ws/edits/Bar")
            let manifest = workspace.manifestLoader.manifests[barKey]!
            workspace.manifestLoader.manifests[editedBarKey] = manifest
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
        let fooKey = MockManifestLoader.Key(url: "/tmp/ws/roots/Foo")
        let manifest = workspace.manifestLoader.manifests[fooKey]!
        workspace.manifestLoader.manifests[fooKey] = Manifest(
            name: manifest.name,
            platforms: [],
            path: manifest.path,
            url: manifest.url,
            version: manifest.version,
            manifestVersion: manifest.manifestVersion,
            dependencies: [PackageDependencyDescription(url: manifest.dependencies[0].url, requirement: .exact("1.5.0"))],
            targets: manifest.targets
        )

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
        workspace.checkResolved() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Add entry for the edited package.
        do {
            let fooKey = MockManifestLoader.Key(url: "/tmp/ws/pkgs/Foo")
            let editedFooKey = MockManifestLoader.Key(url: "/tmp/ws/edits/Foo")
            let manifest = workspace.manifestLoader.manifests[fooKey]!
            workspace.manifestLoader.manifests[editedFooKey] = manifest
        }

        // Try resolving a bad graph.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bar", requirement: .exact("1.1.0")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("/tmp/ws/pkgs/Bar @ 1.1.0"), behavior: .error)
            }
        }
    }

    func testSkipUpdate() throws {
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
                    versions: ["1.5.0"]
                ),
            ],
            skipUpdate: true
        )

        // Run update and remove all events.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.delegate.events = []

        // Check we don't have updating Foo event.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(workspace.delegate.events, ["Everything is already up-to-date"])
        }
    }

    func testLocalDependencyBasics() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
                        TestTarget(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .localPackage),
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
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
                    versions: ["1.0.0", "1.5.0", nil]
                ),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz", dependencies: ["Bar"]),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Baz", "Foo")
                result.check(targets: "Bar", "Baz", "Foo")
                result.check(testModules: "FooTests")
                result.check(dependencies: "Bar", target: "Baz")
                result.check(dependencies: "Baz", "Bar", target: "Foo")
                result.check(dependencies: "Foo", target: "FooTests")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "baz", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .local)
        }

        // Test that its not possible to edit or resolve this package.
        workspace.checkEdit(packageName: "Bar") { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("local dependency 'Bar' can't be edited"), behavior: .error)
            }
        }
        workspace.checkResolve(pkg: "Bar", roots: ["Foo"], version: "1.0.0") { diagnostics in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("local dependency 'Bar' can't be edited"), behavior: .error)
            }
        }
    }

    func testLocalDependencyTransitive() throws {
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
                        TestTarget(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Baz", requirement: .localPackage),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Foo")
                result.check(targets: "Foo")
            }
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("1.5.0 contains incompatible dependencies"), behavior: .error)
            }
        }
    }

    func testLocalDependencyWithPackageUpdate() throws {
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
                    products: [],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
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
                    versions: ["1.0.0", "1.5.0", nil]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }

        // Override with local package and run update.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bar", requirement: .localPackage),
        ]
        workspace.checkUpdate(roots: ["Foo"], deps: deps) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "bar", at: .local)
        }

        // Go back to the versioned state.
        workspace.checkUpdate(roots: ["Foo"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }
    }

    func testRevisionVersionSwitch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
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
                    versions: ["develop", "1.0.0"]
                ),
            ]
        )

        // Test that switching between revision and version requirement works
        // without running swift package update.

        var deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .branch("develop"))
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
        }

        deps = [
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .init(name: "Foo", requirement: .branch("develop"))
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
        }
    }

    func testLocalVersionSwitch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
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
                    versions: ["develop", "1.0.0", nil]
                ),
            ]
        )

        // Test that switching between local and version requirement works
        // without running swift package update.

        var deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .localPackage),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .local)
        }

        deps = [
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .init(name: "Foo", requirement: .localPackage),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .local)
        }
    }

    func testLocalLocalSwitch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
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
                    versions: [nil]
                ),
                TestPackage(
                    name: "Foo",
                    path: "Foo2",
                    targets: [
                        TestTarget(name: "Foo"),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        // Test that switching between two same local packages placed at
        // different locations works correctly.

        var deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .localPackage),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .local)
        }

        deps = [
            .init(name: "Foo2", requirement: .localPackage),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo2", at: .local)
        }
    }

	func testDependencySwitchWithSameIdentity() throws {
         let sandbox = AbsolutePath("/tmp/ws/")
         let fs = InMemoryFileSystem()

         let workspace = try TestWorkspace(
             sandbox: sandbox,
             fs: fs,
             roots: [
                 TestPackage(
                     name: "Root",
                     targets: [
                         TestTarget(name: "Root", dependencies: []),
                     ],
                     products: [],
                     dependencies: []
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
                     versions: [nil]
                 ),
                 TestPackage(
                     name: "Foo",
                     path: "Nested/Foo",
                     targets: [
                         TestTarget(name: "Foo"),
                     ],
                     products: [
                         TestProduct(name: "Foo", targets: ["Foo"]),
                     ],
                     versions: [nil]
                 ),
             ]
         )

         // Test that switching between two same local packages placed at
         // different locations works correctly.

         var deps: [TestWorkspace.PackageDependency] = [
             .init(name: "Foo", requirement: .localPackage),
         ]
         workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
             PackageGraphTester(graph) { result in
                 result.check(roots: "Root")
                 result.check(packages: "Foo", "Root")
             }
             XCTAssertNoDiagnostics(diagnostics)
         }
         workspace.checkManagedDependencies() { result in
             result.check(dependency: "foo", at: .local)
         }
         do {
             let ws = workspace.createWorkspace()
             XCTAssertNotNil(ws.managedDependencies[forURL: "/tmp/ws/pkgs/Foo"])
         }

         deps = [
             .init(name: "Nested/Foo", requirement: .localPackage),
         ]
         workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
             XCTAssertNoDiagnostics(diagnostics)
         }
         workspace.checkManagedDependencies() { result in
             result.check(dependency: "foo", at: .local)
         }
         do {
             let ws = workspace.createWorkspace()
             XCTAssertNotNil(ws.managedDependencies[forURL: "/tmp/ws/pkgs/Nested/Foo"])
         }
     }

    func testResolvedFileUpdate() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
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

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        workspace.checkPackageGraph(roots: ["Root"], deps: []) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved() { result in
            result.check(notPresent: "foo")
        }
    }

    func testPackageMirror() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Dep"]),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Dep",
                    targets: [
                        TestTarget(name: "Dep", dependencies: ["Bar"]),
                    ],
                    products: [
                        TestProduct(name: "Dep", targets: ["Dep"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
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
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.4.0"]
                ),
                TestPackage(
                    name: "Bam",
                    targets: [
                        TestTarget(name: "Bam"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bam"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Foo", "Dep", "Bar")
                result.check(targets: "Foo", "Dep", "Bar")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "Dep", at: .checkout(.version("1.5.0")))
            result.check(dependency: "Bar", at: .checkout(.version("1.5.0")))
            result.check(notPresent: "Baz")
        }

        try workspace.config.set(mirrorURL: workspace.packagesDir.appending(component: "Baz").pathString, forPackageURL: workspace.packagesDir.appending(component: "Bar").pathString)
        try workspace.config.set(mirrorURL: workspace.packagesDir.appending(component: "Baz").pathString, forPackageURL: workspace.packagesDir.appending(component: "Bam").pathString)

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bam", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { (graph, diagnostics) in
             PackageGraphTester(graph) { result in
                 result.check(roots: "Foo")
                 result.check(packages: "Foo", "Dep", "Baz")
                 result.check(targets: "Foo", "Dep", "Baz")
             }
             XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "Dep", at: .checkout(.version("1.5.0")))
            result.check(dependency: "Baz", at: .checkout(.version("1.4.0")))
            result.check(notPresent: "Bar")
            result.check(notPresent: "Bam")
        }
    }

	func testTransitiveDependencySwitchWithSameIdentity() throws {
         let sandbox = AbsolutePath("/tmp/ws/")
         let fs = InMemoryFileSystem()

         let workspace = try TestWorkspace(
             sandbox: sandbox,
             fs: fs,
             roots: [
                 TestPackage(
                     name: "Root",
                     targets: [
                         TestTarget(name: "Root", dependencies: ["Bar"]),
                     ],
                     products: [],
                     dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                     ]
                 ),
             ],
             packages: [
                 TestPackage(
                     name: "Bar",
                     targets: [
                         TestTarget(name: "Bar", dependencies: ["Foo"]),
                     ],
                     products: [
                         TestProduct(name: "Bar", targets: ["Bar"]),
                     ],
                     dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                     ],
                     versions: ["1.0.0"]
                 ),
                 TestPackage(
                     name: "Bar",
                     targets: [
                         TestTarget(name: "Bar", dependencies: ["Foo"]),
                     ],
                     products: [
                         TestProduct(name: "Bar", targets: ["Bar"]),
                     ],
                     dependencies: [
                        TestDependency(name: "Nested/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                     ],
                     versions: ["1.1.0"]
                 ),
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
                 TestPackage(
                     name: "Foo",
                     path: "Nested/Foo",
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

         // In this test, we get into a state where add an entry in the resolved
         // file for a transitive dependency whose URL is later changed to
         // something else, while keeping the same package identity.
         //
         // This is normally detected during pins validation before the
         // dependency resolution process even begins but if we're starting with
         // a clean slate, we don't even know about the correct urls of the
         // transitive dependencies. We will end up fetching the wrong
         // dependency as we prefetch the pins. If we get into this case, it
         // should kick off another dependency resolution operation which will
         // have enough information to remove the invalid pins of transitive
         // dependencies.

         var deps: [TestWorkspace.PackageDependency] = [
             .init(name: "Bar", requirement: .exact("1.0.0")),
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

         do {
             let ws = workspace.createWorkspace()
             XCTAssertNotNil(ws.managedDependencies[forURL: "/tmp/ws/pkgs/Foo"])
         }

         workspace.checkReset { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
         }

         deps = [
             .init(name: "Bar", requirement: .exact("1.1.0")),
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
            result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
         }

         do {
             let ws = workspace.createWorkspace()
             XCTAssertNotNil(ws.managedDependencies[forURL: "/tmp/ws/pkgs/Nested/Foo"])
         }
     }

    func testForceResolveToResolvedVersions() throws {
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
                    versions: ["1.0.0", "develop"]
                ),
            ]
        )

        // Load the initial graph.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bar", requirement: .revision("develop")),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }

        // Change pin of foo to something else.
        do {
            let ws = workspace.createWorkspace()
            let pinsStore = try ws.pinsStore.load()
            let fooPin = pinsStore.pins.first(where: { $0.packageRef.identity == "foo" })!

            let fooRepo = workspace.repoProvider.specifierMap[RepositorySpecifier(url: fooPin.packageRef.path)]!
            let revision = try fooRepo.resolveRevision(tag: "1.0.0")
            let newState = CheckoutState(revision: revision, version: "1.0.0")

            pinsStore.pin(packageRef: fooPin.packageRef, state: newState)
            try pinsStore.saveState()
        }

        // Check force resolve. This should produce an error because the resolved file is out-of-date.
        workspace.checkPackageGraph(roots: ["Root"], forceResolvedVersions: true) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: "cannot update Package.resolved file because automatic resolution is disabled", checkContains: true, behavior: .error)
            }
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }

        // A normal resolution.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // This force resolution should succeed.
        workspace.checkPackageGraph(roots: ["Root"], forceResolvedVersions: true) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testForceResolveToResolvedVersionsLocalPackage() throws {
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
                        TestDependency(name: "Foo", requirement: .localPackage),
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
                    versions: [nil]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Root"], forceResolvedVersions: true) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .local)
        }
    }

    func testSimpleAPI() throws {
        // This verifies that the simplest possible loading APIs are available for package clients.

        // This checkout of the SwiftPM package.
        let package = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory

        // Clients must locate the corresponding “swiftc” exectuable themselves for now.
        // (This just uses the same one used by all the other tests.)
        let swiftCompiler = Resources.default.swiftCompiler

        // From here the API should be simple and straightforward:
        let diagnostics = DiagnosticsEngine()
        let manifest = try ManifestLoader.loadManifest(
            packagePath: package, swiftCompiler: swiftCompiler)
        let loadedPackage = try PackageBuilder.loadPackage(
            packagePath: package, swiftCompiler: swiftCompiler, diagnostics: diagnostics)
        let graph = try Workspace.loadGraph(
            packagePath: package, swiftCompiler: swiftCompiler, diagnostics: diagnostics)

        XCTAssertEqual(manifest.name, "SwiftPM")
        XCTAssertEqual(loadedPackage.name, "SwiftPM")
        XCTAssert(graph.reachableProducts.contains(where: { $0.name == "SwiftPM" }))
    }

    func testRevisionDepOnLocal() throws {
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
                    dependencies: [
                        TestDependency(name: "Local", requirement: .localPackage),
                    ],
                    versions: ["develop"]
                ),
                TestPackage(
                    name: "Local",
                    targets: [
                        TestTarget(name: "Local"),
                    ],
                    products: [
                        TestProduct(name: "Local", targets: ["Local"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Root"]) { (_, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .equal("package 'foo' is required using a revision-based requirement and it depends on local package 'local', which is not supported"), behavior: .error)
            }
        }
    }

	func testRootPackagesOverrideBasenameMismatch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Baz",
                    path: "Overridden/bazzz-master",
                    targets: [
                        TestTarget(name: "Baz"),
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "Baz",
                    path: "bazzz",
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

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "bazzz", requirement: .exact("1.0.0")),
        ]

        workspace.checkPackageGraph(roots: ["Overridden/bazzz-master"], deps: deps) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(diagnostic: .equal("unable to override package 'Baz' because its basename 'bazzz' doesn't match directory name 'bazzz-master'"), behavior: .error)
            }
        }
    }
}

extension PackageGraph {
    /// Finds the package matching the given name.
    func lookup(_ name: String) -> PackageModel.ResolvedPackage {
        return packages.first{ $0.name == name }!
    }
}
