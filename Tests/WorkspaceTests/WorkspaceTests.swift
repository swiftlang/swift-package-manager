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
import SPMBuildCore
import Workspace

import SPMTestSupport

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
            .init(name: "Quix", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Quix"])),
            .init(name: "Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]
        workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Quix")
                result.check(targets: "Bar", "Baz", "Foo", "Quix")
                result.check(testModules: "BarTests")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
                result.checkTarget("BarTests") { result in result.check(dependencies: "Bar") }
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

        let stateFile = workspace.createWorkspace().state.path

        // Remove state file and check we can get the state back automatically.
        try fs.removeFileTree(stateFile)

        workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { _, _ in }
        XCTAssertTrue(fs.exists(stateFile))

        // Remove state file and check we get back to a clean state.
        try fs.removeFileTree(workspace.createWorkspace().state.path)
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
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
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
                        TestDependency(name: nil, path: "bazzz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
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
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
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
                productFilter: .specific(["Foo"]),
                location: ""
            ),
            .init(
                url: workspace.packagesDir.appending(component: "Bar").pathString + ".git",
                requirement: .upToNextMajor(from: "1.0.0"),
                productFilter: .specific(["Bar"]),
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
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
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
                    ],
                    toolsVersion: .v5
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
                result.checkTarget("Foo") { result in result.check(dependencies: "BazAB") }
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
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
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
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
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
                productFilter: .specific(["Bar"]),
                location: ""
            ),
            .init(
                url: "file://\(workspace.packagesDir.appending(component: "Foo").pathString)/",
                requirement: .upToNextMajor(from: "1.0.0"),
                productFilter: .specific(["Foo"]),
                location: ""
            ),
        ]

        workspace.checkPackageGraph(dependencies: dependencies) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo")
                result.check(targets: "Bar", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
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
                    products: [
                        TestProduct(name: "A", targets: ["A"]),
                    ],
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
                    products: [
                        TestProduct(name: "A", targets: ["A"]),
                    ],
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
                .init(name: "A", requirement: .exact("1.0.0"), products: .specific(["A"]))
            ]
            workspace.checkPackageGraph(deps: deps) { (graph, diagnostics) in
                PackageGraphTester(graph) { result in
                    result.check(packages: "A", "AA")
                    result.check(targets: "A", "AA")
                    result.checkTarget("A") { result in result.check(dependencies: "AA") }
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
                .init(name: "A", requirement: .exact("1.0.1"), products: .specific(["A"]))
            ]
            workspace.checkPackageGraph(deps: deps) { (graph, diagnostics) in
                PackageGraphTester(graph) { result in
                    result.checkTarget("A") { result in result.check(dependencies: "AA") }
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
                    products: [
                        TestProduct(name: "A", targets: ["A"])
                    ],
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
                    products: [
                        TestProduct(name: "B", targets: ["B"])
                    ],
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
            .init(name: "A", requirement: .exact("1.0.0"), products: .specific(["A"])),
            .init(name: "B", requirement: .exact("1.0.0"), products: .specific(["B"])),
        ]
        workspace.checkPackageGraph(deps: deps) { (_, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("version solving failed"), behavior: .error)
            }
        }
        // There should be no extra fetches.
        XCTAssertNoMatch(workspace.delegate.events, [.contains("updating repo")])
    }

    func testPrecomputeResolution_empty() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")
        let v2 = CheckoutState(revision: Revision(identifier: "hello"), version: "2.0.0")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: []
                ),
            ],
            packages: []
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: v2],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5)
                    .editedDependency(subpath: bPath, unmanagedPath: nil)
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result.isRequired, false)
        }
    }

    func testPrecomputeResolution_newPackages() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let v1 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.0")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: v1Requirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1)
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .newPackages(packages: [cRef])))
        }
    }

    func testPrecomputeResolution_requirementChange_versionToBranch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let branchRequirement: TestDependency.Requirement = .branch("master")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: branchRequirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: v1_5),
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
                package: cRef,
                state: .checkout(v1_5),
                requirement: .revision("master")
            )))
        }
    }

    func testPrecomputeResolution_requirementChange_versionToRevision() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let cPath = RelativePath("C")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")

        let testWorkspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "C", requirement: .revision("hello")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let cRepo = RepositorySpecifier(url: testWorkspace.urlForPackage(withName: "C"))
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try testWorkspace.set(
            pins: [cRef: v1_5],
            managedDependencies: [
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: v1_5),
            ]
        )

        try testWorkspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
                package: cRef,
                state: .checkout(v1_5),
                requirement: .revision("hello")
            )))
        }
    }


    func testPrecomputeResolution_requirementChange_localToBranch() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let masterRequirement: TestDependency.Requirement = .branch("master")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: masterRequirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency.local(packageRef: cRef)
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
                package: cRef,
                state: .local,
                requirement: .revision("master")
            )))
        }
    }

    func testPrecomputeResolution_requirementChange_versionToLocal() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let localRequirement: TestDependency.Requirement = .localPackage
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: localRequirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: v1_5),
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
                package: cRef,
                state: .checkout(v1_5),
                requirement: .unversioned
            )))
        }
    }

    func testPrecomputeResolution_requirementChange_branchToLocal() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let localRequirement: TestDependency.Requirement = .localPackage
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")
        let master = CheckoutState(revision: Revision(identifier: "master"), branch: "master")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: localRequirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: master],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: master),
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
                package: cRef,
                state: .checkout(master),
                requirement: .unversioned
            )))
        }
    }

    func testPrecomputeResolution_other() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let v2Requirement: TestDependency.Requirement = .range("2.0.0" ..< "3.0.0")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: v2Requirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: v1_5),
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result, .required(reason: .other))
        }
    }

    func testPrecomputeResolution_notRequired() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: TestDependency.Requirement = .range("1.0.0" ..< "2.0.0")
        let v2Requirement: TestDependency.Requirement = .range("2.0.0" ..< "3.0.0")
        let v1_5 = CheckoutState(revision: Revision(identifier: "hello"), version: "1.0.5")
        let v2 = CheckoutState(revision: Revision(identifier: "hello"), version: "2.0.0")

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "A",
                    targets: [TestTarget(name: "A")],
                    products: [],
                    dependencies: [
                        TestDependency(name: "B", requirement: v1Requirement),
                        TestDependency(name: "C", requirement: v2Requirement),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "B",
                    targets: [TestTarget(name: "B")],
                    products: [TestProduct(name: "B", targets: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                TestPackage(
                    name: "C",
                    targets: [TestTarget(name: "C")],
                    products: [TestProduct(name: "C", targets: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                )
            ]
        )

        let bRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "B"))
        let cRepo = RepositorySpecifier(url: workspace.urlForPackage(withName: "C"))
        let bRef = PackageReference(identity: "b", path: bRepo.url)
        let cRef = PackageReference(identity: "c", path: cRepo.url)

        try workspace.set(
            pins: [bRef: v1_5, cRef: v2],
            managedDependencies: [
                ManagedDependency(packageRef: bRef, subpath: bPath, checkoutState: v1_5),
                ManagedDependency(packageRef: cRef, subpath: cPath, checkoutState: v2),
            ]
        )

        try workspace.checkPrecomputeResolution { result in
            XCTAssertEqual(result.diagnostics.hasErrors, false)
            XCTAssertEqual(result.result.isRequired, false)
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
            .init(name: "Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
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
    
    func testUpdateDryRun() throws {
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
            ]
        )
        
        // Do an intial run, capping at Foo at 1.0.0.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]

        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Run update.
        workspace.checkUpdateDryRun(roots: ["Root"]) { changes, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            let expectedChange = (
                PackageReference(identity: "foo", path: "/tmp/ws/pkgs/Foo"),
                Workspace.PackageStateChange.updated(
                    .init(requirement: .version(Version("1.5.0")), products: .specific(["Foo"]))
                )
            )
            guard let change = changes?.first, changes?.count == 1 else {
                XCTFail()
                return
            }
            XCTAssertEqual(expectedChange, change)
        }
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testPartialUpdate() throws {
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
                        TestTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.5.0"]
                ),
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo"]),
                    ],
                    dependencies: [
                        TestDependency(name: "Bar", requirement: .upToNextMinor(from: "1.0.0")),
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
                    versions: ["1.0.0", "1.2.0"]
                ),
            ]
        )

        // Do an intial run, capping at Foo at 1.0.0.
        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run partial updates.
        //
        // Try to update just Bar. This shouldn't do anything because Bar can't be updated due
        // to Foo's requirements.
        workspace.checkUpdate(roots: ["Root"], packages: ["Bar"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Try to update just Foo. This should update Foo but not Bar.
        workspace.checkUpdate(roots: ["Root"], packages: ["Foo"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run full update.
        workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.2.0")))
        }
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
			XCTAssertEqual(manifests.allDependencyManifests().map({ $0.name }), ["Foo", "Baz", "Bam", "Bar"])
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
            .init(name: "Bar", requirement: .revision(barRevision), products: .specific(["Bar"]))
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
                result.check(diagnostic: .contains("Foo 1.3.0"), behavior: .error)
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
                result.check(diagnostic: .contains("dependency 'Foo' is missing; cloning again"), behavior: .warning)
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
                result.check(diagnostic: .contains("Foo[Foo] 1.0.0..<2.0.0"), behavior: .error)
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
                result.check(diagnostic: .equal("dependency 'Foo' was being edited but is missing; falling back to original checkout"), behavior: .warning)
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
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
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
        let editedDependency = ws.state.dependencies[forNameOrIdentity: "foo"]!
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
            .init(name: "Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
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

    func testPrefetchingWithOverridenPackage() throws {
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
                    versions: ["1.0.0"]
                ),
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
                    versions: [nil]
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

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Foo", requirement: .localPackage, products: .specific(["Foo"])),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (graph, diagnostics) in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Bar", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .local)
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
            toolsVersion: manifest.toolsVersion,
            packageKind: .root,
            dependencies: [PackageDependencyDescription(name: nil, url: manifest.dependencies[0].url, requirement: .exact("1.5.0"))],
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
            .init(name: "Bar", requirement: .exact("1.1.0"), products: .specific(["Bar"])),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("Bar[Bar] 1.1.0"), behavior: .error)
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
                result.checkTarget("Baz") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz", "Bar") }
                result.checkTarget("FooTests") { result in result.check(dependencies: "Foo") }
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
                result.check(diagnostic: .contains("Bar[Bar] {1.0.0..<1.5.0, 1.5.1..<2.0.0} is forbidden"), behavior: .error)
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
            .init(name: "Bar", requirement: .localPackage, products: .specific(["Bar"])),
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
            .init(name: "Foo", requirement: .branch("develop"), products: .specific(["Foo"]))
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
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .init(name: "Foo", requirement: .branch("develop"), products: .specific(["Foo"]))
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
            .init(name: "Foo", requirement: .localPackage, products: .specific(["Foo"])),
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
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies() { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .init(name: "Foo", requirement: .localPackage, products: .specific(["Foo"])),
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
            .init(name: "Foo", requirement: .localPackage, products: .specific(["Foo"])),
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
            .init(name: "Foo2", requirement: .localPackage, products: .specific(["Foo"])),
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
             .init(name: "Foo", requirement: .localPackage, products: .specific(["Foo"])),
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
            XCTAssertNotNil(ws.state.dependencies[forURL: "/tmp/ws/pkgs/Foo"])
         }

         deps = [
             .init(name: "Nested/Foo", requirement: .localPackage, products: .specific(["Foo"])),
         ]
         workspace.checkPackageGraph(roots: ["Root"], deps: deps) { (_, diagnostics) in
             XCTAssertNoDiagnostics(diagnostics)
         }
         workspace.checkManagedDependencies() { result in
             result.check(dependency: "foo", at: .local)
         }
         do {
             let ws = workspace.createWorkspace()
             XCTAssertNotNil(ws.state.dependencies[forURL: "/tmp/ws/pkgs/Nested/Foo"])
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
            .init(name: "Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
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
                    ],
                    toolsVersion: .v5
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
                        TestDependency(name: nil, path: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.5.0"],
                    toolsVersion: .v5
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

        try workspace.config.set(mirrorURL: workspace.packagesDir.appending(component: "Baz").pathString, forURL: workspace.packagesDir.appending(component: "Bar").pathString)
        try workspace.config.set(mirrorURL: workspace.packagesDir.appending(component: "Baz").pathString, forURL: workspace.packagesDir.appending(component: "Bam").pathString)

        let deps: [TestWorkspace.PackageDependency] = [
            .init(name: "Bam", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Bar"])),
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
                         TestTarget(name: "Bar", dependencies: ["Nested/Foo"]),
                     ],
                     products: [
                         TestProduct(name: "Bar", targets: ["Bar"]),
                     ],
                     dependencies: [
                        TestDependency(name: nil, path: "Nested/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                     ],
                     versions: ["1.1.0"],
                     toolsVersion: .v5
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
                         TestProduct(name: "Nested/Foo", targets: ["Foo"]),
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
             .init(name: "Bar", requirement: .exact("1.0.0"), products: .specific(["Bar"])),
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
             XCTAssertNotNil(ws.state.dependencies[forURL: "/tmp/ws/pkgs/Foo"])
         }

         workspace.checkReset { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
         }

         deps = [
             .init(name: "Bar", requirement: .exact("1.1.0"), products: .specific(["Bar"])),
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
             XCTAssertNotNil(ws.state.dependencies[forURL: "/tmp/ws/pkgs/Nested/Foo"])
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
            .init(name: "Bar", requirement: .revision("develop"), products: .specific(["Bar"])),
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
        guard Resources.havePD4Runtime else { return }

        // This verifies that the simplest possible loading APIs are available for package clients.

        // This checkout of the SwiftPM package.
        let package = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory

        // Clients must locate the corresponding “swiftc” exectuable themselves for now.
        // (This just uses the same one used by all the other tests.)
        let swiftCompiler = Resources.default.swiftCompiler

        // From here the API should be simple and straightforward:
        let diagnostics = DiagnosticsEngine()
        let manifest = try ManifestLoader.loadManifest(
            packagePath: package, swiftCompiler: swiftCompiler, packageKind: .local)
        let loadedPackage = try PackageBuilder.loadPackage(
            packagePath: package, swiftCompiler: swiftCompiler, xcTestMinimumDeploymentTargets: [:], diagnostics: diagnostics)
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
                        TestTarget(name: "Foo", dependencies: ["Local"]),
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
                result.check(diagnostic: .equal("package 'Foo' is required using a revision-based requirement and it depends on local package 'Local', which is not supported"), behavior: .error)
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
            .init(name: "bazzz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]

        workspace.checkPackageGraph(roots: ["Overridden/bazzz-master"], deps: deps) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(diagnostic: .equal("unable to override package 'Baz' because its basename 'bazzz' doesn't match directory name 'bazzz-master'"), behavior: .error)
            }
        }
    }

    func testUnsafeFlags() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar", settings: [.init(tool: .swift, name: .unsafeFlags, value: ["-F", "/tmp"])]),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
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
                        TestTarget(name: "Bar", settings: [.init(tool: .swift, name: .unsafeFlags, value: ["-F", "/tmp"])]),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz", dependencies: ["Bar"], settings: [.init(tool: .swift, name: .unsafeFlags, value: ["-F", "/tmp"])]),
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

        // We should only see errors about use of unsafe flag in the version-based dependency.
        workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { (graph, diagnostics) in
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
               result.checkUnordered(diagnostic: .equal("the target 'Baz' in product 'Baz' contains unsafe build flags"), behavior: .error)
               result.checkUnordered(diagnostic: .equal("the target 'Bar' in product 'Baz' contains unsafe build flags"), behavior: .error)
           }
        }
    }

    func testEditDependencyHadOverridableConstraints() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Root",
                    targets: [
                        TestTarget(name: "Root", dependencies: ["Foo", "Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .branch("master")),
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
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
                        TestDependency(name: "Bar", requirement: .branch("master")),
                    ],
                    versions: ["master", nil]
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                    ],
                    versions: ["master", "1.0.0", nil]
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
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("master")))
            result.check(dependency: "bar", at: .checkout(.branch("master")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
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

        // Add entry for the edited package.
        do {
            let fooKey = MockManifestLoader.Key(url: "/tmp/ws/pkgs/Foo")
            let editedFooKey = MockManifestLoader.Key(url: "/tmp/ws/edits/Foo")
            let manifest = workspace.manifestLoader.manifests[fooKey]!
            workspace.manifestLoader.manifests[editedFooKey] = manifest
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
        workspace.delegate.events.removeAll()

        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
            result.check(dependency: "bar", at: .checkout(.branch("master")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
    }

    func testTargetBasedDependency() throws {
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
                        TestTarget(name: "RootTests", dependencies: ["TestHelper1"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "TestHelper1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_2
                ),
            ],
            packages: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo1", dependencies: ["Foo2"]),
                        TestTarget(name: "Foo2", dependencies: ["Baz"]),
                        TestTarget(name: "FooTests", dependencies: ["TestHelper2"], type: .test)
                    ],
                    products: [
                        TestProduct(name: "Foo", targets: ["Foo1"]),
                    ],
                    dependencies: [
                        TestDependency(name: "TestHelper2", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                TestPackage(
                    name: "Bar",
                    targets: [
                        TestTarget(name: "Bar"),
                        TestTarget(name: "BarUnused", dependencies: ["Biz"]),
                        TestTarget(name: "BarTests", dependencies: ["TestHelper2"], type: .test),
                    ],
                    products: [
                        TestProduct(name: "Bar", targets: ["Bar"]),
                        TestProduct(name: "BarUnused", targets: ["BarUnused"])
                    ],
                    dependencies: [
                        TestDependency(name: "TestHelper2", requirement: .upToNextMajor(from: "1.0.0")),
                        TestDependency(name: "Biz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                TestPackage(
                    name: "Baz",
                    targets: [
                        TestTarget(name: "Baz")
                    ],
                    products: [
                        TestProduct(name: "Baz", targets: ["Baz"]),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                TestPackage(
                    name: "TestHelper1",
                    targets: [
                        TestTarget(name: "TestHelper1"),
                    ],
                    products: [
                        TestProduct(name: "TestHelper1", targets: ["TestHelper1"]),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
            ],
            toolsVersion: .v5_2,
            enablePubGrub: true
        )

        // Load the graph.
        workspace.checkPackageGraph(roots: ["Root"]) { (graph, diagnostics) in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.checkManagedDependencies { result in
            result.check(dependency: "Foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "Bar", at: .checkout(.version("1.0.0")))
            result.check(dependency: "Baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "TestHelper1", at: .checkout(.version("1.0.0")))
            result.check(notPresent: "Biz")
            result.check(notPresent: "TestHelper2")
        }
    }

    func testChecksumForBinaryArtifact() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["Foo"]),
                    ],
                    products: []
                ),
            ],
            packages: []
        )

        let ws = workspace.createWorkspace()

        // Checks the valid case.
        do {
            let binaryPath = sandbox.appending(component: "binary.zip")
            try fs.writeFileContents(binaryPath, bytes: ByteString([0xaa, 0xbb, 0xcc]))

            let diagnostics = DiagnosticsEngine()
            let checksum = ws.checksum(forBinaryArtifactAt: binaryPath, diagnostics: diagnostics)
            XCTAssertTrue(!diagnostics.hasErrors)
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map({ $0.contents }), [[0xaa, 0xbb, 0xcc]])
            XCTAssertEqual(checksum, "ccbbaa")
        }

        // Checks an unsupported extension.
        do {
            let unknownPath = sandbox.appending(component: "unknown")
            let diagnostics = DiagnosticsEngine()
            let checksum = ws.checksum(forBinaryArtifactAt: unknownPath, diagnostics: diagnostics)
            XCTAssertEqual(checksum, "")
            DiagnosticsEngineTester(diagnostics) { result in
                let expectedDiagnostic = "unexpected file type; supported extensions are: zip"
                result.check(diagnostic: .contains(expectedDiagnostic), behavior: .error)
            }
        }

        // Checks a supported extension that is not a file (does not exist).
        do {
            let unknownPath = sandbox.appending(component: "missingFile.zip")
            let diagnostics = DiagnosticsEngine()
            let checksum = ws.checksum(forBinaryArtifactAt: unknownPath, diagnostics: diagnostics)
            XCTAssertEqual(checksum, "")
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("file not found at path: /tmp/ws/missingFile.zip"),
                             behavior: .error)
            }
        }

        // Checks a supported extension that is a directory instead of a file.
        do {
            let unknownPath = sandbox.appending(component: "aDirectory.zip")
            try fs.createDirectory(unknownPath)

            let diagnostics = DiagnosticsEngine()
            let checksum = ws.checksum(forBinaryArtifactAt: unknownPath, diagnostics: diagnostics)
            XCTAssertEqual(checksum, "")
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("file not found at path: /tmp/ws/aDirectory.zip"),
                             behavior: .error)
            }
        }
    }

    func testArtifactDownload() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        var downloads: [MockDownloader.Download] = []

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloader: MockDownloader(fileSystem: fs, downloadFile: { url, destination, progress, completion in
                let contents: [UInt8]
                switch url.lastPathComponent {
                case "a1.zip": contents = [0xa1]
                case "a2.zip": contents = [0xa2]
                case "a3.zip": contents = [0xa3]
                case "b.zip": contents = [0xb0]
                default:
                    XCTFail("unexpected url")
                    contents = []
                }

                try! fs.writeFileContents(
                    destination,
                    bytes: ByteString(contents),
                    atomically: true
                )

                downloads.append(MockDownloader.Download(url: url, destinationPath: destination))
                completion(.success(()))
            }),
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: [
                            "B",
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            .product(name: "A3", package: "A"),
                            .product(name: "A4", package: "A"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "A", requirement: .exact("1.0.0")),
                        TestDependency(name: "B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"),
                        TestTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"),
                        TestTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a3.zip",
                            checksum: "a3"),
                        TestTarget(
                            name: "A4",
                            type: .binary,
                            path: "A4.xcframework"),
                    ],
                    products: [
                        TestProduct(name: "A1", targets: ["A1"]),
                        TestProduct(name: "A2", targets: ["A2"]),
                        TestProduct(name: "A3", targets: ["A3"]),
                        TestProduct(name: "A4", targets: ["A4"]),
                    ],
                    versions: ["1.0.0"]
                ),
                TestPackage(
                    name: "B",
                    targets: [
                        TestTarget(
                            name: "B",
                            type: .binary,
                            url: "https://b.com/b.zip",
                            checksum: "b0"),
                    ],
                    products: [
                        TestProduct(name: "B", targets: ["B"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let a4FrameworkPath = workspace.packagesDir.appending(components: "A", "A4.xcframework")
        try fs.createDirectory(a4FrameworkPath, recursive: true)

        try [("A", "A1.xcframework"), ("A", "A2.xcframework"), ("B", "B.xcframework")].forEach {
            let frameworkPath = workspace.artifactsDir.appending(components: $0.0, $0.1)
            try fs.createDirectory(frameworkPath, recursive: true)
        }

        // Pin A to 1.0.0, Checkout B to 1.0.0
        let aPath = workspace.urlForPackage(withName: "A")
        let aRef = PackageReference(identity: "a", path: aPath)
        let aRepo = workspace.repoProvider.specifierMap[RepositorySpecifier(url: aPath)]!
        let aRevision = try aRepo.resolveRevision(tag: "1.0.0")
        let aState = CheckoutState(revision: aRevision, version: "1.0.0")

        try workspace.set(
            pins: [aRef: aState],
            managedDependencies: [],
            managedArtifacts: [
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A1",
                    source: .remote(
                        url: "https://a.com/a1.zip",
                        checksum: "a1",
                        subpath: RelativePath("A/A1.xcframework"))),
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A3",
                    source: .remote(
                        url: "https://a.com/old/a3.zip",
                        checksum: "a3-old-checksum",
                        subpath: RelativePath("A/A3.xcframework"))),
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A4",
                    source: .remote(
                        url: "https://a.com/a4.zip",
                        checksum: "a4",
                        subpath: RelativePath("A/A4.xcframework"))),
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A5",
                    source: .remote(
                        url: "https://a.com/a5.zip",
                        checksum: "a5",
                        subpath: RelativePath("A/A5.xcframework"))),
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A6",
                    source: .local(path: "A6.xcframework")),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            XCTAssertEqual(diagnostics.diagnostics.map { $0.message.text }, ["downloaded archive of binary target 'A3' does not contain expected binary artifact 'A3.xcframework'"])
            XCTAssert(fs.isDirectory(AbsolutePath("/tmp/ws/.build/artifacts/B")))
            XCTAssert(!fs.exists(AbsolutePath("/tmp/ws/.build/artifacts/A/A3.xcframework")))
            XCTAssert(!fs.exists(AbsolutePath("/tmp/ws/.build/artifacts/A/A4.xcframework")))
            XCTAssert(!fs.exists(AbsolutePath("/tmp/ws/.build/artifacts/A/A5.xcframework")))
            XCTAssert(!fs.exists(AbsolutePath("/tmp/ws/.build/artifacts/Foo")))
            XCTAssertEqual(downloads.map({ $0.url }), [
                URL(string: "https://b.com/b.zip")!,
                URL(string: "https://a.com/a2.zip")!,
                URL(string: "https://a.com/a3.zip")!,
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes, [
                ByteString([0xb0]),
                ByteString([0xa2]),
                ByteString([0xa3]),
            ])
            XCTAssertEqual(workspace.archiver.extractions.map({ $0.destinationPath }), [
                AbsolutePath("/tmp/ws/.build/artifacts/B"),
                AbsolutePath("/tmp/ws/.build/artifacts/A"),
                AbsolutePath("/tmp/ws/.build/artifacts/A"),
            ])
            XCTAssertEqual(
                downloads.map({ $0.destinationPath }),
                workspace.archiver.extractions.map({ $0.archivePath })
            )
            PackageGraphTester(graph) { graph in
                if let a1 = graph.find(target: "A1")?.underlyingTarget as? BinaryTarget {
                    XCTAssertEqual(a1.artifactPath, AbsolutePath("/tmp/ws/.build/artifacts/A/A1.xcframework"))
                    XCTAssertEqual(a1.artifactSource, .remote(url: "https://a.com/a1.zip"))
                } else {
                    XCTFail("expected binary target")
                }

                if let a2 = graph.find(target: "A2")?.underlyingTarget as? BinaryTarget {
                    XCTAssertEqual(a2.artifactPath, AbsolutePath("/tmp/ws/.build/artifacts/A/A2.xcframework"))
                    XCTAssertEqual(a2.artifactSource, .remote(url: "https://a.com/a2.zip"))
                } else {
                    XCTFail("expected binary target")
                }

                if let a3 = graph.find(target: "A3")?.underlyingTarget as? BinaryTarget {
                    XCTAssertEqual(a3.artifactPath, AbsolutePath("/tmp/ws/.build/artifacts/A/A3.xcframework"))
                    XCTAssertEqual(a3.artifactSource, .remote(url: "https://a.com/a3.zip"))
                } else {
                    XCTFail("expected binary target")
                }

                if let a4 = graph.find(target: "A4")?.underlyingTarget as? BinaryTarget {
                    XCTAssertEqual(a4.artifactPath, a4FrameworkPath)
                    XCTAssertEqual(a4.artifactSource, .local)
                } else {
                    XCTFail("expected binary target")
                }

                if let b = graph.find(target: "B")?.underlyingTarget as? BinaryTarget {
                    XCTAssertEqual(b.artifactPath, AbsolutePath("/tmp/ws/.build/artifacts/B/B.xcframework"))
                    XCTAssertEqual(b.artifactSource, .remote(url: "https://b.com/b.zip"))
                } else {
                    XCTFail("expected binary target")
                }
            }
        }

        workspace.checkManagedArtifacts { result in
            result.check(packageName: "A", targetName: "A1", source: .remote(
                url: "https://a.com/a1.zip",
                checksum: "a1",
                subpath: RelativePath("A/A1.xcframework")))
            result.check(packageName: "A", targetName: "A2", source: .remote(
                url: "https://a.com/a2.zip",
                checksum: "a2",
                subpath: RelativePath("A/A2.xcframework")))
            result.check(packageName: "A", targetName: "A3", source: .remote(
                url: "https://a.com/a3.zip",
                checksum: "a3",
                subpath: RelativePath("A/A3.xcframework")))
            result.check(packageName: "A", targetName: "A4", source: .local(path: "A4.xcframework"))
            result.checkNotPresent(packageName: "A", targetName: "A5")
            result.check(packageName: "B", targetName: "B", source: .remote(
                url: "https://b.com/b.zip",
                checksum: "b0",
                subpath: RelativePath("B/B.xcframework")))
        }
    }

    func testArtifactDownloaderOrArchiverError() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloader: MockDownloader(fileSystem: fs, downloadFile: { url, destination, _, completion in
                switch url {
                case URL(string: "https://a.com/a1.zip")!:
                    completion(.failure(.serverError(statusCode: 500)))
                case URL(string: "https://a.com/a2.zip")!:
                    try! fs.writeFileContents(destination, bytes: ByteString([0xa2]))
                    completion(.success(()))
                case URL(string: "https://a.com/a3.zip")!:
                    try! fs.writeFileContents(destination, bytes: "different contents = different checksum")
                    completion(.success(()))
                default:
                    XCTFail("unexpected url")
                    completion(.success(()))
                }
            }),
            archiver: MockArchiver(extract: { _, destinationPath, completion in
                XCTAssertEqual(destinationPath, AbsolutePath("/tmp/ws/.build/artifacts/A"))
                completion(.failure(DummyError()))
            }),
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: [
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "A", requirement: .exact("1.0.0"))
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"),
                        TestTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"),
                        TestTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a3.zip",
                            checksum: "a3"),
                    ],
                    products: [
                        TestProduct(name: "A1", targets: ["A1"]),
                        TestProduct(name: "A2", targets: ["A2"]),
                        TestProduct(name: "A3", targets: ["A3"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { result, diagnostics in
            print(diagnostics.diagnostics)
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("artifact of binary target 'A1' failed download: invalid status code 500"), behavior: .error)
                result.check(diagnostic: .contains("artifact of binary target 'A2' failed extraction: dummy error"), behavior: .error)
                result.check(diagnostic: .contains("checksum of downloaded artifact of binary target 'A3' (6d75736b6365686320746e65726566666964203d2073746e65746e6f6320746e65726566666964) does not match checksum specified by the manifest (a3)"), behavior: .error)
            }
        }
    }

    func testArtifactChecksumChange() throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try TestWorkspace(
            sandbox: sandbox,
            fs: fs,
            roots: [
                TestPackage(
                    name: "Foo",
                    targets: [
                        TestTarget(name: "Foo", dependencies: ["A"]),
                    ],
                    products: [],
                    dependencies: [
                        TestDependency(name: "A", requirement: .exact("1.0.0"))
                    ]
                ),
            ],
            packages: [
                TestPackage(
                    name: "A",
                    targets: [
                        TestTarget(name: "A", type: .binary, url: "https://a.com/a.zip", checksum: "a"),
                    ],
                    products: [
                        TestProduct(name: "A", targets: ["A"])
                    ],
                    versions: ["0.9.0", "1.0.0"]
                ),
            ]
        )

        // Pin A to 1.0.0, Checkout A to 1.0.0
        let aPath = workspace.urlForPackage(withName: "A")
        let aRef = PackageReference(identity: "a", path: aPath)
        let aRepo = workspace.repoProvider.specifierMap[RepositorySpecifier(url: aPath)]!
        let aRevision = try aRepo.resolveRevision(tag: "1.0.0")
        let aState = CheckoutState(revision: aRevision, version: "1.0.0")
        let aDependency = ManagedDependency(packageRef: aRef, subpath: RelativePath("A"), checkoutState: aState)

        try workspace.set(
            pins: [aRef: aState],
            managedDependencies: [aDependency],
            managedArtifacts: [
                ManagedArtifact(
                    packageRef: aRef,
                    targetName: "A",
                    source: .remote(
                        url: "https://a.com/a.zip",
                        checksum: "old-checksum",
                        subpath: RelativePath("A/A.xcframework")))
            ]
        )

        workspace.checkPackageGraph(roots: ["Foo"]) { result, diagnostics in
            XCTAssertEqual(workspace.downloader.downloads, [])
            DiagnosticsEngineTester(diagnostics) { result in
                result.check(diagnostic: .contains("artifact of binary target 'A' has changed checksum"), behavior: .error)
            }
        }
    }

    func testAndroidCompilerFlags() throws {
      let target = try Triple("x86_64-unknown-linux-android")
      let sdk = AbsolutePath("/some/path/to/an/SDK.sdk")
      let toolchainPath = AbsolutePath("/some/path/to/a/toolchain.xctoolchain")

      let destination = Destination(
        target: target,
        sdk: sdk,
        binDir: toolchainPath.appending(components: "usr", "bin")
      )

      XCTAssertEqual(UserToolchain.deriveSwiftCFlags(triple: target, destination: destination), [
        // Needed when cross‐compiling for Android. 2020‐03‐01
        "-sdk", sdk.pathString
      ])
    }
}

extension PackageGraph {
    /// Finds the package matching the given name.
    func lookup(_ name: String) -> PackageModel.ResolvedPackage {
        return packages.first{ $0.name == name }!
    }
}

struct DummyError: LocalizedError, Equatable {
    public var errorDescription: String? { "dummy error" }
}
