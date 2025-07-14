//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import PackageFingerprint
@testable import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import PackageSigning
import SourceControl
import SPMBuildCore
@testable import Workspace
import XCTest

import struct TSCBasic.ByteString

import struct TSCUtility.Version

final class WorkspaceTests: XCTestCase {
    // override func setUpWithError() throws {
    //     let windowsPassingTests = [
    //         #selector(self.testBinaryArtifactsInvalidPath),
    //         #selector(self.testManifestLoaderDiagnostics),
    //         #selector(self.testInterpreterFlags),
    //         #selector(self.testManifestParseError),
    //         #selector(self.testSimpleAPI)
    //     ]
    //     let matches = windowsPassingTests.filter { $0 == self.invocation?.selector}
    //     if matches.count == 0 {
    //         try XCTSkipOnWindows()
    //     }
    // }

    func testBasics() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                        MockTarget(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Quix",
                    targets: [
                        MockTarget(name: "Quix"),
                    ],
                    products: [
                        MockProduct(name: "Quix", modules: ["Quix"]),
                    ],
                    versions: ["1.0.0", "1.2.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Quix", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Quix"])),
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Quix")
                result.check(modules: "Bar", "Baz", "Foo", "Quix")
                result.check(testModules: "BarTests")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
                result.checkTarget("BarTests") { result in result.check(dependencies: "Bar") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "quix", at: .checkout(.version("1.2.0")))
        }

        // Check the load-package callbacks.
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for root package: \(sandbox.appending(components: "roots", "Foo")) (identity: foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for root package: \(sandbox.appending(components: "roots", "Foo")) (identity: foo)"]
        )

        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for localSourceControl package: \(sandbox.appending(components: "pkgs", "Quix")) (identity: quix)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for localSourceControl package: \(sandbox.appending(components: "pkgs", "Quix")) (identity: quix)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for localSourceControl package: \(sandbox.appending(components: "pkgs", "Baz")) (identity: baz)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for localSourceControl package: \(sandbox.appending(components: "pkgs", "Baz")) (identity: baz)",
            ]
        )

        // Close and reopen workspace.
        try await workspace.closeWorkspace(resetState: false)
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "quix", at: .checkout(.version("1.2.0")))
        }

        let stateFile = try await workspace.getOrCreateWorkspace().state.storagePath

        // Remove state file and check we can get the state back automatically.
        try fs.removeFileTree(stateFile)

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { _, _ in }
        XCTAssertTrue(fs.exists(stateFile), "workspace state file should exist")

        // Remove state file and check we get back to a clean state.
        try await fs.removeFileTree(workspace.getOrCreateWorkspace().state.storagePath)
        try await workspace.closeWorkspace()
        await workspace.checkManagedDependencies { result in
            result.checkEmpty()
        }
    }

    func testInterpreterFlags() async throws {
        let fs = localFileSystem

        try testWithTemporaryDirectory { path in
            let foo = path.appending("foo")
            let packageManifest = foo.appending("Package.swift")

            func createWorkspace(_ content: String) throws -> Workspace {
                try fs.writeFileContents(packageManifest, string: content)

                let manifestLoader = try ManifestLoader(toolchain: UserToolchain.default)

                let sandbox = path.appending("ws")
                return try Workspace(
                    fileSystem: fs,
                    forRootPackage: sandbox,
                    customManifestLoader: manifestLoader,
                    delegate: MockWorkspaceDelegate()
                )
            }

            do {
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:4.0
                    import PackageDescription
                    let package = Package(
                        name: "foo"
                    )
                    """
                )

                XCTAssertMatch(try ws.interpreterFlags(for: packageManifest), [.equal("-swift-version"), .equal("4")])
            }

            do {
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:3.1
                    import PackageDescription
                    let package = Package(
                        name: "foo"
                    )
                    """
                )

                XCTAssertThrowsError(try ws.interpreterFlags(for: packageManifest))
            }

            do {
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:999.0
                    import PackageDescription
                    let package = Package(
                        name: "foo"
                    )
                    """
                )

                XCTAssertMatch(try ws.interpreterFlags(for: packageManifest), [.equal("-swift-version"), .equal("6")])
            }

            do {
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:5.9.2
                    import PackageDescription
                    let package = Package(
                        name: "foo"
                    )
                    """
                )

                XCTAssertMatch(try ws.interpreterFlags(for: packageManifest), [.equal("-swift-version"), .equal("5")])
            }

            do {
                // Invalid package manifest should still produce build settings.
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:5.9.2
                    import PackageDescription
                    """
                )

                XCTAssertMatch(try ws.interpreterFlags(for: packageManifest), [.equal("-package-description-version")])
            }

            do {
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:3.0
                    import PackageDescription
                    """
                )
                XCTAssertThrowsError(
                    try ws.interpreterFlags(for: packageManifest),
                    "error expected"
                ) { error in
                    XCTAssertEqual(
                        error as? StringError,
                        StringError("invalid tools version")
                    )
                }
            }

            do {
                // Invalid package manifest should still produce build settings.
                let ws = try createWorkspace(
                    """
                    // swift-tools-version:5.1
                    import PackageDescription
                    """
                )

                XCTAssertMatch(
                    try ws.interpreterFlags(for: packageManifest),
                    [.equal("-package-description-version"), .equal("5.1.0")]
                )
            }
        }
    }

    func testManifestParseError() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        try await testWithTemporaryDirectory { path in
            let pkgDir = path.appending("MyPkg")
            try localFileSystem.createDirectory(pkgDir)
            try localFileSystem.writeFileContents(
                pkgDir.appending("Package.swift"),
                string: """
                // swift-tools-version:4.0
                import PackageDescription
                #error("An error in MyPkg")
                let package = Package(
                    name: "MyPkg"
                )
                """
            )
            let workspace = try Workspace(
                fileSystem: localFileSystem,
                forRootPackage: pkgDir,
                customManifestLoader: ManifestLoader(toolchain: UserToolchain.default),
                delegate: MockWorkspaceDelegate()
            )
            let rootInput = PackageGraphRootInput(packages: [pkgDir], dependencies: [])
            let rootManifests = try await workspace.loadRootManifests(
                packages: rootInput.packages,
                observabilityScope: observability.topScope
            )

            XCTAssert(rootManifests.count == 0, "\(rootManifests)")

            testDiagnostics(observability.diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: .contains(
                        "\(pkgDir.appending("Package.swift")):3:8: error: An error in MyPkg"
                    ),
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .init(path: pkgDir))
                XCTAssertEqual(diagnostic?.metadata?.packageKind, .root(pkgDir))
            }
        }
    }

    func testMultipleRootPackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .exact("1.0.1")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.0.3", "1.0.5", "1.0.8"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Bar", "Foo")
                result.check(packages: "Bar", "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.1")))
        }
    }

    func testRootPackagesOverride() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "bazzz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: []
                ),
                MockPackage(
                    name: "Baz",
                    path: "Overridden/bazzz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    path: "bazzz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.0.3", "1.0.5", "1.0.8"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo", "Bar", "Overridden/bazzz"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "bar", "Foo", "bazzz")
                result.check(packages: "bar", "bazzz", "foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateRootPackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
                MockPackage(
                    name: "Foo",
                    path: "Nested/Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: []
        )

        await workspace.checkPackageGraphFailure(roots: ["Foo", "Nested/Foo"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("found multiple top-level packages named 'Foo'"), severity: .error)
            }
        }
    }

    /// Test that the explicit name given to a package is not used as its identity.
    func testExplicitPackageNameIsNotUsedAsPackageIdentity() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "FooPackage",
                    path: "foo-package",
                    targets: [
                        MockTarget(
                            name: "FooTarget",
                            dependencies: [.product(name: "BarProduct", package: "BarPackage")]
                        ),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "BarPackage",
                            path: "bar-package",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar-package",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "1.0.1"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "BarPackage",
                    path: "bar-package",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "1.0.1"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(
            roots: ["foo-package", "bar-package"],
            dependencies: [
                .localSourceControl(
                    path: "\(sandbox)/pkgs/bar-package",
                    requirement: .upToNextMajor(from: "1.0.0")
                ),
            ]
        ) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "foo-package", "bar-package")
                result.check(packages: "foo-package", "bar-package")
                result.checkTarget("FooTarget") { result in result.check(dependencies: "BarProduct") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    /// Test that the remote repository is not resolved when a root package with same name is already present.
    func testRootAsDependency1() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["BazAB"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "BazA"),
                        MockTarget(name: "BazB"),
                    ],
                    products: [
                        MockProduct(name: "BazAB", modules: ["BazA", "BazB"]),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo", "Baz"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Baz", "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "BazA", "BazB", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "BazAB") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(notPresent: "baz")
        }
        XCTAssertNoMatch(workspace.delegate.events, [.equal("fetching package: \(sandbox)/pkgs/Baz")])
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
    }

    /// Test that a root package can be used as a dependency when the remote version was resolved previously.
    func testRootAsDependency2() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "BazA"),
                        MockTarget(name: "BazB"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["BazA", "BazB"]),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Load only Foo right now so Baz is loaded from remote.
        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
        XCTAssertMatch(
            workspace.delegate.events,
            [.equal("fetching package: \(sandbox.appending(components: "pkgs", "Baz"))")]
        )
        XCTAssertMatch(workspace.delegate.events, [.equal("will resolve dependencies")])

        // Now load with Baz as a root package.
        workspace.delegate.clear()
        try await workspace.checkPackageGraph(roots: ["Foo", "Baz"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Baz", "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "BazA", "BazB", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(notPresent: "baz")
        }
        XCTAssertNoMatch(
            workspace.delegate.events,
            [.equal("fetching package: \(sandbox.appending(components: "pkgs", "Baz"))")]
        )
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
        XCTAssertMatch(
            workspace.delegate.events,
            [.equal("removing repo: \(sandbox.appending(components: "pkgs", "Baz"))")]
        )
    }

    func testGraphRootDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let dependencies: [PackageDependency] = [
            .localSourceControl(
                path: workspace.packagesDir.appending("Bar"),
                requirement: .upToNextMajor(from: "1.0.0"),
                productFilter: .specific(["Bar"])
            ),
            .localSourceControl(
                path: workspace.packagesDir.appending("Foo"),
                requirement: .upToNextMajor(from: "1.0.0"),
                productFilter: .specific(["Foo"])
            ),
        ]

        try await workspace.checkPackageGraph(dependencies: dependencies) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo")
                result.check(modules: "Bar", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testCanResolveWithIncompatiblePackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [
                        MockProduct(name: "A", modules: ["A"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./AA", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [
                        MockProduct(name: "A", modules: ["A"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./AA", requirement: .exact("2.0.0")),
                    ],
                    versions: ["1.0.1"]
                ),
                MockPackage(
                    name: "AA",
                    targets: [
                        MockTarget(name: "AA"),
                    ],
                    products: [
                        MockProduct(name: "AA", modules: ["AA"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        // Resolve when A = 1.0.0.
        do {
            let deps: [MockDependency] = [
                .sourceControl(path: "./A", requirement: .exact("1.0.0"), products: .specific(["A"])),
            ]
            try await workspace.checkPackageGraph(deps: deps) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(packages: "A", "AA")
                    result.check(modules: "A", "AA")
                    result.checkTarget("A") { result in result.check(dependencies: "AA") }
                }
                XCTAssertNoDiagnostics(diagnostics)
            }
            await workspace.checkManagedDependencies { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.0")))
                result.check(dependency: "aa", at: .checkout(.version("1.0.0")))
            }
            workspace.checkResolved { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.0")))
                result.check(dependency: "aa", at: .checkout(.version("1.0.0")))
            }
        }

        // Resolve when A = 1.0.1.
        do {
            let deps: [MockDependency] = [
                .sourceControl(path: "./A", requirement: .exact("1.0.1"), products: .specific(["A"])),
            ]
            try await workspace.checkPackageGraph(deps: deps) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.checkTarget("A") { result in result.check(dependencies: "AA") }
                }
                XCTAssertNoDiagnostics(diagnostics)
            }
            await workspace.checkManagedDependencies { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.1")))
                result.check(dependency: "aa", at: .checkout(.version("2.0.0")))
            }
            workspace.checkResolved { result in
                result.check(dependency: "a", at: .checkout(.version("1.0.1")))
                result.check(dependency: "aa", at: .checkout(.version("2.0.0")))
            }
            XCTAssertMatch(
                workspace.delegate.events,
                [.equal("updating repo: \(sandbox.appending(components: "pkgs", "A"))")]
            )
            XCTAssertMatch(
                workspace.delegate.events,
                [.equal("updating repo: \(sandbox.appending(components: "pkgs", "AA"))")]
            )
            XCTAssertEqual(workspace.delegate.events.filter { $0.hasPrefix("updating repo") }.count, 2)
        }
    }

    func testResolverCanHaveError() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(name: "A", dependencies: ["AA"]),
                    ],
                    products: [
                        MockProduct(name: "A", modules: ["A"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./AA", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(name: "B", dependencies: ["AA"]),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./AA", requirement: .exact("2.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "AA",
                    targets: [
                        MockTarget(name: "AA"),
                    ],
                    products: [
                        MockProduct(name: "AA", modules: ["AA"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./A", requirement: .exact("1.0.0"), products: .specific(["A"])),
            .sourceControl(path: "./B", requirement: .exact("1.0.0"), products: .specific(["B"])),
        ]
        try await workspace.checkPackageGraph(deps: deps) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("Dependencies could not be resolved"), severity: .error)
            }
        }
        // There should be no extra fetches.
        XCTAssertNoMatch(workspace.delegate.events, [.contains("updating repo")])
    }

    func testPrecomputeResolution_empty() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))
        let v2 = CheckoutState.version("2.0.0", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: []
                ),
            ],
            packages: []
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: v2],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath)
                    .edited(subpath: bPath, unmanagedPath: .none),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result.isRequired, false)
    }

    func testPrecomputeResolution_newPackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let v1 = CheckoutState.version("1.0.0", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .sourceControl(path: "./C", requirement: v1Requirement),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1, subpath: bPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .newPackages(packages: [cRef])))
    }

    func testPrecomputeResolution_requirementChange_versionToBranch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let branchRequirement: SourceControlRequirement = .branch("master")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .sourceControl(path: "./C", requirement: branchRequirement),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: v1_5, subpath: cPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
            package: cRef,
            state: .sourceControlCheckout(v1_5),
            requirement: .revision("master")
        )))
    }

    func testPrecomputeResolution_requirementChange_versionToRevision() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let cPath = RelativePath("C")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))

        let testWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./C", requirement: .revision("hello")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let cPackagePath = try testWorkspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await testWorkspace.set(
            resolvedPackages: [cRef: v1_5],
            managedDependencies: [
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: v1_5, subpath: cPath),
            ]
        )

        let result = try await testWorkspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
            package: cRef,
            state: .sourceControlCheckout(v1_5),
            requirement: .revision("hello")
        )))
    }

    func testPrecomputeResolution_requirementChange_localToBranch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let masterRequirement: SourceControlRequirement = .branch("master")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .sourceControl(path: "./C", requirement: masterRequirement),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .fileSystem(packageRef: cRef),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
            package: cRef,
            state: .fileSystem(cPackagePath),
            requirement: .revision("master")
        )))
    }

    func testPrecomputeResolution_requirementChange_versionToLocal() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .fileSystem(path: "./C"),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: v1_5, subpath: cPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
            package: cRef,
            state: .sourceControlCheckout(v1_5),
            requirement: .unversioned
        )))
    }

    func testPrecomputeResolution_requirementChange_branchToLocal() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))
        let master = CheckoutState.branch(name: "master", revision: Revision(identifier: "master"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .fileSystem(path: "./C"),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: master],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: master, subpath: cPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result, .required(reason: .packageRequirementChange(
            package: cRef,
            state: .sourceControlCheckout(master),
            requirement: .unversioned
        )))
    }

    func testPrecomputeResolution_other() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let v2Requirement: SourceControlRequirement = .range("2.0.0" ..< "3.0.0")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .sourceControl(path: "./C", requirement: v2Requirement),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: v1_5],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: v1_5, subpath: cPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(
            result.result,
            .required(reason: .other(
                "Dependencies could not be resolved because no versions of \'c\' match the requirement 2.0.0..<3.0.0 and root depends on \'c\' 2.0.0..<3.0.0."
            ))
        )
    }

    func testPrecomputeResolution_notRequired() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let bPath = RelativePath("B")
        let cPath = RelativePath("C")
        let v1Requirement: SourceControlRequirement = .range("1.0.0" ..< "2.0.0")
        let v2Requirement: SourceControlRequirement = .range("2.0.0" ..< "3.0.0")
        let v1_5 = CheckoutState.version("1.0.5", revision: Revision(identifier: "hello"))
        let v2 = CheckoutState.version("2.0.0", revision: Revision(identifier: "hello"))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "A",
                    targets: [MockTarget(name: "A")],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./B", requirement: v1Requirement),
                        .sourceControl(path: "./C", requirement: v2Requirement),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "B",
                    targets: [MockTarget(name: "B")],
                    products: [MockProduct(name: "B", modules: ["B"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [MockTarget(name: "C")],
                    products: [MockProduct(name: "C", modules: ["C"])],
                    versions: [nil, "1.0.0", "1.0.5", "2.0.0"]
                ),
            ]
        )

        let bPackagePath = try workspace.pathToPackage(withName: "B")
        let bRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: bPackagePath),
            path: bPackagePath
        )

        let cPackagePath = try workspace.pathToPackage(withName: "C")
        let cRef = PackageReference.localSourceControl(
            identity: PackageIdentity(path: cPackagePath),
            path: cPackagePath
        )

        try await workspace.set(
            resolvedPackages: [bRef: v1_5, cRef: v2],
            managedDependencies: [
                bPackagePath: .sourceControlCheckout(packageRef: bRef, state: v1_5, subpath: bPath),
                cPackagePath: .sourceControlCheckout(packageRef: cRef, state: v2, subpath: cPath),
            ]
        )

        let result = try await workspace.checkPrecomputeResolution()
        XCTAssertNoDiagnostics(result.diagnostics)
        XCTAssertEqual(result.result.isRequired, false)
    }

    func testLoadingRootManifests() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                .genericPackage(named: "A"),
                .genericPackage(named: "B"),
                .genericPackage(named: "C"),
            ],
            packages: []
        )

        try await workspace.checkPackageGraph(roots: ["A", "B", "C"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(packages: "A", "B", "C")
                result.check(modules: "A", "B", "C")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testUpdate() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        MockProduct(name: "Root", modules: ["Root"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.5.0"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Do an initial run, capping at Foo at 1.0.0.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run update.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
        }
        XCTAssertMatch(
            workspace.delegate.events,
            [.equal("removing repo: \(sandbox.appending(components: "pkgs", "Bar"))")]
        )

        // Run update again.
        // Ensure that up-to-date delegate is called when there is nothing to update.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("Everything is already up-to-date")])
    }

    func testUpdateDryRun() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        MockProduct(name: "Root", modules: ["Root"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.5.0"]
                ),
            ]
        )

        // Do an initial run, capping at Foo at 1.0.0.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Run update.
        try await workspace.checkUpdateDryRun(roots: ["Root"]) { changes, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
            let stateChange = Workspace.PackageStateChange
                .updated(.init(requirement: .version(Version("1.5.0")), products: .specific(["Foo"])))
            #else
            let stateChange = Workspace.PackageStateChange
                .updated(.init(requirement: .version(Version("1.5.0")), products: .everything))
            #endif

            let path = sandbox.appending(components: ["pkgs","Foo"])
            let expectedChange = (
                PackageReference.localSourceControl(identity: PackageIdentity(path: path), path: path),
                stateChange
            )
            guard let change = changes?.first, changes?.count == 1 else {
                XCTFail()
                return
            }
            XCTAssertEqual(expectedChange, change)
        }
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testPartialUpdate() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        MockProduct(name: "Root", modules: ["Root"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.5.0"]
                ),
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMinor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.2.0"]
                ),
            ]
        )

        // Do an initial run, capping at Foo at 1.0.0.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run partial updates.
        //
        // Try to update just Bar. This shouldn't do anything because Bar can't be updated due
        // to Foo's requirements.
        try await workspace.checkUpdate(roots: ["Root"], packages: ["Bar"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Try to update just Foo. This should update Foo but not Bar.
        try await workspace.checkUpdate(roots: ["Root"], packages: ["Foo"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Run full update.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.2.0")))
        }
    }

    func testCleanAndReset() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        MockProduct(name: "Root", modules: ["Root"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Load package graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Drop a build artifact in data directory.
        let ws = try workspace.getOrCreateWorkspace()
        let buildArtifact = ws.location.scratchDirectory.appending("test.o")
        try fs.writeFileContents(buildArtifact, bytes: "Hi")

        // Double checks.
        XCTAssert(fs.exists(buildArtifact))
        XCTAssert(fs.exists(ws.location.repositoriesCheckoutsDirectory))

        // Check clean.
        workspace.checkClean { diagnostics in
            // Only the build artifact should be removed.
            XCTAssertFalse(fs.exists(buildArtifact))
            XCTAssert(fs.exists(ws.location.repositoriesCheckoutsDirectory))
            XCTAssert(fs.exists(ws.location.scratchDirectory))

            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Add the build artifact again.
        try fs.writeFileContents(buildArtifact, bytes: "Hi")

        // Check reset.
        await workspace.checkReset { diagnostics in
            // Only the build artifact should be removed.
            XCTAssertFalse(fs.exists(buildArtifact))
            XCTAssertFalse(fs.exists(ws.location.repositoriesCheckoutsDirectory))
            XCTAssertFalse(fs.exists(ws.location.scratchDirectory))

            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.checkEmpty()
        }
    }

    func testDependencyManifestLoading() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs: InMemoryFileSystem = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root1",
                    targets: [
                        MockTarget(name: "Root1", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
                MockPackage(
                    name: "Root2",
                    targets: [
                        MockTarget(name: "Root2", dependencies: ["Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                .genericPackage(named: "Foo"),
                .genericPackage(named: "Bar"),
            ]
        )

        // Check that we can compute missing dependencies.
        try await workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { manifests, diagnostics in
            XCTAssertEqual(
                try! manifests.missingPackages.map(\.locationString).sorted(),
                [
                    sandbox.appending(components: "pkgs", "Bar").pathString,
                    sandbox.appending(components: "pkgs", "Foo").pathString,
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Load the graph with one root.
        try await workspace.checkPackageGraph(roots: ["Root1"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(packages: "Foo", "Root1")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Check that we compute the correct missing dependencies.
        try await workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { manifests, diagnostics in
            XCTAssertEqual(
                try! manifests.missingPackages.map(\.locationString).sorted(),
                [sandbox.appending(components: "pkgs", "Bar").pathString]
            )
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Load the graph with both roots.
        try await workspace.checkPackageGraph(roots: ["Root1", "Root2"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo", "Root1", "Root2")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Check that we compute the correct missing dependencies.
        try await workspace.loadDependencyManifests(roots: ["Root1", "Root2"]) { manifests, diagnostics in
            XCTAssertEqual(try! manifests.missingPackages.map(\.locationString).sorted(), [])
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDependencyManifestsOrder() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root1",
                    targets: [
                        MockTarget(name: "Root1", dependencies: ["Foo", "Bar", "Baz", "Bam"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                .genericPackage(named: "Bar"),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz", dependencies: ["Bam"]),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                .genericPackage(named: "Bam"),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root1"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        try await workspace.loadDependencyManifests(roots: ["Root1"]) { manifests, diagnostics in
            // Ensure that the order of the manifests is stable.
            XCTAssertEqual(
                manifests.allDependencyManifests.map(\.value.manifest.displayName),
                ["Bam", "Baz", "Bar", "Foo"]
            )
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testBranchAndRevision() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .branch("develop")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["develop"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["boo"]
                ),
            ]
        )

        // Get some revision identifier of Bar.
        let bar = RepositorySpecifier(path: "\(sandbox)/pkgs/Bar")
        let barRevision = workspace.repositoryProvider.specifierMap[bar]!.revisions[0]

        // We request Bar via revision.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Bar", requirement: .revision(barRevision), products: .specific(["Bar"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
            result.check(dependency: "bar", at: .checkout(.revision(barRevision)))
        }
    }

    func testResolve() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.3"]
                ),
            ]
        )

        // Load initial version.
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.3")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.3")))
        }

        // Resolve to an older version.
        await workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.0.0") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Check failure.
        await workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.3.0") { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("'foo' 1.3.0"), severity: .error)
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testDeletedCheckoutDirectory() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                .genericPackage(named: "Foo"),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        try fs.removeFileTree(workspace.getOrCreateWorkspace().location.repositoriesCheckoutsDirectory)

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("dependency 'foo' is missing; cloning again"), severity: .warning)
            }
        }
    }

    func testMinimumRequiredToolsVersionInDependencyResolution() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v3
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("'foo' 1.0.0..<2.0.0"), severity: .error)
            }
        }
    }

    func testToolsVersionRootPackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: []
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: []
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: []
                ),
            ],
            packages: [],
            toolsVersion: .v4
        )

        let roots = try workspace.rootPaths(for: ["Foo", "Bar", "Baz"]).map { $0.appending("Package.swift") }

        try fs.writeFileContents(roots[0], bytes: "// swift-tools-version:4.0")
        try fs.writeFileContents(roots[1], bytes: "// swift-tools-version:4.1.0")
        try fs.writeFileContents(roots[2], bytes: "// swift-tools-version:3.1")

        try await workspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkPackageGraphFailure(roots: ["Bar"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: .equal(
                        "package 'bar' is using Swift tools version 4.1.0 but the installed version is 4.0.0"
                    ),
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .plain("bar"))
            }
        }
        await workspace.checkPackageGraphFailure(roots: ["Foo", "Bar"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: .equal(
                        "package 'bar' is using Swift tools version 4.1.0 but the installed version is 4.0.0"
                    ),
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .plain("bar"))
            }
        }
        await workspace.checkPackageGraphFailure(roots: ["Baz"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: .equal(
                        "package 'baz' is using Swift tools version 3.1.0 which is no longer supported; consider using '// swift-tools-version:4.0' to specify the current tools version"
                    ),
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .plain("baz"))
            }
        }
    }


    func testEditDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: .plain("Root"))
                result.check(packages: .plain("bar"), .plain("foo"), .plain("Root"))
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Edit foo.
        let fooPath = try workspace.getOrCreateWorkspace().location.editsDirectory.appending("foo")
        await workspace.checkEdit(packageIdentity: "foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        XCTAssertTrue(fs.exists(fooPath))

        try await workspace.loadDependencyManifests(roots: ["Root"]) { manifests, diagnostics in
            let editedPackages = manifests.editedPackagesConstraints
            XCTAssertEqual(editedPackages.map(\.package.locationString), [fooPath.pathString])
            XCTAssertNoDiagnostics(diagnostics)
        }

        // Try re-editing foo.
        await workspace.checkEdit(packageIdentity: "foo") { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("dependency 'foo' already in edit mode"), severity: .error)
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Try editing bar at bad revision.
        await workspace.checkEdit(packageIdentity: "bar", revision: Revision(identifier: "dev")) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("revision 'dev' does not exist"), severity: .error)
            }
        }

        // Edit bar at a custom path and branch (ToT).
        let barPath = sandbox.appending(components: ["custom", "bar"])
        await workspace.checkEdit(packageIdentity: "bar", path: barPath, checkoutBranch: "dev") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .edited(barPath))
        }
        let barRepo = try await workspace.repositoryProvider.openWorkingCopy(at: barPath) as! InMemoryGitRepository
        XCTAssert(barRepo.revisions.contains("dev"))

        // Test unediting.
        await workspace.checkUnedit(packageIdentity: "foo", roots: ["Root"]) { diagnostics in
            XCTAssertFalse(fs.exists(fooPath))
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkUnedit(packageIdentity: "bar", roots: ["Root"]) { diagnostics in
            XCTAssert(fs.exists(barPath))
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testUnsafeFlagsInEditedPackage() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "Root",
                            dependencies: ["Foo"],
                            settings: [
                                .init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"])),
                            ]
                        ),
                    ],
                    products: [],
                    dependencies: [
                        // Must be a branch or revision for unsafe flags
                        .sourceControl(path: "./Foo", requirement: .revision("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            settings: [
                                .init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"])),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: .plain("Root"))
                result.check(packages: .plain("root"), .plain("Foo"))
            }
            XCTAssertNoDiagnostics(diagnostics)
        }

        let editedFooPath = sandbox.appending("Foo")
        await workspace.checkEdit(packageIdentity: "Foo", path: editedFooPath) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testMissingEditCanRestoreOriginalCheckout() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, _ in }

        // Edit foo.
        let fooPath = try workspace.getOrCreateWorkspace().location.editsDirectory.appending("Foo")
        await workspace.checkEdit(packageIdentity: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        XCTAssertTrue(fs.exists(fooPath))

        // Remove the edited package.
        try fs.removeFileTree(fooPath)
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .equal(
                        "dependency 'foo' was being edited but is missing; falling back to original checkout"
                    ),
                    severity: .warning
                )
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
    }

    func testCanUneditRemovedDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        let ws = try workspace.getOrCreateWorkspace()

        // Load the graph and edit foo.
        try await workspace.checkPackageGraph(deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(packages: "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkEdit(packageIdentity: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Remove foo.
        try await workspace.checkUpdate { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        XCTAssertMatch(
            workspace.delegate.events,
            [.equal("removing repo: \(sandbox.appending(components: "pkgs", "Foo"))")]
        )
        try await workspace.checkPackageGraph(deps: []) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        // There should still be an entry for `foo`, which we can unedit.
        let editedDependency = await ws.state.dependencies[.plain("foo")]
        if case .edited(let basedOn, _) = editedDependency?.state {
            XCTAssertNil(basedOn)
        } else {
            XCTFail("expected edited dependency")
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }

        // Unedit foo.
        await workspace.checkUnedit(packageIdentity: "Foo", roots: []) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.checkEmpty()
        }
    }

    func testDependencyResolutionWithEdit() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.0", "1.3.2"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .exact("1.0.0"), products: .specific(["Foo"])),
        ]
        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Edit bar.
        await workspace.checkEdit(packageIdentity: "Bar") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Add entry for the edited package.
        do {
            let barKey = MockManifestLoader.Key(url: sandbox.appending(components: "pkgs", "Bar").pathString)
            let editedBarKey = MockManifestLoader.Key(url: sandbox.appending(components: "edits", "Bar").pathString)
            let manifest = workspace.manifestLoader.manifests[barKey]!
            workspace.manifestLoader.manifests[editedBarKey] = manifest
        }

        // Now, resolve foo at a different version.
        await workspace.checkResolve(pkg: "Foo", roots: ["Root"], version: "1.2.0") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
            result.check(notPresent: "bar")
        }

        // Try package update.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(notPresent: "bar")
        }

        // Unedit should get the Package.resolved entry back.
        await workspace.checkUnedit(packageIdentity: "bar", roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testPrefetchingWithOverridenPackage() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: [nil]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        let deps: [MockDependency] = [
            .fileSystem(path: "./Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Bar", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    // Test that changing a particular dependency re-resolves the graph.
    func testChangeOneDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        // Initial resolution.
        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // Check that changing the requirement to 1.5.0 triggers re-resolution.
        let fooKey = MockManifestLoader.Key(url: sandbox.appending(components: "roots", "Foo").pathString)
        let manifest = workspace.manifestLoader.manifests[fooKey]!

        let dependency = manifest.dependencies[0]
        switch dependency {
        case .sourceControl(let settings):
            let updatedDependency: PackageDependency = .sourceControl(
                identity: settings.identity,
                nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly,
                location: settings.location,
                requirement: .exact("1.5.0"),
                productFilter: settings.productFilter,
                traits: []
            )

            workspace.manifestLoader.manifests[fooKey] = Manifest.createManifest(
                displayName: manifest.displayName,
                path: manifest.path,
                packageKind: manifest.packageKind,
                packageIdentity: manifest.packageIdentity,
                packageLocation: manifest.packageLocation,
                platforms: [],
                version: manifest.version,
                toolsVersion: manifest.toolsVersion,
                dependencies: [updatedDependency],
                targets: manifest.targets
            )
        default:
            XCTFail("unexpected dependency type")
        }

        try await workspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }
    }

    func testResolutionFailureWithEditedDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkEdit(packageIdentity: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        // Add entry for the edited package.
        do {
            let fooKey = MockManifestLoader.Key(url: sandbox.appending(components: "pkgs", "Foo").pathString)
            let editedFooKey = MockManifestLoader.Key(url: sandbox.appending(components: "edits", "Foo").pathString)
            let manifest = workspace.manifestLoader.manifests[fooKey]!
            workspace.manifestLoader.manifests[editedFooKey] = manifest
        }

    }
    func testResolutionFailureWithEditedDependencyWithABadGraph() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // Try resolving a bad graph.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Bar", requirement: .exact("1.1.0"), products: .specific(["Bar"])),
        ]

        // Replicate earlier workspace, include Bar dependency in target so that dependency resolution can include it.
        let badWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )
        try await badWorkspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("'bar' 1.1.0"), severity: .error)
            }
        }
    }

    func testStateModified() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: [
                            .product(name: "Foo", package: "foo"),
                            .product(name: "Bar", package: "bar"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "https://scm.com/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil, "1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"], deps: []) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo", "Root")
            }
        }

        let underlying = try workspace.getOrCreateWorkspace()
        let fooEditPath = sandbox.appending(components: ["edited", "foo"])

        // mimic external process putting a dependency into edit mode
        do {
            try fs.writeFileContents(fooEditPath.appending("Package.swift"), string: "// swift-tools-version: 5.6")

            let fooState = await underlying.state.dependencies[.plain("foo")]!
            let externalState = await WorkspaceState(
                fileSystem: fs,
                storageDirectory: underlying.state.storagePath.parentDirectory,
                initializationWarningHandler: { _ in }
            )
            await externalState.remove(identity: fooState.packageRef.identity)
            try await externalState.add(dependency: fooState.edited(subpath: "foo", unmanagedPath: fooEditPath))
            try await externalState.save()
        }

        // reload graph after "external" change
        try await workspace.checkPackageGraph(roots: ["Root"], deps: []) { graph, _ in
            PackageGraphTester(graph) { result in
                result.check(packages: "Bar", "Foo", "Root")
            }
        }

        do {
            let fooState = await underlying.state.dependencies[.plain("foo")]!
            guard case .edited(basedOn: _, unmanagedPath: fooEditPath) = fooState.state else {
                XCTFail(
                    "'\(fooState.packageRef.identity)' dependency expected to be in edit mode, but was: \(fooState)"
                )
                return
            }
        }
    }

    func testSkipUpdate() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [
                        MockProduct(name: "Root", modules: ["Root"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.5.0"]
                ),
            ],
            skipDependenciesUpdates: true
        )

        // Run update and remove all events.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        workspace.delegate.clear()

        // Check we don't have updating Foo event.
        try await workspace.checkUpdate(roots: ["Root"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertMatch(workspace.delegate.events, ["Everything is already up-to-date"])
        }
    }

    func testLocalDependencyBasics() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
                        MockTarget(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        .fileSystem(path: "./Bar"),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Baz", "Foo")
                result.check(modules: "Bar", "Baz", "Foo")
                result.check(testModules: "FooTests")
                result.checkTarget("Baz") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz", "Bar") }
                result.checkTarget("FooTests") { result in result.check(dependencies: "Foo") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bar", at: .local)
        }

        // Test that its not possible to edit or resolve this package.
        await workspace.checkEdit(packageIdentity: "Bar") { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("local dependency 'bar' can't be edited"), severity: .error)
            }
        }
        await workspace.checkResolve(pkg: "Bar", roots: ["Foo"], version: "1.0.0") { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("local dependency 'bar' can't be resolved"), severity: .error)
            }
        }
    }


    func testLocalDependencyTransitive() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                        MockTarget(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .fileSystem(path: "./Baz"),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Foo")
                result.check(modules: "Foo")
            }
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains("'bar' {1.0.0..<1.5.0, 1.5.1..<2.0.0} cannot be used"),
                    severity: .error
                )
            }
        }
    }

    func testLocalDependencyWithPackageUpdate() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0", nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }

        // Override with local package and run update.
        let deps: [MockDependency] = [
            .fileSystem(path: "./Bar", products: .specific(["Bar"])),
        ]
        try await workspace.checkUpdate(roots: ["Foo"], deps: deps) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .local)
        }

        // Go back to the versioned state.
        try await workspace.checkUpdate(roots: ["Foo"]) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .checkout(.version("1.5.0")))
        }
    }

    func testMissingLocalDependencyDiagnostic() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: []),
                    ],
                    products: [],
                    dependencies: [
                        .fileSystem(path: "Bar"),
                    ]
                ),
            ],
            packages: [
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Foo")
                result.check(modules: "Foo")
            }
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "the package at '\(sandbox.appending(components: "pkgs", "Bar"))' cannot be accessed (\(sandbox.appending(components: "pkgs", "Bar")) doesn't exist in file system"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testRevisionVersionSwitch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["develop", "1.0.0"]
                ),
            ]
        )

        // Test that switching between revision and version requirement works
        // without running swift package update.

        var deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .branch("develop"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
        }

        deps = [
            .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .sourceControl(path: "./Foo", requirement: .branch("develop"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("develop")))
        }
    }

    func testLocalVersionSwitch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["develop", "1.0.0", nil]
                ),
            ]
        )

        // Test that switching between local and version requirement works
        // without running swift package update.

        var deps: [MockDependency] = [
            .fileSystem(path: "./Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
        }

        deps = [
            .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        deps = [
            .fileSystem(path: "./Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
        }
    }

    func testLocalLocalSwitch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
                MockPackage(
                    name: "Foo",
                    path: "Foo2",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        // Test that switching between two same local packages placed at
        // different locations works correctly.

        var deps: [MockDependency] = [
            .fileSystem(path: "./Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
        }

        deps = [
            .fileSystem(path: "./Foo2", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo2", at: .local)
        }
    }

    // Test that switching between two same local packages placed at
    // different locations works correctly.
    func testDependencySwitchLocalWithSameIdentity() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
                MockPackage(
                    name: "Foo",
                    path: "Nested/Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        var deps: [MockDependency] = [
            .fileSystem(path: "./Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                sandbox.appending(components: "pkgs", "Foo").pathString
            )
        }

        deps = [
            .fileSystem(path: "./Nested/Foo", products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                sandbox.appending(components: "pkgs", "Nested", "Foo").pathString
            )
        }
    }

    // Test that switching between two remote packages at
    // different locations works correctly.
    func testDependencySwitchRemoteWithSameIdentity() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "https://scm.com/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Foo",
                    url: "https://scm.com/other/foo",
                    targets: [
                        MockTarget(name: "OtherFoo"),
                    ],
                    products: [
                        MockProduct(name: "OtherFoo", modules: ["OtherFoo"]),
                    ],
                    versions: ["1.1.0"]
                ),
            ]
        )

        var deps: [MockDependency] = [
            .sourceControl(url: "https://scm.com/org/foo", requirement: .exact("1.0.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Foo", "Root")
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        do {
            let ws = try workspace.getOrCreateWorkspace()
            let locationString = await ws.state.dependencies[.plain("foo")]?.packageRef.locationString
            XCTAssertEqual(locationString, "https://scm.com/org/foo")
        }

        deps = [
            .sourceControl(url: "https://scm.com/other/foo", requirement: .exact("1.1.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.1.0")))
        }
        do {
            let ws = try workspace.getOrCreateWorkspace()
            let locationString = await ws.state.dependencies[.plain("foo")]?.packageRef.locationString
            XCTAssertEqual(locationString, "https://scm.com/other/foo")
        }
    }

    func testResolvedFileUpdate() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Foo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }

        try await workspace.checkPackageGraph(roots: ["Root"], deps: []) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(notPresent: "foo")
        }
    }

    func testResolvedFileSchemeToolsVersion() async throws {
        for pair in [
            (ToolsVersion.v5_2, ToolsVersion.v5_2),
            (ToolsVersion.v5_6, ToolsVersion.v5_6),
            (ToolsVersion.v5_2, ToolsVersion.v5_6),
        ] {
            let fs = InMemoryFileSystem()
            let sandbox = AbsolutePath("/tmp/ws/")
            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    MockPackage(
                        name: "Root1",
                        targets: [
                            MockTarget(name: "Root1", dependencies: ["Foo"]),
                        ],
                        products: [],
                        dependencies: [
                            .sourceControl(
                                path: "./Foo",
                                requirement: .upToNextMajor(from: "1.0.0"),
                                products: .specific(["Foo"])
                            ),
                        ],
                        toolsVersion: pair.0
                    ),
                    MockPackage(
                        name: "Root2",
                        targets: [
                            MockTarget(name: "Root2", dependencies: []),
                        ],
                        products: [],
                        dependencies: [],
                        toolsVersion: pair.1
                    ),
                ],
                packages: [
                    MockPackage(
                        name: "Foo",
                        targets: [
                            MockTarget(name: "Foo"),
                        ],
                        products: [
                            MockProduct(name: "Foo", modules: ["Foo"]),
                        ],
                        versions: ["1.0.0"]
                    ),
                ]
            )

            try await workspace.checkPackageGraph(roots: ["Root1", "Root2"]) { _, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
            }
            await workspace.checkManagedDependencies { result in
                result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            }
            workspace.checkResolved { result in
                result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            }

            let minToolsVersion = [pair.0, pair.1].min()!
            let expectedSchemeVersion = minToolsVersion >= .v5_6 ? 2 : 1
            let actualSchemeVersion = try workspace.getOrCreateWorkspace().resolvedPackagesStore.load().schemeVersion()
            XCTAssertEqual(
                actualSchemeVersion,
                expectedSchemeVersion,
                "Actual scheme version (\(actualSchemeVersion)) is not as expected (\(expectedSchemeVersion)). Pair 0 (\(pair.0)) pair 1 (\(pair.1))"
            )
        }
    }

    func testResolvedFileStableCanonicalLocation() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: []),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "https://localhost/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { version in version } // stable revisions
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://localhost/org/bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { version in version } // stable revisions
                ),
                MockPackage(
                    name: "Foo",
                    url: "https://localhost/ORG/FOO", // diff: case
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { version in version } // stable revisions
                ),
                MockPackage(
                    name: "Foo",
                    url: "https://localhost/org/foo.git", // diff: .git extension
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { version in version } // stable revisions
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://localhost/org/bar.git", // diff: .git extension
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { version in version } // stable revisions
                ),
            ]
        )

        // case 1: initial loading

        var deps: [MockDependency] = [
            .sourceControl(url: "https://localhost/org/foo", requirement: .exact("1.0.0")),
            .sourceControl(url: "https://localhost/org/bar", requirement: .exact("1.0.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://localhost/org/foo"
            )
            XCTAssertEqual(
                result.managedDependencies[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://localhost/org/foo"
            )
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar"
            )
        }

        // case 2: set state with slightly different URLs that are canonically the same

        deps = [
            .sourceControl(url: "https://localhost/ORG/FOO", requirement: .exact("1.0.0")),
            .sourceControl(url: "https://localhost/org/bar.git", requirement: .exact("1.0.0")),
        ]

        // reset state, excluding the resolved file
        try await workspace.closeWorkspace(resetResolvedFile: false)
        XCTAssertTrue(fs.exists(sandbox.appending("Package.resolved")))
        // run update
        try await workspace.checkUpdate(roots: ["Root"], deps: deps) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            // URLs should reflect the actual dependencies
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://localhost/ORG/FOO"
            )
            XCTAssertEqual(
                result.managedDependencies[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar.git"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            // URLs should be stable since URLs are canonically the same and we kept the resolved file between the two
            // iterations
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://localhost/org/foo"
            )
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar"
            )
        }

        // case 2: set state with slightly different URLs that are canonically the same but request different versions

        deps = [
            .sourceControl(url: "https://localhost/ORG/FOO", requirement: .exact("1.1.0")),
            .sourceControl(url: "https://localhost/org/bar.git", requirement: .exact("1.1.0")),
        ]
        // reset state, excluding the resolved file
        try await workspace.closeWorkspace(resetResolvedFile: false)
        XCTAssertTrue(fs.exists(sandbox.appending("Package.resolved")))
        // run update
        try await workspace.checkUpdate(roots: ["Root"], deps: deps) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.1.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            // URLs should reflect the actual dependencies
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://localhost/ORG/FOO"
            )
            XCTAssertEqual(
                result.managedDependencies[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar.git"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.1.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            // URLs should reflect the actual dependencies since the new version forces rewrite of the resolved file
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://localhost/ORG/FOO"
            )
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar.git"
            )
        }

        // case 3: set state with slightly different URLs that are canonically the same but remove resolved file

        deps = [
            .sourceControl(url: "https://localhost/org/foo.git", requirement: .exact("1.0.0")),
            .sourceControl(url: "https://localhost/org/bar.git", requirement: .exact("1.0.0")),
        ]
        // reset state, including the resolved file
        await workspace.checkReset { XCTAssertNoDiagnostics($0) }
        try fs.removeFileTree(sandbox.appending("Package.resolved"))
        XCTAssertFalse(fs.exists(sandbox.appending("Package.resolved")))
        // run update
        try await workspace.checkUpdate(roots: ["Root"], deps: deps) { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            // URLs should reflect the actual dependencies
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://localhost/org/foo.git"
            )
            XCTAssertEqual(
                result.managedDependencies[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar.git"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            // URLs should reflect the actual dependencies since we deleted the resolved file
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://localhost/org/foo.git"
            )
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar.git"
            )
        }
    }

    func testPreferResolvedFileWhenExists() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "Root",
                            dependencies: [
                                .product(name: "Foo", package: "foo"),
                                .product(name: "Bar", package: "bar"),
                            ]
                        ),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://localhost/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://localhost/org/bar", requirement: .upToNextMinor(from: "1.1.0")),
                    ],
                    toolsVersion: .v5_10
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "https://localhost/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.1.0", "1.1.1", "1.2.0", "1.2.1", "1.3.0", "1.3.1"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://localhost/org/bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.1.0", "1.1.1", "1.2.0", "1.2.1", "1.3.0", "1.3.1"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://localhost/org/baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.0.1", "1.1.0", "1.1.1", "1.2.0", "1.2.1", "1.3.0", "1.3.1"]
                ),
            ]
        )

        // initial resolution without resolved file

        do {
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no errors
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "resolving and updating '\(Workspace.DefaultLocations.resolvedFileName)'",
                        severity: .debug
                    )
                }
            }

            workspace.checkResolved { result in
                result.check(dependency: "foo", at: .checkout(.version("1.3.1")))
                result.check(dependency: "bar", at: .checkout(.version("1.1.1")))
            }

            let resolvedPackagesStore = try workspace.getOrCreateWorkspace().resolvedPackagesStore.load()
            checkPinnedVersion(pin: resolvedPackagesStore.resolvedPackages["foo"]!, version: "1.3.1")
            checkPinnedVersion(pin: resolvedPackagesStore.resolvedPackages["bar"]!, version: "1.1.1")
        }

        do {
            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // run resolution again, now it should rely on the resolved file
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash matches manifest dependencies, attempting resolution based on this file",
                        severity: .debug
                    )
                }
            }
        }

        do {
            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // change the manifest
            let rootManifestPath = try workspace.pathToRoot(withName: "Root").appending(Manifest.filename)
            let manifestContent: String = try fs.readFileContents(rootManifestPath)
            try fs.writeFileContents(rootManifestPath, string: manifestContent.appending("\n"))

            // run resolution again, but change requirements
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash does do not match manifest dependencies. resolving and updating accordingly",
                        severity: .debug
                    )
                    result.checkUnordered(
                        diagnostic: "resolving and updating '\(Workspace.DefaultLocations.resolvedFileName)'",
                        severity: .debug
                    )
                }
            }

            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // restore original manifest
            try fs.writeFileContents(rootManifestPath, string: manifestContent)
            // run resolution again, now it should rely on the resolved file
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash matches manifest dependencies, attempting resolution based on this file",
                        severity: .debug
                    )
                }
            }
        }

        do {
            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // change the dependency requirements
            let changedDeps: [PackageDependency] = [
                .remoteSourceControl(url: "https://localhost/org/baz", requirement: .upToNextMinor(from: "1.0.0")),
            ]
            // run resolution again, but change requirements
            try await workspace.checkPackageGraph(roots: ["Root"], dependencies: changedDeps) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Baz", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash does do not match manifest dependencies. resolving and updating accordingly",
                        severity: .debug
                    )
                    result.checkUnordered(
                        diagnostic: "resolving and updating '\(Workspace.DefaultLocations.resolvedFileName)'",
                        severity: .debug
                    )
                }
            }

            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // run resolution again, but change requirements back to original
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash does do not match manifest dependencies. resolving and updating accordingly",
                        severity: .debug
                    )
                    result.checkUnordered(
                        diagnostic: "resolving and updating '\(Workspace.DefaultLocations.resolvedFileName)'",
                        severity: .debug
                    )
                }
            }

            // reset but keep resolved file
            try await workspace.closeWorkspace(resetResolvedFile: false)
            // run resolution again, now it should rely on the resolved file
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "'\(Workspace.DefaultLocations.resolvedFileName)' origin hash matches manifest dependencies, attempting resolution based on this file",
                        severity: .debug
                    )
                }
            }
        }

        do {
            // reset including removing resolved file
            try await workspace.closeWorkspace(resetResolvedFile: true)
            // run resolution again
            try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "Bar", "Foo", "Root")
                }
                // no error
                XCTAssertNoDiagnostics(diagnostics)
                // check resolution mode
                testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                    result.checkUnordered(
                        diagnostic: "resolving and updating '\(Workspace.DefaultLocations.resolvedFileName)'",
                        severity: .debug
                    )
                }
            }
        }
    }

    // util
    func checkPinnedVersion(pin: ResolvedPackagesStore.ResolvedPackage, version: Version) {
        switch pin.state {
        case .version(let pinnedVersion, _):
            XCTAssertEqual(pinnedVersion, version)
        default:
            XCTFail("non-version pin \(pin.state)")
        }
    }

    func testPackageSimpleMirrorPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(
            mirror: sandbox.appending(components: "pkgs", "BarMirror").pathString,
            for: sandbox.appending(components: "pkgs", "Bar").pathString
        )
        try mirrors.set(
            mirror: sandbox.appending(components: "pkgs", "BazMirror").pathString,
            for: sandbox.appending(components: "pkgs", "Baz").pathString
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Dep", package: "dep"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Dep",
                    targets: [
                        MockTarget(name: "Dep", dependencies: [
                            .product(name: "Bar", package: "bar"),
                            .product(name: "Baz", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Dep", modules: ["Dep"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.4.0"]
                ),
                MockPackage(
                    name: "BarMirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "BazMirror",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
            ],
            mirrors: mirrors
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "BarMirror", "BazMirror", "Foo", "Dep")
                result.check(modules: "Bar", "Baz", "Foo", "Dep")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "dep", at: .checkout(.version("1.4.0")))
            result.check(dependency: "barmirror", at: .checkout(.version("1.5.0")))
            result.check(dependency: "bazmirror", at: .checkout(.version("1.6.0")))
            result.check(notPresent: "bar")
            result.check(notPresent: "baz")
        }
    }

    func testPackageMirrorPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(
            mirror: sandbox.appending(components: "pkgs", "BarMirror").pathString,
            for: sandbox.appending(components: "pkgs", "Bar").pathString
        )
        try mirrors.set(
            mirror: sandbox.appending(components: "pkgs", "BarMirror").pathString,
            for: sandbox.appending(components: "pkgs", "Baz").pathString
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Dep", package: "dep"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Dep",
                    targets: [
                        MockTarget(name: "Dep", dependencies: [
                            .product(name: "Bar", package: "bar"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Dep", modules: ["Dep"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.4.0"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
                MockPackage(
                    name: "BarMirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            mirrors: mirrors
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Baz"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "BarMirror", "Foo", "Dep")
                result.check(modules: "Bar", "Foo", "Dep")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "dep", at: .checkout(.version("1.4.0")))
            result.check(dependency: "barmirror", at: .checkout(.version("1.5.0")))
            result.check(notPresent: "baz")
            result.check(notPresent: "bar")
        }
    }

    func testPackageSimpleMirrorURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "https://scm.com/org/bar-mirror", for: "https://scm.com/org/bar")
        try mirrors.set(mirror: "https://scm.com/org/baz-mirror", for: "https://scm.com/org/baz")

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Dep", package: "dep"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Dep",
                    url: "https://scm.com/org/dep",
                    targets: [
                        MockTarget(name: "Dep", dependencies: [
                            .product(name: "Bar", package: "bar"),
                            .product(name: "Baz", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Dep", modules: ["Dep"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://scm.com/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.4.0"]
                ),
                MockPackage(
                    name: "BarMirror",
                    url: "https://scm.com/org/bar-mirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "BazMirror",
                    url: "https://scm.com/org/baz-mirror",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
            ],
            mirrors: mirrors
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "bar-mirror", "baz-mirror", "foo", "dep")
                result.check(modules: "Bar", "Baz", "Foo", "Dep")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "dep", at: .checkout(.version("1.4.0")))
            result.check(dependency: "bar-mirror", at: .checkout(.version("1.5.0")))
            result.check(dependency: "baz-mirror", at: .checkout(.version("1.6.0")))
            result.check(notPresent: "bar")
            result.check(notPresent: "baz")
        }
    }

    func testPackageMirrorURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "https://scm.com/org/bar-mirror", for: "https://scm.com/org/bar")
        try mirrors.set(mirror: "https://scm.com/org/bar-mirror", for: "https://scm.com/org/baz")

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Dep", package: "dep"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Dep",
                    url: "https://scm.com/org/dep",
                    targets: [
                        MockTarget(name: "Dep", dependencies: [
                            .product(name: "Bar", package: "bar"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Dep", modules: ["Dep"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.4.0"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://scm.com/org/baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
                MockPackage(
                    name: "BarMirror",
                    url: "https://scm.com/org/bar-mirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            mirrors: mirrors
        )

        let deps: [MockDependency] = [
            .sourceControl(
                url: "https://scm.com/org/baz",
                requirement: .upToNextMajor(from: "1.0.0"),
                products: .specific(["Baz"])
            ),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "bar-mirror", "foo", "dep")
                result.check(modules: "Bar", "Foo", "Dep")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "dep", at: .checkout(.version("1.4.0")))
            result.check(dependency: "bar-mirror", at: .checkout(.version("1.5.0")))
            result.check(notPresent: "bar")
            result.check(notPresent: "baz")
        }
    }

    func testPackageMirrorURLToRegistry() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "org.bar-mirror", for: "https://scm.com/org/bar")

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Bar", package: "bar"),
                            .product(name: "Baz", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://scm.com/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "BarMirror",
                    identity: "org.bar-mirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://scm.com/org/baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
            ],
            mirrors: mirrors
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "org.bar-mirror", "baz", "foo")
                result.check(modules: "Bar", "Baz", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.bar-mirror", at: .registryDownload("1.5.0"))
            result.check(dependency: "baz", at: .checkout(.version("1.6.0")))
            result.check(notPresent: "bar")
        }
    }

    func testPackageMirrorRegistryToURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "https://scm.com/org/bar-mirror", for: "org.bar")

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Bar", package: "org.bar"),
                            .product(name: "Baz", package: "org.baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "BarMirror",
                    url: "https://scm.com/org/bar-mirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Baz",
                    identity: "org.baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.6.0"]
                ),
            ],
            mirrors: mirrors
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "bar-mirror", "org.baz", "foo")
                result.check(modules: "Bar", "Baz", "Foo")
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar-mirror", at: .checkout(.version("1.5.0")))
            result.check(dependency: "org.baz", at: .registryDownload("1.6.0"))
            result.check(notPresent: "org.bar")
        }
    }

    // In this test, we get into a state where an entry in the resolved
    // file for a transitive dependency whose URL is later changed to
    // something else, while keeping the same package identity.
    func testTransitiveDependencySwitchWithSameIdentity() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // Use the same revision (hash) for "foo" to indicate they are the same
        // package despite having different URLs.
        let fooRevision = String((UUID().uuidString + UUID().uuidString).prefix(40))

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "Root",
                            dependencies: [
                                .product(name: "Bar", package: "bar"),
                            ]
                        ),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [
                        MockTarget(
                            name: "Bar",
                            dependencies: [
                                .product(name: "Foo", package: "foo"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [
                        MockTarget(
                            name: "Bar",
                            dependencies: [
                                .product(name: "OtherFoo", package: "foo"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/other/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.1.0"],
                    toolsVersion: .v5
                ),
                MockPackage(
                    name: "Foo",
                    url: "https://scm.com/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in fooRevision }
                ),
                MockPackage(
                    name: "Foo",
                    url: "https://scm.com/other/foo",
                    targets: [
                        MockTarget(name: "OtherFoo"),
                    ],
                    products: [
                        MockProduct(name: "OtherFoo", modules: ["OtherFoo"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in fooRevision }
                ),
            ]
        )

        var deps: [MockDependency] = [
            .sourceControl(url: "https://scm.com/org/bar", requirement: .exact("1.0.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://scm.com/org/foo"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://scm.com/org/foo"
            )
        }

        // reset state
        await workspace.checkReset { XCTAssertNoDiagnostics($0) }

        deps = [
            .sourceControl(url: "https://scm.com/org/bar", requirement: .exact("1.1.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "Bar", "Foo", "Root")
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            XCTAssertEqual(
                result.managedDependencies[.plain("foo")]?.packageRef.locationString,
                "https://scm.com/other/foo"
            )
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            XCTAssertEqual(
                result.store.resolvedPackages[.plain("foo")]?.packageRef.locationString,
                "https://scm.com/other/foo"
            )
        }
    }

    func testForceResolveToResolvedVersions() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.0", "1.3.2"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "develop"]
                ),
            ]
        )

        // Load the initial graph.
        let deps: [MockDependency] = [
            .sourceControl(path: "./Bar", requirement: .revision("develop"), products: .specific(["Bar"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Root"], deps: deps) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.3.2")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }

        // Change pin of foo to something else.
        do {
            let ws = try workspace.getOrCreateWorkspace()
            let resolvedPackagesStore = try ws.resolvedPackagesStore.load()
            let fooPin = try XCTUnwrap(
                resolvedPackagesStore.resolvedPackages.values
                    .first(where: { $0.packageRef.identity.description == "foo" })
            )

            let fooRepo = try workspace.repositoryProvider
                .specifierMap[RepositorySpecifier(path: AbsolutePath(
                    validating: fooPin.packageRef
                        .locationString
                ))]!
            let revision = try fooRepo.resolveRevision(tag: "1.0.0")
            let newState = ResolvedPackagesStore.ResolutionState.version("1.0.0", revision: revision.identifier)

            resolvedPackagesStore.track(packageRef: fooPin.packageRef, state: newState)
            try resolvedPackagesStore.saveState(toolsVersion: ToolsVersion.current, originHash: .none)
        }

        // Check force resolve. This should produce an error because the resolved file is out-of-date.
        await workspace.checkPackageGraphFailure(roots: ["Root"], forceResolvedVersions: true) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "an out-of-date resolved file was detected at \(sandbox.appending(components: "Package.resolved")), which is not allowed when automatic dependency resolution is disabled; please make sure to update the file to reflect the changes in dependencies. Running resolver because requirements have changed.",
                    severity: .error
                )
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.branch("develop")))
        }

        // A normal resolution.
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }

        // This force resolution should succeed.
        try await workspace.checkPackageGraph(roots: ["Root"], forceResolvedVersions: true) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
        workspace.checkResolved { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testForceResolveToResolvedVersionsDuplicateLocalDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .fileSystem(path: "./Bar"),
                    ]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.0", "1.3.2"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root", "Bar"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        try await workspace.checkPackageGraph(roots: ["Root", "Bar"], forceResolvedVersions: true) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testForceResolveWithNoResolvedFile() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.2.0", "1.3.2"]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", "develop"]
                ),
            ]
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"], forceResolvedVersions: true) { diagnostics in
            // rdar://82544922 (`WorkspaceResolveReason` is non-deterministic)
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .prefix(
                        "a resolved file is required when automatic dependency resolution is disabled and should be placed at \(Workspace.DefaultLocations.resolvedVersionsFile(forRootPackage: sandbox)). Running resolver because the following dependencies were added:"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testForceResolveToResolvedVersionsLocalPackage() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .fileSystem(path: "./Foo"),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"], forceResolvedVersions: true) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
        }
    }

    func testForceResolveToResolvedVersionsLocalPackageInAdditionalDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root"),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(
            roots: ["Root"],
            dependencies: [.fileSystem(path: workspace.packagesDir.appending(component: "Foo"))],
            forceResolvedVersions: true
        ) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .local)
        }
    }

    // This verifies that the simplest possible loading APIs are available for package clients.
    func testSimpleAPI() async throws {
        try await testWithTemporaryDirectory { path in
            // Create a temporary package as a test case.
            let packagePath = path.appending("MyPkg")
            let initPackage = try InitPackage(
                name: packagePath.basename,
                packageType: .executable,
                destinationPath: packagePath,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Load the workspace.
            let observability = ObservabilitySystem.makeForTesting()
            let workspace = try Workspace(
                forRootPackage: packagePath,
                customHostToolchain: UserToolchain.default
            )

            // From here the API should be simple and straightforward:
            let manifest = try await workspace.loadRootManifest(
                at: packagePath,
                observabilityScope: observability.topScope
            )
            XCTAssertFalse(observability.hasWarningDiagnostics, observability.diagnostics.description)
            XCTAssertFalse(observability.hasErrorDiagnostics, observability.diagnostics.description)

            let package = try await workspace.loadRootPackage(
                at: packagePath,
                observabilityScope: observability.topScope
            )
            XCTAssertFalse(observability.hasWarningDiagnostics, observability.diagnostics.description)
            XCTAssertFalse(observability.hasErrorDiagnostics, observability.diagnostics.description)

            let graph = try await workspace.loadPackageGraph(
                rootPath: packagePath,
                observabilityScope: observability.topScope
            )
            XCTAssertFalse(observability.hasWarningDiagnostics, observability.diagnostics.description)
            XCTAssertFalse(observability.hasErrorDiagnostics, observability.diagnostics.description)

            XCTAssertEqual(manifest.displayName, "MyPkg")
            XCTAssertEqual(package.identity, .plain(manifest.displayName))
            XCTAssert(graph.reachableProducts.contains(where: { $0.name == "MyPkg" }))

            let reloadedPackage = try await workspace.loadPackage(
                with: package.identity,
                packageGraph: graph,
                observabilityScope: observability.topScope
            )

            XCTAssertEqual(package.identity, reloadedPackage.identity)
            XCTAssertEqual(package.manifest.displayName, reloadedPackage.manifest.displayName)
            XCTAssertEqual(package.products.map(\.name), reloadedPackage.products.map(\.name))
        }
    }

    func testRevisionDepOnLocal() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .branch("develop")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Local"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .fileSystem(path: "./Local"),
                    ],
                    versions: ["develop"]
                ),
                MockPackage(
                    name: "Local",
                    targets: [
                        MockTarget(name: "Local"),
                    ],
                    products: [
                        MockProduct(name: "Local", modules: ["Local"]),
                    ],
                    versions: [nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .equal(
                        "package 'foo' is required using a revision-based requirement and it depends on local package 'local', which is not supported"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testRootPackagesOverrideBasenameMismatch() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Baz",
                    path: "Overridden/bazzz-master",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    path: "bazzz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./bazzz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]

        try await workspace.checkPackageGraphFailure(roots: ["Overridden/bazzz-master"], deps: deps) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .equal(
                        "unable to override package 'Baz' because its identity 'bazzz' doesn't match override's identity (directory name) 'bazzz-master'"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testManagedDependenciesNotCaseSensitive() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "Bar", package: "bar"),
                            .product(name: "Baz", package: "baz"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://localhost/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://localhost/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    url: "https://localhost/org/bar",
                    targets: [
                        MockTarget(name: "Bar", dependencies: [
                            .product(name: "Baz", package: "Baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://localhost/org/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://localhost/org/baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://localhost/org/Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Bar", "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar", "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            testDiagnostics(diagnostics, minSeverity: .info) { result in
                result.checkUnordered(
                    diagnostic: "dependency on 'baz' is represented by similar locations ('https://localhost/org/baz' and 'https://localhost/org/Baz') which are treated as the same canonical location 'localhost/org/baz'.",
                    severity: .info
                )
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            XCTAssertEqual(
                result.managedDependencies[.plain("bar")]?.packageRef.locationString,
                "https://localhost/org/bar"
            )
            // root casing should win, so testing for lower case
            XCTAssertEqual(
                result.managedDependencies[.plain("baz")]?.packageRef.locationString,
                "https://localhost/org/baz"
            )
        }
    }

    func testUnsafeFlags() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar", settings: [.init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"]))]),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar", "Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .fileSystem(path: "./Bar"),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar", settings: [.init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"]))]),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(
                            name: "Baz",
                            dependencies: ["Bar"],
                            settings: [.init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"]))]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        // We should only see errors about use of unsafe flag in the version-based dependency.
        try await workspace.checkPackageGraph(roots: ["Foo", "Bar"]) { _, diagnostics in
            // We have disabled the check so there shouldn't be any errors.
            XCTAssert(diagnostics.filter({ $0.severity == .error }).isEmpty)
        }
    }

    func testUnsafeFlagsInFoundation() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Test",
                    targets: [
                        MockTarget(
                            name: "Test",
                            dependencies: [
                                .product(
                                    name: "Foundation",
                                    package: "swift-corelibs-foundation"
                                ),
                            ]
                        ),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "swift-corelibs-foundation", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "swift-corelibs-foundation",
                    targets: [
                        MockTarget(
                            name: "Foundation",
                            settings: [.init(tool: .swift, kind: .unsafeFlags(["-F", "/tmp"]))]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Foundation", modules: ["Foundation"]),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Test"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testEditDependencyHadOverridableConstraints() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Baz"]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .branch("master")),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .branch("master")),
                    ],
                    versions: ["master", nil]
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["master", "1.0.0", nil]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz", dependencies: ["Bar"]),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", nil]
                ),
            ]
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("master")))
            result.check(dependency: "bar", at: .checkout(.branch("master")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }

        // Edit foo.
        let fooPath = try workspace.getOrCreateWorkspace().location.editsDirectory.appending("Foo")
        await workspace.checkEdit(packageIdentity: "Foo") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
        }
        XCTAssertTrue(fs.exists(fooPath))

        // Add entry for the edited package.
        do {
            let fooKey = MockManifestLoader.Key(url: sandbox.appending(components: "pkgs", "Foo").pathString)
            let editedFooKey = MockManifestLoader.Key(url: sandbox.appending(components: "edits", "Foo").pathString)
            let manifest = workspace.manifestLoader.manifests[fooKey]!
            workspace.manifestLoader.manifests[editedFooKey] = manifest
        }
        XCTAssertMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
        workspace.delegate.clear()

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .edited(nil))
            result.check(dependency: "bar", at: .checkout(.branch("master")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
        XCTAssertNoMatch(workspace.delegate.events, [.equal("will resolve dependencies")])
    }

    func testTargetBasedDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let barProducts: [MockProduct]
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        barProducts = [
            MockProduct(name: "Bar", modules: ["Bar"]),
            MockProduct(name: "BarUnused", modules: ["BarUnused"]),
        ]
        #else
        // Whether a product is being used does not affect dependency resolution in this case, so we omit the unused
        // product.
        barProducts = [MockProduct(name: "Bar", modules: ["Bar"])]
        #endif

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Root", dependencies: ["Foo", "Bar"]),
                        MockTarget(name: "RootTests", dependencies: ["TestHelper1"], type: .test),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./TestHelper1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_2
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo1", dependencies: ["Foo2"]),
                        MockTarget(name: "Foo2", dependencies: ["Baz"]),
                        MockTarget(name: "FooTests", dependencies: ["TestHelper2"], type: .test),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo1"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./TestHelper2", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                MockPackage(
                    name: "Bar",
                    targets: [
                        MockTarget(name: "Bar"),
                        MockTarget(name: "BarUnused", dependencies: ["Biz"]),
                        MockTarget(name: "BarTests", dependencies: ["TestHelper2"], type: .test),
                    ],
                    products: barProducts,
                    dependencies: [
                        .sourceControl(path: "./TestHelper2", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Biz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
                MockPackage(
                    name: "TestHelper1",
                    targets: [
                        MockTarget(name: "TestHelper1"),
                    ],
                    products: [
                        MockProduct(name: "TestHelper1", modules: ["TestHelper1"]),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5_2
                ),
            ],
            toolsVersion: .v5_2
        )

        // Load the graph.
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.0.0")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "testhelper1", at: .checkout(.version("1.0.0")))
            result.check(notPresent: "biz")
            result.check(notPresent: "testhelper2")
        }
    }

    func testLocalArchivedArtifactExtractionHappyPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // create dummy xcframework and artifactbundle directories from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "A1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                case "A2.zip":
                    try createDummyArtifactBundle(fileSystem: fs, path: destinationPath, name: "A2")
                case "B.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "B")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            .product(name: "B", package: "B"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.zip"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "ArtifactBundles/A2.zip"
                        ),
                    ],
                    products: [
                        MockProduct(name: "A1", modules: ["A1"]),
                        MockProduct(name: "A2", modules: ["A2"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(
                            name: "B",
                            type: .binary,
                            path: "XCFrameworks/B.zip"
                        ),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(archiver: archiver)
        )

        // Create dummy xcframework/artifactbundle zip files
        let aPath = workspace.packagesDir.appending(components: "A")

        let aFrameworksPath = aPath.appending("XCFrameworks")
        let a1FrameworkArchivePath = aFrameworksPath.appending("A1.zip")
        try fs.createDirectory(aFrameworksPath, recursive: true)
        try fs.writeFileContents(a1FrameworkArchivePath, bytes: ByteString([0xA1]))

        let aArtifactBundlesPath = aPath.appending("ArtifactBundles")
        let a2ArtifactBundleArchivePath = aArtifactBundlesPath.appending("A2.zip")
        try fs.createDirectory(aArtifactBundlesPath, recursive: true)
        try fs.writeFileContents(a2ArtifactBundleArchivePath, bytes: ByteString([0xA2]))

        let bPath = workspace.packagesDir.appending(components: "B")

        let bFrameworksPath = bPath.appending("XCFrameworks")
        let bFrameworkArchivePath = bFrameworksPath.appending("B.zip")
        try fs.createDirectory(bFrameworksPath, recursive: true)
        try fs.writeFileContents(bFrameworkArchivePath, bytes: ByteString([0xB0]))

        // Ensure that the artifacts do not exist yet
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "A", "A1.xcframework"])))
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "A", "A2", "artifactbundle"])))
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "B", "B", "xcframework"])))

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)

            // Ensure that the artifacts have been properly extracted
            XCTAssertTrue(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "a", "A1", "A1.xcframework"])))
            XCTAssertTrue(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "a", "A2", "A2.artifactbundle"])))
            XCTAssertTrue(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "b", "B", "B.xcframework"])))

            // Ensure that the original archives have been untouched
            XCTAssertTrue(fs.exists(a1FrameworkArchivePath))
            XCTAssertTrue(fs.exists(a2ArtifactBundleArchivePath))
            XCTAssertTrue(fs.exists(bFrameworkArchivePath))

            // Ensure that the temporary folders have been properly created
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A1"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A2"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "b", "B"]),
            ])

            // Ensure that the temporary directories have been removed
            XCTAssertTrue(try! fs.getDirectoryContents(sandbox.appending(components: [".build", "artifacts", "extract", "a", "A1"])).isEmpty)
            XCTAssertTrue(try! fs.getDirectoryContents(sandbox.appending(components: [".build", "artifacts", "extract", "a", "A2"])).isEmpty)
            XCTAssertTrue(try! fs.getDirectoryContents(sandbox.appending(components: [".build", "artifacts", "extract", "b", "B"])).isEmpty)
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A1",
                source: .local(checksum: "a1"),
                path: workspace.artifactsDir.appending(components: "a", "A1", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A2",
                source: .local(checksum: "a2"),
                path: workspace.artifactsDir.appending(components: "a", "A2", "A2.artifactbundle")
            )
            result.check(
                packageIdentity: .plain("b"),
                targetName: "B",
                source: .local(checksum: "b0"),
                path: workspace.artifactsDir.appending(components: "b", "B", "B.xcframework")
            )
        }
    }

    // There are 6 possible transition permutations of the artifact source set
    // {local, local-archived, and remote}, namely:
    //
    // (remote         -> local)
    // (local          -> remote)
    // (local          -> local-archived)
    // (local-archived -> local)
    // (remote         -> local-archived)
    // (local-archived -> remote)
    //
    // This test covers the last 4 permutations where the `local-archived` source is involved.
    // It ensures that all the appropriate clean-up operations are executed, and the workspace
    // contains the correct set of managed artifacts after the transition.
    func testLocalArchivedArtifactSourceTransitionPermutations() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let a1FrameworkName = "A1.xcframework"
        let a2FrameworkName = "A2.xcframework"
        let a3FrameworkName = "A3.xcframework"
        let a4FrameworkName = "A4.xcframework"
        let a5FrameworkName = "A5.xcframework"

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a4.zip":
                contents = [0xA4]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            return .okay()
        }

        // create a dummy xcframework directory (with a marker subdirectory) from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                // var subdirectoryName: String?
                switch archivePath.basename {
                case "A1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                case "A2.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A2")
                case "A3.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A3")
                    try fs.createDirectory(
                        destinationPath.appending(components: [a3FrameworkName, "local-archived"]),
                        recursive: false
                    )
                case "a4.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A4")
                    try fs.createDirectory(
                        destinationPath.appending(components: [a4FrameworkName, "remote"]),
                        recursive: false
                    )
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }

                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            .product(name: "A3", package: "A"),
                            .product(name: "A4", package: "A"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.zip"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "XCFrameworks/\(a2FrameworkName)"
                        ),
                        MockTarget(
                            name: "A3",
                            type: .binary,
                            path: "XCFrameworks/A3.zip"
                        ),
                        MockTarget(
                            name: "A4",
                            type: .binary,
                            url: "https://a.com/a4.zip",
                            checksum: "a4"
                        ),
                    ],
                    products: [
                        MockProduct(name: "A1", modules: ["A1"]),
                        MockProduct(name: "A2", modules: ["A2"]),
                        MockProduct(name: "A3", modules: ["A3"]),
                        MockProduct(name: "A4", modules: ["A4"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        // Create dummy xcframework directories and zip files
        let aFrameworksPath = workspace.packagesDir.appending(components: "A", "XCFrameworks")
        try fs.createDirectory(aFrameworksPath, recursive: true)

        let a1FrameworkPath = aFrameworksPath.appending(component: a1FrameworkName)
        let a1FrameworkArchivePath = aFrameworksPath.appending("A1.zip")
        try fs.createDirectory(a1FrameworkPath, recursive: true)
        try fs.writeFileContents(a1FrameworkArchivePath, bytes: ByteString([0xA1]))

        let a2FrameworkPath = aFrameworksPath.appending(component: a2FrameworkName)
        let a2FrameworkArchivePath = aFrameworksPath.appending("A2.zip")
        try createDummyXCFramework(fileSystem: fs, path: a2FrameworkPath.parentDirectory, name: "A2")
        try fs.writeFileContents(a2FrameworkArchivePath, bytes: ByteString([0xA2]))

        let a3FrameworkArchivePath = aFrameworksPath.appending("A3.zip")
        try fs.writeFileContents(a3FrameworkArchivePath, bytes: ByteString([0xA3]))

        let a4FrameworkArchivePath = aFrameworksPath.appending("A4.zip")
        try fs.writeFileContents(a4FrameworkArchivePath, bytes: ByteString([0xA4]))

        // Pin A to 1.0.0, Checkout B to 1.0.0
        let aPath = try workspace.pathToPackage(withName: "A")
        let aRef = PackageReference.localSourceControl(identity: PackageIdentity(path: aPath), path: aPath)
        let aRepo = workspace.repositoryProvider.specifierMap[RepositorySpecifier(path: aPath)]!
        let aRevision = try aRepo.resolveRevision(tag: "1.0.0")
        let aState = CheckoutState.version("1.0.0", revision: aRevision)

        // Set an initial workspace state
        try await workspace.set(
            resolvedPackages: [aRef: aState],
            managedArtifacts: [
                .init(
                    packageRef: aRef,
                    targetName: "A1",
                    source: .local(),
                    path: a1FrameworkPath,
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A2",
                    source: .local(checksum: "a2"),
                    path: workspace.artifactsDir.appending(components: "A", a2FrameworkName),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A3",
                    source: .remote(url: "https://a.com/a3.zip", checksum: "a3"),
                    path: workspace.artifactsDir.appending(components: "A", a3FrameworkName),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A4",
                    source: .local(checksum: "a4"),
                    path: workspace.artifactsDir.appending(components: "A", a4FrameworkName),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A5",
                    source: .local(checksum: "a5"),
                    path: workspace.artifactsDir.appending(components: "A", a5FrameworkName),
                    kind: .xcframework
                ),
            ]
        )

        // Create marker folders to later check that the frameworks' content is properly overwritten
        try fs.createDirectory(
            workspace.artifactsDir.appending(components: "A", "A3", a3FrameworkName, "remote"),
            recursive: true
        )
        try fs.createDirectory(
            workspace.artifactsDir.appending(components: "A", "A4", a4FrameworkName, "local-archived"),
            recursive: true
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)

            // Ensure that the original archives have been untouched
            XCTAssertTrue(fs.exists(a1FrameworkArchivePath))
            XCTAssertTrue(fs.exists(a2FrameworkArchivePath))
            XCTAssertTrue(fs.exists(a3FrameworkArchivePath))
            XCTAssertTrue(fs.exists(a4FrameworkArchivePath))

            // Ensure that the new artifacts have been properly extracted
            XCTAssertTrue(try fs.exists(AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A1/\(a1FrameworkName)")))
            XCTAssertTrue(
                try fs
                    .exists(
                        AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A3/\(a3FrameworkName)/local-archived")
                    )
            )
            XCTAssertTrue(
                try fs
                    .exists(AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A4/\(a4FrameworkName)/remote"))
            )

            // Ensure that the old artifacts have been removed
            XCTAssertFalse(try fs.exists(AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A2/\(a2FrameworkName)")))
            XCTAssertFalse(
                try fs
                    .exists(AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A3/\(a3FrameworkName)/remote"))
            )
            XCTAssertFalse(
                try fs
                    .exists(
                        AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A4/\(a4FrameworkName)/local-archived")
                    )
            )
            XCTAssertFalse(try fs.exists(AbsolutePath(validating: "\(sandbox)/.build/artifacts/a/A5/\(a5FrameworkName)")))
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A1",
                source: .local(checksum: "a1"),
                path: workspace.artifactsDir.appending(components: "a", "A1", a1FrameworkName)
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A2",
                source: .local(),
                path: a2FrameworkPath
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A3",
                source: .local(checksum: "a3"),
                path: workspace.artifactsDir.appending(components: "a", "A3", a3FrameworkName)
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A4",
                source: .remote(url: "https://a.com/a4.zip", checksum: "a4"),
                path: workspace.artifactsDir.appending(components: "a", "A4", a4FrameworkName)
            )
        }
    }

    func testLocalArchivedArtifactNameDoesNotMatchTargetName() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs: InMemoryFileSystem = InMemoryFileSystem()

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "archived-does-not-match-target-name.zip":
                    try createDummyXCFramework(
                        fileSystem: fs,
                        path: destinationPath,
                        name: "artifact-does-not-match-target-name"
                    )
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/archived-does-not-match-target-name.zip"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                archiver: archiver
            )
        )

        // Create dummy zip files
        let rootPath = try workspace.pathToRoot(withName: "Root")
        let frameworksPath = rootPath.appending("XCFrameworks")
        try fs.createDirectory(frameworksPath, recursive: true)
        try fs.writeFileContents(
            frameworksPath.appending("archived-does-not-match-target-name.zip"),
            bytes: ByteString([0xA1])
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testLocalArchivedArtifactExtractionError() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let archiver = MockArchiver(handler: { _, _, _, completion in
            completion(.failure(DummyError()))
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.zip"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "ArtifactBundles/A2.zip"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                archiver: archiver
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.checkUnordered(
                    diagnostic: .contains(
                        "failed extracting '\(sandbox.appending(components: "roots", "Root", "XCFrameworks", "A1.zip"))' which is required by binary target 'A1': dummy error"
                    ),
                    severity: .error
                )
                result.checkUnordered(
                    diagnostic: .contains(
                        "failed extracting '\(sandbox.appending(components: "roots", "Root", "ArtifactBundles", "A2.zip"))' which is required by binary target 'A2': dummy error"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testLocalArchiveDoesNotMatchTargetName() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // create dummy xcframework and artifactbundle directories from the request archive
        let archiver = MockArchiver(handler: { _, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "A1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "foo")
                case "A2.zip":
                    try createDummyArtifactBundle(fileSystem: fs, path: destinationPath, name: "bar")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })
        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.zip"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "ArtifactBundles/A2.zip"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                archiver: archiver
            )
        )

        // Create dummy zip files
        let rootPath = try workspace.pathToRoot(withName: "Root")
        let frameworksPath = rootPath.appending("XCFrameworks")
        try fs.createDirectory(frameworksPath, recursive: true)
        try fs.writeFileContents(frameworksPath.appending("A1.zip"), bytes: ByteString([0xA1]))

        let aArtifactBundlesPath = rootPath.appending("ArtifactBundles")
        try fs.createDirectory(aArtifactBundlesPath, recursive: true)
        try fs.writeFileContents(aArtifactBundlesPath.appending("A2.zip"), bytes: ByteString([0xA2]))

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A1",
                source: .local(checksum: "a1"),
                path: workspace.artifactsDir.appending(components: "root", "A1", "foo.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A2",
                source: .local(checksum: "a2"),
                path: workspace.artifactsDir.appending(components: "root", "A2", "bar.artifactbundle")
            )
        }
    }

////// STAET ATDIN
    func testLocalArchivedArtifactChecksumChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // create dummy xcframework directories from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "A1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                case "A2.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A2")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.zip"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "XCFrameworks/A2.zip"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                archiver: archiver
            )
        )

        let rootPath = try workspace.pathToRoot(withName: "Root")
        let rootRef = PackageReference.root(identity: PackageIdentity(path: rootPath), path: rootPath)

        // Set an initial workspace state
        try await workspace.set(
            managedArtifacts: [
                .init(
                    packageRef: rootRef,
                    targetName: "A1",
                    source: .local(checksum: "old-checksum"),
                    path: workspace.artifactsDir.appending(components: "root", "A1", "A1.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: rootRef,
                    targetName: "A2",
                    source: .local(checksum: "a2"),
                    path: workspace.artifactsDir.appending(components: "root", "A2", "A2.xcframework"),
                    kind: .xcframework
                ),
            ]
        )

        // Create dummy zip files
        let frameworksPath = rootPath.appending(components: "XCFrameworks")
        try fs.createDirectory(frameworksPath, recursive: true)

        let a1FrameworkArchivePath = frameworksPath.appending("A1.zip")
        try fs.writeFileContents(a1FrameworkArchivePath, bytes: ByteString([0xA1]))

        let a2FrameworkArchivePath = frameworksPath.appending("A2.zip")
        try fs.writeFileContents(a2FrameworkArchivePath, bytes: ByteString([0xA2]))

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, _ in
            // Ensure that only the artifact archive with the changed checksum has been extracted
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "A1"]),
            ])
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A1",
                source: .local(checksum: "a1"),
                path: workspace.artifactsDir.appending(components: "root", "A1", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A2",
                source: .local(checksum: "a2"),
                path: workspace.artifactsDir.appending(components: "root", "A2", "A2.xcframework")
            )
        }
    }

    func testLocalArchivedArtifactStripFirstComponent() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "flat.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "flat")
                case "nested.zip":
                    let nestedPath = destinationPath.appending("root")
                    try fs.createDirectory(nestedPath, recursive: true)
                    try createDummyXCFramework(fileSystem: fs, path: nestedPath, name: "nested")
                case "nested2.zip":
                    let nestedPath = destinationPath.appending("root")
                    try fs.createDirectory(nestedPath, recursive: true)
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "nested2")
                    try fs
                        .writeFileContents(
                            nestedPath.appending(".DS_Store"),
                            bytes: []
                        ) // add a file next to the directory
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "flat",
                            type: .binary,
                            path: "frameworks/flat.zip"
                        ),
                        MockTarget(
                            name: "nested",
                            type: .binary,
                            path: "frameworks/nested.zip"
                        ),

                        MockTarget(
                            name: "nested2",
                            type: .binary,
                            path: "frameworks/nested2.zip"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                archiver: archiver
            )
        )

        // create the mock archives
        let rootPath = try workspace.pathToRoot(withName: "Root")
        let archivesPath = rootPath.appending(components: "frameworks")
        try fs.createDirectory(archivesPath, recursive: true)
        try fs.writeFileContents(archivesPath.appending("flat.zip"), bytes: ByteString([0x1]))
        try fs.writeFileContents(archivesPath.appending("nested.zip"), bytes: ByteString([0x2]))
        try fs.writeFileContents(archivesPath.appending("nested2.zip"), bytes: ByteString([0x3]))

        // ensure that the artifacts do not exist yet
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root", "flat", "flat.xcframework"])))
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root", "nested", "nested.artifactbundle"])))
        XCTAssertFalse(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root", "nested2", "nested2.xcframework"])))

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root"])))
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "flat"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "nested"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "nested2"]),
            ])
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "flat",
                source: .local(checksum: "01"),
                path: workspace.artifactsDir.appending(components: "root", "flat", "flat.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "nested",
                source: .local(checksum: "02"),
                path: workspace.artifactsDir.appending(components: "root", "nested", "nested.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "nested2",
                source: .local(checksum: "03"),
                path: workspace.artifactsDir.appending(components: "root", "nested2", "nested2.xcframework")
            )
        }
    }

    func testLocalArtifactHappyPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/A1.xcframework"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "ArtifactBundles/A2.artifactbundle"
                        ),
                    ]
                ),
            ]
        )

        let rootPath = try workspace.pathToRoot(withName: "Root")

        // make sure the directory exist in their destined location
        try createDummyXCFramework(fileSystem: fs, path: rootPath.appending("XCFrameworks"), name: "A1")
        try createDummyArtifactBundle(fileSystem: fs, path: rootPath.appending("ArtifactBundles"), name: "A2")

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A1",
                source: .local(checksum: .none),
                path: rootPath.appending(components: "XCFrameworks", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A2",
                source: .local(checksum: .none),
                path: rootPath.appending(components: "ArtifactBundles", "A2.artifactbundle")
            )
        }
    }

    func testLocalArtifactDoesNotExist() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            path: "XCFrameworks/incorrect.xcframework"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            path: "ArtifactBundles/incorrect.artifactbundle"
                        ),
                    ]
                ),
            ]
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.checkUnordered(
                    diagnostic: .contains(
                        "local binary target 'A1' at '\(sandbox.appending(components: ["roots", "Root", "XCFrameworks", "incorrect.xcframework"]))' does not contain a binary artifact."
                    ),
                    severity: .error
                )
                result.checkUnordered(
                    diagnostic: .contains(
                        "local binary target 'A2' at '\(sandbox.appending(components: ["roots", "Root", "ArtifactBundles", "incorrect.artifactbundle"]))' does not contain a binary artifact."
                    ),
                    severity: .error
                )
            }
        }
    }

    func testArtifactDownloadHappyPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            case "a2.zip":
                contents = [0xA2]
            case "b.zip":
                contents = [0xB0]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads[request.url] = destination
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                case "a2.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A2")
                case "b.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "B")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            "B",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"
                        ),
                    ],
                    products: [
                        MockProduct(name: "A1", modules: ["A1"]),
                        MockProduct(name: "A2", modules: ["A2"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(
                            name: "B",
                            type: .binary,
                            url: "https://b.com/b.zip",
                            checksum: "b0"
                        ),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false // disable cache
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "a"])))
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "b"])))
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/a1.zip",
                "https://a.com/a2.zip",
                "https://b.com/b.zip",
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA1]).hexadecimalRepresentation,
                ByteString([0xA2]).hexadecimalRepresentation,
                ByteString([0xB0]).hexadecimalRepresentation,
            ])
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A1"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A2"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "b", "B"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A1",
                source: .remote(
                    url: "https://a.com/a1.zip",
                    checksum: "a1"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A1", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A2",
                source: .remote(
                    url: "https://a.com/a2.zip",
                    checksum: "a2"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A2", "A2.xcframework")
            )
            result.check(
                packageIdentity: .plain("b"),
                targetName: "B",
                source: .remote(
                    url: "https://b.com/b.zip",
                    checksum: "b0"
                ),
                path: workspace.artifactsDir.appending(components: "b", "B", "B.xcframework")
            )
        }

        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://a.com/a1.zip"])
        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://a.com/a2.zip"])
        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://b.com/b.zip"])
        XCTAssertMatch(
            workspace.delegate.events,
            ["finished downloading binary artifact package: https://a.com/a1.zip"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["finished downloading binary artifact package: https://a.com/a2.zip"]
        )
        XCTAssertMatch(workspace.delegate.events, ["finished downloading binary artifact package: https://b.com/b.zip"])
    }

    func testArtifactDownloadWithPreviousState() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            case "a2.zip":
                contents = [0xA2]
            case "a3.zip":
                contents = [0xA3]
            case "a7.zip":
                contents = [0xA7]
            case "b.zip":
                contents = [0xB0]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads[request.url] = destination
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                case "a2.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A2")
                case "a3.zip":
                    fs.createEmptyFiles(at: destinationPath, files: ".DS_Store") // invalid binary artifact
                case "a7.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A7")
                case "b.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "B")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            "B",
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            .product(name: "A3", package: "A"),
                            .product(name: "A4", package: "A"),
                            .product(name: "A7", package: "A"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"
                        ),
                        MockTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a3.zip",
                            checksum: "a3"
                        ),
                        MockTarget(
                            name: "A4",
                            type: .binary,
                            path: "XCFrameworks/A4.xcframework"
                        ),
                        MockTarget(
                            name: "A7",
                            type: .binary,
                            url: "https://a.com/a7.zip",
                            checksum: "a7"
                        ),
                    ],
                    products: [
                        MockProduct(name: "A1", modules: ["A1"]),
                        MockProduct(name: "A2", modules: ["A2"]),
                        MockProduct(name: "A3", modules: ["A3"]),
                        MockProduct(name: "A4", modules: ["A4"]),
                        MockProduct(name: "A7", modules: ["A7"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(
                            name: "B",
                            type: .binary,
                            url: "https://b.com/b.zip",
                            checksum: "b0"
                        ),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        let a4FrameworkPath = workspace.packagesDir.appending(components: "A", "XCFrameworks", "A4.xcframework")
        try createDummyXCFramework(fileSystem: fs, path: a4FrameworkPath.parentDirectory, name: "A4")

        // Pin A to 1.0.0, Checkout B to 1.0.0
        let aPath = try workspace.pathToPackage(withName: "A")
        let aRef = PackageReference.localSourceControl(identity: PackageIdentity(path: aPath), path: aPath)
        let aRepo = workspace.repositoryProvider.specifierMap[RepositorySpecifier(path: aPath)]!
        let aRevision = try aRepo.resolveRevision(tag: "1.0.0")
        let aState = CheckoutState.version("1.0.0", revision: aRevision)

        try await workspace.set(
            resolvedPackages: [aRef: aState],
            managedArtifacts: [
                .init(
                    packageRef: aRef,
                    targetName: "A1",
                    source: .remote(
                        url: "https://a.com/a1.zip",
                        checksum: "a1"
                    ),
                    path: workspace.artifactsDir.appending(components: "a", "A1", "A1.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A3",
                    source: .remote(
                        url: "https://a.com/old/a3.zip",
                        checksum: "a3-old-checksum"
                    ),
                    path: workspace.artifactsDir.appending(components: "a", "A3", "A3.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A4",
                    source: .remote(
                        url: "https://a.com/a4.zip",
                        checksum: "a4"
                    ),
                    path: workspace.artifactsDir.appending(components: "a", "A4", "A4.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A5",
                    source: .remote(
                        url: "https://a.com/a5.zip",
                        checksum: "a5"
                    ),
                    path: workspace.artifactsDir.appending(components: "a", "A5", "A5.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A6",
                    source: .local(),
                    path: workspace.artifactsDir.appending(components: "a", "A6", "A6.xcframework"),
                    kind: .xcframework
                ),
                .init(
                    packageRef: aRef,
                    targetName: "A7",
                    source: .local(),
                    path: workspace.packagesDir.appending(components: "a", "XCFrameworks", "A7.xcframework"),
                    kind: .xcframework
                ),
            ]
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "downloaded archive of binary target 'A3' from 'https://a.com/a3.zip' does not contain a binary artifact.",
                    severity: .error
                )
            }
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "b"])))
            XCTAssert(fs.exists(sandbox.appending(components: [".build", "artifacts", "a", "A1", "A1.xcframework"])))
            XCTAssert(fs.exists(sandbox.appending(components: [".build", "artifacts", "a", "A2", "A2.xcframework"])))
            XCTAssert(!fs.exists(sandbox.appending(components: [".build", "artifacts", "a", "A3", "A3.xcframework"])))
            XCTAssert(!fs.exists(sandbox.appending(components: [".build", "artifacts", "a", "A4", "A4.xcframework"])))
            XCTAssert(!fs.exists(sandbox.appending(components: [".build", "artifacts", "a", "A5", "A5.xcframework"])))
            XCTAssert(fs.exists(sandbox.appending(components: ["pkgs", "a", "XCFrameworks", "A7.xcframework"])))
            XCTAssert(!fs.exists(sandbox.appending(components: [".build", "artifacts", "Foo"])))
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/a2.zip",
                "https://a.com/a3.zip",
                "https://a.com/a7.zip",
                "https://b.com/b.zip",
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA2]).hexadecimalRepresentation,
                ByteString([0xA3]).hexadecimalRepresentation,
                ByteString([0xA7]).hexadecimalRepresentation,
                ByteString([0xB0]).hexadecimalRepresentation,
            ])
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract","a", "A2"]),
                sandbox.appending(components: [".build", "artifacts", "extract","a", "A3"]),
                sandbox.appending(components: [".build", "artifacts", "extract","a", "A7"]),
                sandbox.appending(components: [".build", "artifacts", "extract","b", "B"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A1",
                source: .remote(
                    url: "https://a.com/a1.zip",
                    checksum: "a1"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A1", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A2",
                source: .remote(
                    url: "https://a.com/a2.zip",
                    checksum: "a2"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A2", "A2.xcframework")
            )
            result.checkNotPresent(packageName: "A", targetName: "A3")
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A4",
                source: .local(),
                path: a4FrameworkPath
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A7",
                source: .remote(
                    url: "https://a.com/a7.zip",
                    checksum: "a7"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A7", "A7.xcframework")
            )
            result.checkNotPresent(packageName: "A", targetName: "A5")
            result.check(
                packageIdentity: .plain("b"),
                targetName: "B",
                source: .remote(
                    url: "https://b.com/b.zip",
                    checksum: "b0"
                ),
                path: workspace.artifactsDir.appending(components: "b", "B", "B.xcframework")
            )
        }
    }

    func testArtifactDownloadTwice() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeArrayStore<(URL, AbsolutePath)>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads.append((request.url, destination))
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                let name: String
                switch archivePath.basename {
                case "a1.zip":
                    name = "A1.xcframework"
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                let path = destinationPath.appending(component: name)
                if fs.exists(path) {
                    throw StringError("\(path) already exists")
                }
                try createDummyXCFramework(fileSystem: fs, path: path.parentDirectory, name: "A1")
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root"])))
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA1]).hexadecimalRepresentation,
            ])
        }

        XCTAssertEqual(downloads.map(\.0.absoluteString).sorted(), [
            "https://a.com/a1.zip",
        ])
        XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
            sandbox.appending(components: [".build", "artifacts", "extract", "root", "A1"]),
        ])
        XCTAssertEqual(
            downloads.map(\.1).sorted(),
            archiver.extractions.map(\.archivePath).sorted()
        )

        // reset

        try await workspace.resetState()

        // do it again

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root"])))

            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA1]).hexadecimalRepresentation, ByteString([0xA1]).hexadecimalRepresentation,
            ])
        }

        XCTAssertEqual(downloads.map(\.0.absoluteString).sorted(), [
            "https://a.com/a1.zip", "https://a.com/a1.zip",
        ])
        XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
            sandbox.appending(components: [".build", "artifacts", "extract", "root", "A1"]),
            sandbox.appending(components: [".build", "artifacts", "extract", "root", "A1"]),
        ])
        XCTAssertEqual(
            downloads.map(\.1).sorted(),
            archiver.extractions.map(\.archivePath).sorted()
        )
    }

    func testArtifactDownloadServerError() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws/")
        try fs.createDirectory(sandbox, recursive: true)
        let artifactUrl = "https://a.com/a.zip"

        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            // mimics URLSession behavior which write the file even if sends an error message
            try fileSystem.writeFileContents(
                destination,
                bytes: "not found",
                atomically: true
            )

            return .notFound()
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: artifactUrl,
                            checksum: "a1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "failed downloading 'https://a.com/a.zip' which is required by binary target 'A1': badResponseStatusCode(404)"
                    ),
                    severity: .error
                )
            }
        }

        // make sure artifact downloaded is deleted
        XCTAssertTrue(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root"])))
        XCTAssertFalse(fs.exists(sandbox.appending(components: [".build", "artifacts", "root", "a.zip"])))

        // make sure the cached artifact is also deleted
        let artifactCacheKey = artifactUrl.spm_mangledToC99ExtendedIdentifier()
        guard let cachePath = workspace.workspaceLocation?
            .sharedBinaryArtifactsCacheDirectory?
            .appending(artifactCacheKey)
        else {
            XCTFail("Required workspace location wasn't found")
            return
        }

        XCTAssertFalse(fs.exists(cachePath))
    }

    func testArtifactDownloaderOrArchiverError() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            switch request.url {
            case "https://a.com/a1.zip":
                return .serverError()
            case "https://a.com/a2.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA2]))
                return .okay()
            case "https://a.com/a3.zip":
                try fileSystem.writeFileContents(destination, bytes: "different contents = different checksum")
                return .okay()
            default:
                throw StringError("unexpected url")
            }
        }

        let archiver = MockArchiver(handler: { _, _, destinationPath, completion in
            XCTAssertEqual(destinationPath.parentDirectory, sandbox.appending(components: [".build", "artifacts", "extract", "root", "A2"]))
            completion(.failure(DummyError()))
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"
                        ),
                        MockTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a3.zip",
                            checksum: "a3"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.checkUnordered(
                    diagnostic: .contains(
                        "failed downloading 'https://a.com/a1.zip' which is required by binary target 'A1': badResponseStatusCode(500)"
                    ),
                    severity: .error
                )
                result.checkUnordered(
                    diagnostic: .contains(
                        "failed extracting 'https://a.com/a2.zip' which is required by binary target 'A2': dummy error"
                    ),
                    severity: .error
                )
                result.checkUnordered(
                    diagnostic: .contains(
                        "checksum of downloaded artifact of binary target 'A3' (6d75736b6365686320746e65726566666964203d2073746e65746e6f6320746e65726566666964) does not match checksum specified by the manifest (a3)"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadedArtifactNotAnArchiveError() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            switch request.url {
            case "https://a.com/a1.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA1]))
                return .okay()
            case "https://a.com/a2.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA2]))
                return .okay()
            case "https://a.com/a3.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA3]))
                return .okay()
            default:
                throw StringError("unexpected url")
            }
        }

        let archiver = MockArchiver(
            extractionHandler: { archiver, archivePath, destinationPath, completion in
                do {
                    if archivePath.basenameWithoutExt == "a1" {
                        try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                        archiver.extractions
                            .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                        completion(.success(()))
                    } else {
                        throw StringError("unexpected path")
                    }
                } catch {
                    completion(.failure(error))
                }
            },
            validationHandler: { _, path, completion in
                if path.basenameWithoutExt == "a1" {
                    completion(.success(true))
                } else if path.basenameWithoutExt == "a2" {
                    completion(.success(false))
                } else if path.basenameWithoutExt == "a3" {
                    completion(.failure(DummyError()))
                } else {
                    XCTFail("unexpected path")
                    completion(.success(false))
                }
            }
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip",
                            checksum: "a2"
                        ),
                        MockTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a3.zip",
                            checksum: "a3"
                        ),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.checkUnordered(
                    diagnostic: .contains(
                        "invalid archive returned from 'https://a.com/a2.zip' which is required by binary target 'A2'"
                    ),
                    severity: .error
                )
                result.checkUnordered(
                    diagnostic: .contains(
                        "failed validating archive from 'https://a.com/a3.zip' which is required by binary target 'A3': dummy error"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadedArtifactInvalid() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            switch request.url {
            case "https://a.com/a1.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA1]))
                return .okay()
            default:
                throw StringError("unexpected url")
            }
        }

        let archiver = MockArchiver(
            extractionHandler: { _, archivePath, destinationPath, completion in
                do {
                    if archivePath.basenameWithoutExt == "a1" {
                        // create file instead of directory
                        fs.createEmptyFiles(at: destinationPath, files: "A1.Framework")
                        completion(.success(()))
                    } else {
                        throw StringError("unexpected path")
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.checkUnordered(
                    diagnostic: .contains(
                        "downloaded archive of binary target 'A1' from 'https://a.com/a1.zip' does not contain a binary artifact."
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadedArtifactDoesNotMatchTargetName() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            switch request.url {
            case "https://a.com/foo.zip":
                try fileSystem.writeFileContents(destination, bytes: ByteString([0xA1]))
                return .okay()
            default:
                throw StringError("unexpected url")
            }
        }

        let archiver = MockArchiver(
            extractionHandler: { _, archivePath, destinationPath, completion in
                do {
                    if archivePath.basename == "foo.zip" {
                        try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "bar")
                        completion(.success(()))
                    } else {
                        throw StringError("unexpected path")
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/foo.zip",
                            checksum: "a1"
                        ),
                    ],
                    products: [],
                    dependencies: []
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A1",
                source: .remote(
                    url: "https://a.com/foo.zip",
                    checksum: "a1"
                ),
                path: workspace.artifactsDir.appending(components: "root", "A1", "bar.xcframework")
            )
        }
    }

    func testArtifactChecksum() async throws {
        try XCTSkipOnWindows(because: #"""
        threw error "\tmp\ws doesn't exist in file system" because there is an issue with InMemoryFileSystem readFileContents(...) on Windows
        """#)

        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let sandbox = AbsolutePath("/tmp/ws/")

        try fs.createDirectory(sandbox, recursive: true)

        let checksumAlgorithm = MockHashAlgorithm()
        let binaryArtifactsManager = try Workspace.BinaryArtifactsManager(
            fileSystem: fs,
            authorizationProvider: .none,
            hostToolchain: UserToolchain.mockHostToolchain(fs),
            checksumAlgorithm: checksumAlgorithm,
            cachePath: .none,
            customHTTPClient: .none,
            customArchiver: .none,
            delegate: .none
        )

        // Checks the valid case.
        do {
            let binaryPath = sandbox.appending("binary.zip")
            try fs.writeFileContents(binaryPath, bytes: ByteString([0xAA, 0xBB, 0xCC]))

            let checksum = try binaryArtifactsManager.checksum(forBinaryArtifactAt: binaryPath)
            XCTAssertEqual(checksumAlgorithm.hashes.map(\.contents), [[0xAA, 0xBB, 0xCC]])
            XCTAssertEqual(checksum, "ccbbaa")
        }

        // Checks an unsupported extension.
        do {
            let unknownPath = sandbox.appending("unknown")
            XCTAssertThrowsError(
                try binaryArtifactsManager.checksum(forBinaryArtifactAt: unknownPath),
                "error expected"
            ) { error in
                XCTAssertEqual(
                    error as? StringError,
                    StringError("unexpected file type; supported extensions are: zip")
                )
            }
        }

        // Checks a supported extension that is not a file (does not exist).
        do {
            let unknownPath = sandbox.appending("missingFile.zip")
            XCTAssertThrowsError(
                try binaryArtifactsManager.checksum(forBinaryArtifactAt: unknownPath),
                "error expected"
            ) { error in
                XCTAssertEqual(
                    error as? StringError,
                    StringError("file not found at path: \(sandbox.appending("missingFile.zip"))")
                )
            }
        }

        // Checks a supported extension that is a directory instead of a file.
        do {
            let unknownPath = sandbox.appending("aDirectory.zip")
            try fs.createDirectory(unknownPath)
            XCTAssertThrowsError(
                try binaryArtifactsManager.checksum(forBinaryArtifactAt: unknownPath),
                "error expected"
            ) { error in
                XCTAssertEqual(
                    error as? StringError,
                    StringError("file not found at path: \(sandbox.appending("aDirectory.zip"))")
                )
            }
        }
    }

    func testDownloadedArtifactChecksumChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { _, _ in
            throw StringError("should not be called")
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "A", type: .binary, url: "https://a.com/a.zip", checksum: "new-checksum"),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        let rootPath = try workspace.pathToRoot(withName: "Root")
        let rootRef = PackageReference.root(identity: PackageIdentity(path: rootPath), path: rootPath)

        try await workspace.set(
            managedArtifacts: [
                .init(
                    packageRef: rootRef,
                    targetName: "A",
                    source: .remote(
                        url: "https://a.com/a.zip",
                        checksum: "old-checksum"
                    ),
                    path: workspace.artifactsDir.appending(components: "Root", "A.xcframework"),
                    kind: .xcframework
                ),
            ]
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains("artifact of binary target 'A' has changed checksum"),
                    severity: .error
                )
            }
        }
    }

    func testDownloadedArtifactChecksumChangeURLChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a.zip":
                contents = [0xA1]
            case "b.zip":
                contents = [0xB1]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            return .okay()
        }

        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A")
                case "b.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "B")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/b.zip",
                            checksum: "b1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        let rootPath = try workspace.pathToRoot(withName: "Root")
        let rootRef = PackageReference.root(identity: PackageIdentity(path: rootPath), path: rootPath)

        try await workspace.set(
            managedArtifacts: [
                .init(
                    packageRef: rootRef,
                    targetName: "A",
                    source: .remote(
                        url: "https://a.com/a.zip",
                        checksum: "a1"
                    ),
                    path: workspace.artifactsDir.appending(components: "Root", "A.xcframework"),
                    kind: .xcframework
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testArtifactDownloadAddsAcceptHeader() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let acceptHeaders = ThreadSafeBox([String]())

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }
            acceptHeaders.mutate { $0?.append(request.headers.get("accept").first!) }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(acceptHeaders.get(), [
                "application/octet-stream",
            ])
        }
    }

    func testDownloadedArtifactNoCache() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeBox(0)

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads.increment()
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        // should not come from cache
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 1)
        }

        // state is there, should not come from local cache
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 1)
        }

        // resetting state, should not come from global cache
        try await workspace.resetState()
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 2)
        }
    }

    func testDownloadedArtifactCache() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeBox(0)

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.zip":
                contents = [0xA1]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads.increment()
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a1.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A1")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: true
            )
        )

        // should not come from cache
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 1)
        }

        // state is there, should not come from local cache
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 1)
        }

        // resetting state, should come from global cache
        try await workspace.resetState()
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 1)
        }

        // delete global cache, should download again
        try await workspace.resetState()
        try fs.removeFileTree(fs.swiftPMCacheDirectory)
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 2)
        }

        // resetting state, should come from global cache again
        try await workspace.resetState()
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.get(), 2)
        }
    }

    func testDownloadedArtifactTransitive() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a.zip":
                contents = [0xA]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            if downloads[request.url] != nil {
                throw StringError("\(request.url) already requested")
            }
            downloads[request.url] = destination
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "a.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "A")
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }

                if archiver.extractions.get().contains(where: { $0.archivePath == archivePath }) {
                    throw StringError("\(archivePath) already extracted")
                }

                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "A", package: "A"),
                            .product(name: "B", package: "B"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(name: "A", type: .binary, url: "https://a.com/a.zip", checksum: "0a"),
                    ],
                    products: [
                        MockProduct(name: "A", modules: ["A"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(name: "B", dependencies: [
                            .product(name: "C", package: "C"),
                            .product(name: "D", package: "D"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./C", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./D", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "C",
                    targets: [
                        MockTarget(name: "C", dependencies: [
                            .product(name: "A", package: "A"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "C", modules: ["C"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "D",
                    targets: [
                        MockTarget(name: "D", dependencies: [
                            .product(name: "A", package: "A"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "D", modules: ["D"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "a"])))
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/a.zip",
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA]).hexadecimalRepresentation,
            ])
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A",
                source: .remote(
                    url: "https://a.com/a.zip",
                    checksum: "0a"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A", "A.xcframework")
            )
        }
    }

    func testDownloadedArtifactArchiveExists() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        // this relies on internal knowledge of the destination path construction
        let expectedDownloadDestination = sandbox.appending(
            components: ".build",
            "artifacts",
            "root",
            "binary",
            "binary.zip"
        )

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            // this is to test the test's integrity, as it relied on internal knowledge of the destination path
            // construction
            guard expectedDownloadDestination == destination else {
                throw StringError("expected destination of \(expectedDownloadDestination)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "binary.zip":
                contents = [0x01]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            // in-memory fs does not check for this!
            if fileSystem.exists(destination) {
                throw StringError("\(destination) already exists")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "binary.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "binary")
                    archiver.extractions
                        .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "binary",
                            type: .binary,
                            url: "https://a.com/binary.zip",
                            checksum: "01"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        // write the file to test it gets deleted

        try fs.createDirectory(expectedDownloadDestination.parentDirectory, recursive: true)
        try fs.writeFileContents(
            expectedDownloadDestination,
            bytes: [],
            atomically: true
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "binary",
                source: .remote(
                    url: "https://a.com/binary.zip",
                    checksum: "01"
                ),
                path: workspace.artifactsDir.appending(components: "root", "binary", "binary.xcframework")
            )
        }
    }

    func testDownloadedArtifactConcurrency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let maxConcurrentRequests = 2
        let concurrentRequests = ThreadSafeBox(0)

        var configuration = HTTPClient.Configuration()
        configuration.maxConcurrentRequests = maxConcurrentRequests
        let httpClient = HTTPClient(configuration: configuration) { request, _ in
            defer {
                concurrentRequests.decrement()
            }

            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            concurrentRequests.increment()
            if concurrentRequests.get()! > maxConcurrentRequests {
                XCTFail("too many concurrent requests \(concurrentRequests), expected \(maxConcurrentRequests)")
            }

            // returns a dummy zipfile for the requested artifact
            try fileSystem.writeFileContents(
                destination,
                bytes: [0x01],
                atomically: true
            )

            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { _, archivePath, destinationPath, completion in
            do {
                try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: archivePath.basenameWithoutExt)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let packages = try (0 ... maxConcurrentRequests * 10).map { index in
            try MockPackage(
                name: "library\(index)",
                targets: [
                    MockTarget(
                        name: "binary\(index)",
                        type: .binary,
                        url: "https://somewhere.com/binary\(index).zip",
                        checksum: "01"
                    ),
                ],
                products: [
                    MockProduct(name: "binary\(index)", modules: ["binary\(index)"]),
                ],
                versions: ["1.0.0"]
            )
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "App",
                    targets: [
                        MockTarget(
                            name: "App",
                            dependencies: packages.map { package in
                                .product(name: package.targets.first!.name, package: package.name)
                            }
                        ),
                    ],
                    products: [],
                    dependencies: packages.map { package in
                        .sourceControl(path: "./\(package.name)", requirement: .exact("1.0.0"))
                    }
                ),
            ],
            packages: packages,
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["App"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        await workspace.checkManagedArtifacts { result in
            for package in packages {
                let targetName = package.targets.first!.name
                result.check(
                    packageIdentity: .plain(package.name),
                    targetName: targetName,
                    source: .remote(
                        url: "https://somewhere.com/\(targetName).zip",
                        checksum: "01"
                    ),
                    path: workspace.artifactsDir.appending(
                        components: package.name,
                        targetName,
                        "\(targetName).xcframework"
                    )
                )
            }
        }
    }

    func testDownloadedArtifactStripFirstComponent() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "flat.zip":
                contents = [0x01]
            case "nested.zip":
                contents = [0x02]
            case "nested2.zip":
                contents = [0x03]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads[request.url] = destination
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                switch archivePath.basename {
                case "flat.zip":
                    try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: "flat")
                    archiver.extractions
                        .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                case "nested.zip":
                    let nestedPath = destinationPath.appending("root")
                    try fs.createDirectory(nestedPath)
                    try createDummyXCFramework(fileSystem: fs, path: nestedPath, name: "nested")
                    archiver.extractions
                        .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                case "nested2.zip":
                    let nestedPath = destinationPath.appending("root")
                    try fs.createDirectory(nestedPath)
                    try createDummyXCFramework(fileSystem: fs, path: nestedPath, name: "nested2")
                    try fs
                        .writeFileContents(
                            nestedPath.appending(".DS_Store"),
                            bytes: []
                        ) // add a file next to the directory

                    archiver.extractions
                        .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "flat",
                            type: .binary,
                            url: "https://a.com/flat.zip",
                            checksum: "01"
                        ),
                        MockTarget(
                            name: "nested",
                            type: .binary,
                            url: "https://a.com/nested.zip",
                            checksum: "02"
                        ),

                        MockTarget(
                            name: "nested2",
                            type: .binary,
                            url: "https://a.com/nested2.zip",
                            checksum: "03"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "root"])))
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/flat.zip",
                "https://a.com/nested.zip",
                "https://a.com/nested2.zip",
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0x01]).hexadecimalRepresentation,
                ByteString([0x02]).hexadecimalRepresentation,
                ByteString([0x03]).hexadecimalRepresentation,
            ])
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "flat"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "nested"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "nested2"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "flat",
                source: .remote(
                    url: "https://a.com/flat.zip",
                    checksum: "01"
                ),
                path: workspace.artifactsDir.appending(components: "root", "flat", "flat.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "nested",
                source: .remote(
                    url: "https://a.com/nested.zip",
                    checksum: "02"
                ),
                path: workspace.artifactsDir.appending(components: "root", "nested", "nested.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "nested2",
                source: .remote(
                    url: "https://a.com/nested2.zip",
                    checksum: "03"
                ),
                path: workspace.artifactsDir.appending(components: "root", "nested2", "nested2.xcframework")
            )
        }
    }

    func testArtifactMultipleExtensions() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs: InMemoryFileSystem = InMemoryFileSystem()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()

        // returns a dummy zipfile for the requested artifact
        let httpClient = HTTPClient { request, _ in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            let contents: [UInt8]
            switch request.url.lastPathComponent {
            case "a1.xcframework.zip":
                contents = [0xA1]
            case "a2.zip.zip":
                contents = [0xA2]
            default:
                throw StringError("unexpected url \(request.url)")
            }

            try fileSystem.writeFileContents(
                destination,
                bytes: ByteString(contents),
                atomically: true
            )

            downloads[request.url] = destination
            return .okay()
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                let name: String
                switch archivePath.basename {
                case "a1.xcframework.zip":
                    name = "A1"
                case "a2.zip.zip":
                    name = "A2"
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                try createDummyXCFramework(fileSystem: fs, path: destinationPath, name: name)
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.xcframework.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.zip.zip",
                            checksum: "a2"
                        ),
                    ],
                    products: []
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            )
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/a1.xcframework.zip",
                "https://a.com/a2.zip.zip",
            ])
            XCTAssertEqual(workspace.checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(), [
                ByteString([0xA1]).hexadecimalRepresentation,
                ByteString([0xA2]).hexadecimalRepresentation,
            ])
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "A1"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "root", "A2"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A1",
                source: .remote(
                    url: "https://a.com/a1.xcframework.zip",
                    checksum: "a1"
                ),
                path: workspace.artifactsDir.appending(components: "root", "A1", "A1.xcframework")
            )
            result.check(
                packageIdentity: .plain("root"),
                targetName: "A2",
                source: .remote(
                    url: "https://a.com/a2.zip.zip",
                    checksum: "a2"
                ),
                path: workspace.artifactsDir.appending(components: "root", "A2", "A2.xcframework")
            )
        }
    }

    func testLoadRootPackageWithBinaryDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.zip",
                            checksum: "a1"
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.xcframework.zip",
                            checksum: "a2"
                        ),
                        MockTarget(
                            name: "A3",
                            type: .binary,
                            url: "https://a.com/a2.zip.zip",
                            checksum: "a3"
                        ),
                        MockTarget(
                            name: "A4",
                            type: .binary,
                            path: "a4.zip"
                        ),
                    ],
                    products: []
                ),
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        let wks = try workspace.getOrCreateWorkspace()
        _ = try await wks.loadRootPackage(
            at: workspace.rootsDir.appending("Root"),
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testDownloadArchiveIndexFilesHappyPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let downloads = ThreadSafeKeyValueStore<URL, AbsolutePath>()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        let ariFiles = [
            """
            {
                "schemaVersion": "1.0",
                "archives": [
                    {
                        "fileName": "a1.zip",
                        "checksum": "a1",
                        "supportedTriples": ["\(hostToolchain.targetTriple.tripleString)"]
                    }
                ]
            }
            """,
            """
            {
                "schemaVersion": "1.0",
                "archives": [
                    {
                        "fileName": "a2/a2.zip",
                        "checksum": "a2",
                        "supportedTriples": ["\(hostToolchain.targetTriple.tripleString)"]
                    }
                ]
            }
            """,
        ]

        let checksumAlgorithm = MockHashAlgorithm() // used in tests
        let ariFilesChecksums = ariFiles.map { checksumAlgorithm.hash($0).hexadecimalRepresentation }

        // returns a dummy file for the requested artifact
        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .generic:
                let contents: String
                switch request.url.lastPathComponent {
                case "a1.artifactbundleindex":
                    contents = ariFiles[0]
                case "a2.artifactbundleindex":
                    contents = ariFiles[1]
                default:
                    throw StringError("unexpected url \(request.url)")
                }
                return .okay(body: contents)

            case .download(let fileSystem, let destination):
                let contents: [UInt8]
                switch request.url.lastPathComponent {
                case "a1.zip":
                    contents = [0xA1]
                case "a2.zip":
                    contents = [0xA2]
                case "b.zip":
                    contents = [0xB0]
                default:
                    throw StringError("unexpected url \(request.url)")
                }

                try fileSystem.writeFileContents(
                    destination,
                    bytes: ByteString(contents),
                    atomically: true
                )

                downloads[request.url] = destination
                return .okay()
            }
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                let name: String
                switch archivePath.basename {
                case "a1.zip":
                    name = "A1"
                case "a2.zip":
                    name = "A2"
                case "b.zip":
                    name = "B"
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                try createDummyArtifactBundle(fileSystem: fs, path: destinationPath, name: name)
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "Foo", dependencies: [
                            .product(name: "A1", package: "A"),
                            .product(name: "A2", package: "A"),
                            "B",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "./A", requirement: .exact("1.0.0")),
                        .sourceControl(path: "./B", requirement: .exact("1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "A",
                    targets: [
                        MockTarget(
                            name: "A1",
                            type: .binary,
                            url: "https://a.com/a1.artifactbundleindex",
                            checksum: ariFilesChecksums[0]
                        ),
                        MockTarget(
                            name: "A2",
                            type: .binary,
                            url: "https://a.com/a2.artifactbundleindex",
                            checksum: ariFilesChecksums[1]
                        ),
                    ],
                    products: [
                        MockProduct(name: "A1", modules: ["A1"]),
                        MockProduct(name: "A2", modules: ["A2"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "B",
                    targets: [
                        MockTarget(
                            name: "B",
                            type: .binary,
                            url: "https://b.com/b.zip",
                            checksum: "b0"
                        ),
                    ],
                    products: [
                        MockProduct(name: "B", modules: ["B"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver,
                useCache: false
            ),
            checksumAlgorithm: checksumAlgorithm
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "a"])))
            XCTAssert(fs.isDirectory(sandbox.appending(components: [".build", "artifacts", "b"])))
            XCTAssertEqual(downloads.map(\.key.absoluteString).sorted(), [
                "https://a.com/a1.zip",
                "https://a.com/a2/a2.zip",
                "https://b.com/b.zip",
            ])
            XCTAssertEqual(
                checksumAlgorithm.hashes.map(\.hexadecimalRepresentation).sorted(),
                (
                    ariFiles.map(ByteString.init(encodingAsUTF8:)) +
                        ariFiles.map(ByteString.init(encodingAsUTF8:)) +
                        [
                            ByteString([0xA1]),
                            ByteString([0xA2]),
                            ByteString([0xB0]),
                        ]
                ).map(\.hexadecimalRepresentation).sorted()
            )
            XCTAssertEqual(archiver.extractions.map(\.destinationPath.parentDirectory).sorted(), [
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A1"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "a", "A2"]),
                sandbox.appending(components: [".build", "artifacts", "extract", "b", "B"]),
            ])
            XCTAssertEqual(
                downloads.map(\.value).sorted(),
                archiver.extractions.map(\.archivePath).sorted()
            )
        }

        await workspace.checkManagedArtifacts { result in
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A1",
                source: .remote(
                    url: "https://a.com/a1.zip",
                    checksum: "a1"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A1", "A1.artifactbundle")
            )
            result.check(
                packageIdentity: .plain("a"),
                targetName: "A2",
                source: .remote(
                    url: "https://a.com/a2/a2.zip",
                    checksum: "a2"
                ),
                path: workspace.artifactsDir.appending(components: "a", "A2", "A2.artifactbundle")
            )
            result.check(
                packageIdentity: .plain("b"),
                targetName: "B",
                source: .remote(
                    url: "https://b.com/b.zip",
                    checksum: "b0"
                ),
                path: workspace.artifactsDir.appending(components: "b", "B", "B.artifactbundle")
            )
        }

        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://a.com/a1.zip"])
        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://a.com/a2/a2.zip"])
        XCTAssertMatch(workspace.delegate.events, ["downloading binary artifact package: https://b.com/b.zip"])
        XCTAssertMatch(
            workspace.delegate.events,
            ["finished downloading binary artifact package: https://a.com/a1.zip"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["finished downloading binary artifact package: https://a.com/a2/a2.zip"]
        )
        XCTAssertMatch(workspace.delegate.events, ["finished downloading binary artifact package: https://b.com/b.zip"])
    }

    func testDownloadArchiveIndexServerError() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        // returns a dummy files for the requested artifact
        let httpClient = HTTPClient { _, _ in
            .serverError()
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: "does-not-matter"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "failed retrieving 'https://a.com/a.artifactbundleindex': badResponseStatusCode(500)"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadArchiveIndexFileBadChecksum() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        let ari = """
        {
            "schemaVersion": "1.0",
            "archives": [
                {
                    "fileName": "a1.zip",
                    "checksum": "a1",
                    "supportedTriples": ["\(hostToolchain.targetTriple.tripleString)"]
                }
            ]
        }
        """
        let checksumAlgorithm = MockHashAlgorithm() // used in tests
        let ariChecksums = checksumAlgorithm.hash(ari).hexadecimalRepresentation

        // returns a dummy files for the requested artifact
        let httpClient = HTTPClient { request, _ in
            let contents: String
            switch request.url.lastPathComponent {
            case "a.artifactbundleindex":
                contents = ari
            default:
                throw StringError("unexpected url \(request.url)")
            }
            return .okay(body: contents)
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: "incorrect"
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "failed retrieving 'https://a.com/a.artifactbundleindex': checksum of downloaded artifact of binary target 'A' (\(ariChecksums)) does not match checksum specified by the manifest (incorrect)"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadArchiveIndexFileChecksumChanges() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: "new-checksum"
                        ),
                    ]
                ),
            ]
        )

        let rootPath = try workspace.pathToRoot(withName: "Root")
        let rootRef = PackageReference.root(identity: PackageIdentity(path: rootPath), path: rootPath)

        try await workspace.set(
            managedArtifacts: [
                .init(
                    packageRef: rootRef,
                    targetName: "A",
                    source: .remote(
                        url: "https://a.com/a.artifactbundleindex",
                        checksum: "old-checksum"
                    ),
                    path: workspace.artifactsDir.appending(components: "root", "A.xcframework"),
                    kind: .xcframework
                ),
            ]
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains("artifact of binary target 'A' has changed checksum"),
                    severity: .error
                )
            }
        }
    }

    func testDownloadArchiveIndexFileBadArchivesChecksum() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        let ari = """
        {
            "schemaVersion": "1.0",
            "archives": [
                {
                    "fileName": "a.zip",
                    "checksum": "a",
                    "supportedTriples": ["\(hostToolchain.targetTriple.tripleString)"]
                }
            ]
        }
        """
        let checksumAlgorithm = MockHashAlgorithm() // used in tests
        let ariChecksums = checksumAlgorithm.hash(ari).hexadecimalRepresentation

        // returns a dummy files for the requested artifact
        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .generic:
                let contents: String
                switch request.url.lastPathComponent {
                case "a.artifactbundleindex":
                    contents = ari
                default:
                    throw StringError("unexpected url \(request.url)")
                }

                return .okay(body: contents)

            case .download(let fileSystem, let destination):
                let contents: [UInt8]
                switch request.url.lastPathComponent {
                case "a.zip":
                    contents = [0x42]
                default:
                    throw StringError("unexpected url \(request.url)")
                }

                try fileSystem.writeFileContents(
                    destination,
                    bytes: ByteString(contents),
                    atomically: true
                )

                return .okay()
            }
        }

        // create a dummy xcframework directory from the request archive
        let archiver = MockArchiver(handler: { archiver, archivePath, destinationPath, completion in
            do {
                let name: String
                switch archivePath.basename {
                case "a.zip":
                    name = "A.artifactbundle"
                default:
                    throw StringError("unexpected archivePath \(archivePath)")
                }
                try fs.createDirectory(destinationPath.appending(component: name), recursive: false)
                archiver.extractions
                    .append(MockArchiver.Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: ariChecksums
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "checksum of downloaded artifact of binary target 'A' (42) does not match checksum specified by the manifest (a)"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadArchiveIndexFileArchiveNotFound() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        let ari = """
        {
            "schemaVersion": "1.0",
            "archives": [
                {
                    "fileName": "not-found.zip",
                    "checksum": "a",
                    "supportedTriples": ["\(hostToolchain.targetTriple.tripleString)"]
                }
            ]
        }
        """
        let checksumAlgorithm = MockHashAlgorithm() // used in tests
        let ariChecksums = checksumAlgorithm.hash(ari).hexadecimalRepresentation

        // returns a dummy files for the requested artifact
        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .generic:
                let contents: String
                switch request.url.lastPathComponent {
                case "a.artifactbundleindex":
                    contents = ari
                default:
                    throw StringError("unexpected url \(request.url)")
                }
                return .okay(body: contents)

            case .download:
                return .notFound()
            }
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: ariChecksums
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "failed downloading 'https://a.com/not-found.zip' which is required by binary target 'A': badResponseStatusCode(404)"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDownloadArchiveIndexTripleNotFound() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        try fs.createMockToolchain()

        let hostToolchain = try UserToolchain.mockHostToolchain(fs)
        let androidTriple = try Triple("x86_64-unknown-linux-android")
        let macTriple = try Triple("arm64-apple-macosx")
        let notHostTriple = hostToolchain.targetTriple == androidTriple ? macTriple : androidTriple

        let ari = """
        {
            "schemaVersion": "1.0",
            "archives": [
                {
                    "fileName": "a1.zip",
                    "checksum": "a1",
                    "supportedTriples": ["\(notHostTriple.tripleString)"]
                }
            ]
        }
        """
        let checksumAlgorithm = MockHashAlgorithm() // used in tests
        let ariChecksum = checksumAlgorithm.hash(ari).hexadecimalRepresentation

        // returns a dummy files for the requested artifact
        let httpClient = HTTPClient { request, _ in
            let contents: String
            switch request.url.lastPathComponent {
            case "a.artifactbundleindex":
                contents = ari
            default:
                throw StringError("unexpected url \(request.url)")
            }
            return .okay(body: contents)
        }

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(
                            name: "A",
                            type: .binary,
                            url: "https://a.com/a.artifactbundleindex",
                            checksum: ariChecksum
                        ),
                    ]
                ),
            ],
            binaryArtifactsManager: .init(
                httpClient: httpClient
            )
        )

        await workspace.checkPackageGraphFailure(roots: ["Root"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .contains(
                        "failed retrieving 'https://a.com/a.artifactbundleindex': No supported archive was found for '\(hostToolchain.targetTriple.tripleString)'"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testDuplicateDependencyIdentityWithNameAtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "FooUtilityPackage"),
                            .product(name: "BarProduct", package: "BarUtilityPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FooUtilityPackage",
                            path: "foo/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControlWithDeprecatedName(
                            name: "BarUtilityPackage",
                            path: "bar/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                // this package never gets loaded since the dependency declaration identity is the same as "FooPackage"
                MockPackage(
                    name: "BarUtilityPackage",
                    path: "bar/utility",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "Conflicting identity for utility: dependency '\(CanonicalPackageLocation(sandbox.pathString))/pkgs/bar/utility' and dependency '\(CanonicalPackageLocation(sandbox.pathString))/pkgs/foo/utility' both point to the same package identity 'utility'.",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateDependencyIdentityWithoutNameAtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "FooUtilityPackage"),
                            .product(name: "BarProduct", package: "BarUtilityPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo/utility", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar/utility", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                // this package never gets loaded since the dependency declaration identity is the same as "FooPackage"
                MockPackage(
                    name: "BarUtilityPackage",
                    path: "bar/utility",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                result.check(
                    diagnostic: "Conflicting identity for utility: dependency '\(tmpDirCanonicalPackageLocation)/pkgs/bar/utility' and dependency '\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility' both point to the same package identity 'utility'.",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateExplicitDependencyName_AtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "FooPackage"),
                            .product(name: "BarProduct", package: "BarPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FooPackage",
                            path: "foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControlWithDeprecatedName(
                            name: "FooPackage",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                // this package never gets loaded since the dependency declaration name is the same as "FooPackage"
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "'root' dependency on '\(sandbox.appending(components: "pkgs", "bar"))' conflicts with dependency on '\(sandbox.appending(components: "pkgs", "foo"))' which has the same explicit name 'FooPackage'",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateManifestNameAtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            "FooProduct",
                            "BarProduct",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "MyPackage",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "MyPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateManifestName_ExplicitProductPackage_AtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "MyPackage",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "MyPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testManifestNameAndIdentityConflict_AtRoot_Pre52() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            "FooProduct",
                            "BarProduct",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "foo",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "foo",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testManifestNameAndIdentityConflict_AtRoot_Post52_Incorrect() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            "FooProduct",
                            "BarProduct",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_3
                ),
            ],
            packages: [
                MockPackage(
                    name: "foo",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "foo",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "dependency 'FooProduct' in target 'RootTarget' requires explicit declaration; reference the package in the target dependency with '.product(name: \"FooProduct\", package: \"foo\")'",
                    severity: .error
                )
                result.check(
                    diagnostic: "dependency 'BarProduct' in target 'RootTarget' requires explicit declaration; reference the package in the target dependency with '.product(name: \"BarProduct\", package: \"bar\")'",
                    severity: .error
                )
            }
        }
    }

    func testManifestNameAndIdentityConflict_AtRoot_Post52_Correct() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_3
                ),
            ],
            packages: [
                MockPackage(
                    name: "foo",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "foo",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testManifestNameAndIdentityConflict_ExplicitDependencyNames_AtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            "FooProduct",
                            "BarProduct",
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControlWithDeprecatedName(
                            name: "foo",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "foo",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "foo",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "'root' dependency on '\(sandbox.appending(components: "pkgs", "bar"))' conflicts with dependency on '\(sandbox.appending(components: "pkgs", "foo"))' which has the same explicit name 'foo'",
                    severity: .error
                )
            }
        }
    }

    func testManifestNameAndIdentityConflict_ExplicitDependencyNames_ExplicitProductPackage_AtRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "foo"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControlWithDeprecatedName(
                            name: "foo",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5_3
                ),
            ],
            packages: [
                MockPackage(
                    name: "foo",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "foo",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "'root' dependency on '\(sandbox.appending(components: "pkgs", "bar"))' conflicts with dependency on '\(sandbox.appending(components: "pkgs", "foo"))' which has the same explicit name 'foo'",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateTransitiveIdentityWithNames() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooUtilityProduct", package: "FooUtilityPackage"),
                            .product(name: "BarProduct", package: "BarPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FooUtilityPackage",
                            path: "foo/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControlWithDeprecatedName(
                            name: "BarPackage",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooUtilityProduct", modules: ["FooUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "OtherUtilityProduct", package: "OtherUtilityPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "OtherUtilityPackage",
                            path: "other/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "OtherUtilityPackage",
                    path: "other/utility",
                    targets: [
                        MockTarget(name: "OtherUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "OtherUtilityProduct", modules: ["OtherUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                result.check(
                    diagnostic: "Conflicting identity for utility: dependency '\(tmpDirCanonicalPackageLocation)/pkgs/other/utility' and dependency '\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility' both point to the same package identity 'utility'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/bar->\(tmpDirCanonicalPackageLocation)/pkgs/other/utility (B) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility. If there are multiple chains that lead to the same dependency, only the first chain is shown here. To see all chains use debug output option. To resolve the conflict, coordinate with the maintainer of the package that introduces the conflicting dependency.",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateTransitiveIdentityMultiplePossibleChains() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "HouseProduct", package: "HousePackage"),
                            .product(name: "ShackProduct", package: "ShackPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "HousePackage",
                            path: "house",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControlWithDeprecatedName(
                            name: "ShackPackage",
                            path: "shack",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "HousePackage",
                    path: "house",
                    targets: [
                        MockTarget(name: "HouseTarget", dependencies: [
                            .product(name: "BudgetWindowProduct", package: "BudgetWindowPackage"),
                            .product(name: "PremiumWindowProduct", package: "PremiumWindowPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "HouseProduct", modules: ["HouseTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "BudgetWindowPackage",
                            path: "budget_window",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControlWithDeprecatedName(
                            name: "PremiumWindowPackage",
                            path: "premium_window",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "ShackPackage",
                    path: "shack",
                    targets: [
                        MockTarget(name: "ShackTarget", dependencies: [
                            .product(name: "StandardGlassProduct", package: "StandardGlassPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "ShackProduct", modules: ["ShackTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "StandardGlassPackage",
                            path: "standard/glass",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BudgetWindowPackage",
                    path: "budget_window",
                    targets: [
                        MockTarget(name: "BudgetWindowTarget", dependencies: [
                            .product(name: "StandardGlassProduct", package: "StandardGlassPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BudgetWindowProduct", modules: ["BudgetWindowTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "StandardGlassPackage",
                            path: "standard/glass",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "PremiumWindowPackage",
                    path: "premium_window",
                    targets: [
                        MockTarget(name: "PremiumWindowTarget", dependencies: [
                            .product(name: "TemperedGlassProduct", package: "TemperedGlassPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "PremiumWindowProduct", modules: ["PremiumWindowTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "TemperedGlassPackage",
                            path: "tempered/glass",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "StandardGlassPackage",
                    path: "standard/glass",
                    targets: [
                        MockTarget(name: "StandardGlassTarget"),
                    ],
                    products: [
                        MockProduct(name: "StandardGlassProduct", modules: ["StandardGlassTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),

                // This package triggers the conflict.
                MockPackage(
                    name: "TemperedGlassPackage",
                    path: "tempered/glass",
                    targets: [
                        MockTarget(name: "TemperedTarget"),
                    ],
                    products: [
                        MockProduct(name: "TemperedGlassProduct", modules: ["TemperedGlassTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let sandboxCanonicalPackageLocation: CanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: "Conflicting identity for glass: dependency '\(sandboxCanonicalPackageLocation)/pkgs/tempered/glass' and dependency '\(sandboxCanonicalPackageLocation)/pkgs/standard/glass' both point to the same package identity 'glass'. The dependencies are introduced through the following chains: (A) \(sandboxCanonicalPackageLocation)/roots/root->\(sandboxCanonicalPackageLocation)/pkgs/house->\(sandboxCanonicalPackageLocation)/pkgs/premium_window->\(sandboxCanonicalPackageLocation)/pkgs/tempered/glass (B) \(sandboxCanonicalPackageLocation)/roots/root->\(sandboxCanonicalPackageLocation)/pkgs/shack->\(sandboxCanonicalPackageLocation)/pkgs/standard/glass. If there are multiple chains that lead to the same dependency, only the first chain is shown here. To see all chains use debug output option. To resolve the conflict, coordinate with the maintainer of the package that introduces the conflicting dependency.",
                    severity: .error
                )
            }
        }
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                let prefix1 = sandbox.appending(components: ["pkgs", "tempered", "glass"])
                result.checkUnordered(
                    diagnostic: .contains("Conflicting identity for glass: chains of dependencies for \(prefix1): [[\(sandboxCanonicalPackageLocation)/roots/root, \(sandboxCanonicalPackageLocation)/pkgs/house, \(sandboxCanonicalPackageLocation)/pkgs/premium_window, \(sandboxCanonicalPackageLocation)/pkgs/tempered/glass]]"),
                    severity: .debug
                )

                let prefix2 = sandbox.appending(components: ["pkgs", "standard", "glass"])
                result.checkUnordered(
                    diagnostic: .contains("Conflicting identity for glass: chains of dependencies for \(prefix2): [[\(sandboxCanonicalPackageLocation)/roots/root, \(sandboxCanonicalPackageLocation)/pkgs/shack, \(sandboxCanonicalPackageLocation)/pkgs/standard/glass], [\(sandboxCanonicalPackageLocation)/roots/root, \(sandboxCanonicalPackageLocation)/pkgs/house, \(sandboxCanonicalPackageLocation)/pkgs/budget_window, \(sandboxCanonicalPackageLocation)/pkgs/standard/glass]]"),
                    severity: .debug
                )
            }
        }
    }

    func testDuplicateIdentityDependenciesMultipleRoots() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "River",
                    targets: [
                        MockTarget(name: "RiverTarget", dependencies: [
                            .product(name: "FlowingWaterProduct", package: "FlowingWaterPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FlowingWaterPackage",
                            path: "flowing/water",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
                MockPackage(
                    name: "Lake",
                    targets: [
                        MockTarget(name: "LakeTarget", dependencies: [
                            .product(name: "StandingWaterProduct", package: "StandingWaterPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "StandingWaterPackage",
                            path: "standing/water",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FlowingWaterPackage",
                    path: "flowing/water",
                    targets: [
                        MockTarget(name: "FlowingWaterTarget"),
                    ],
                    products: [
                        MockProduct(name: "FlowingWaterProduct", modules: ["FlowingWaterTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),

                // This package triggers the conflict.
                MockPackage(
                    name: "StandingWaterPackage",
                    path: "standing/water",
                    targets: [
                        MockTarget(name: "StandingWaterTarget"),
                    ],
                    products: [
                        MockProduct(name: "StandingWaterProduct", modules: ["StandingWaterTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["River", "Lake"]) { _, diagnostics in
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                // Order of roots processing is not deterministic. To make the test less brittle, we check debug
                // output of individual conflicts instead of a summarized error message.
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                let prefix = sandbox.appending(components: ["pkgs", "standing", "water"])
                result.checkUnordered(
                    diagnostic: .contains("Conflicting identity for water: chains of dependencies for \(prefix): [[\(tmpDirCanonicalPackageLocation)/roots/lake, \(tmpDirCanonicalPackageLocation)/pkgs/standing/water]]"),
                    severity: .debug
                )

                let prefix2 = sandbox.appending(components: ["pkgs", "flowing", "water"])
                result.checkUnordered(
                    diagnostic: .contains("Conflicting identity for water: chains of dependencies for \(prefix2): [[\(tmpDirCanonicalPackageLocation)/roots/river, \(tmpDirCanonicalPackageLocation)/pkgs/flowing/water]]"),
                    severity: .debug
                )
            }
        }
    }

    func testDuplicateTransitiveIdentityWithoutNames() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooUtilityProduct", package: "utility"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo/utility", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooUtilityProduct", modules: ["FooUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "OtherUtilityProduct", package: "utility"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "other-foo/utility", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "OtherUtilityPackage",
                    path: "other-foo/utility",
                    targets: [
                        MockTarget(name: "OtherUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "OtherUtilityProduct", modules: ["OtherUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // 9/2021 this is currently emitting a warning only to support backwards compatibility
        // we will escalate this to an error in a few versions to tighten up the validation
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                result.check(
                    diagnostic: "Conflicting identity for utility: dependency '\(tmpDirCanonicalPackageLocation)/pkgs/other-foo/utility' and dependency '\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility' both point to the same package identity 'utility'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/bar->\(tmpDirCanonicalPackageLocation)/pkgs/other-foo/utility (B) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility. If there are multiple chains that lead to the same dependency, only the first chain is shown here. To see all chains use debug output option. To resolve the conflict, coordinate with the maintainer of the package that introduces the conflicting dependency. This will be escalated to an error in future versions of SwiftPM.",
                    severity: .warning
                )
                // FIXME: rdar://72940946
                // we need to improve this situation or diagnostics when working on identity
                result.check(
                    diagnostic: "product 'OtherUtilityProduct' required by package 'bar' target 'BarTarget' not found in package 'utility'.",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateTransitiveIdentitySimilarURLs1() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://github.com/foo/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/foo/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateTransitiveIdentitySimilarURLs2() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/foo/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://github.com/foo/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    url: "http://github.com/foo/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateTransitiveIdentityGitHubURLs1() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/foo/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "git@github.com:foo/foo.git", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateTransitiveIdentityGitHubURLs2() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.enterprise.com/foo/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.enterprise.com/foo/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.enterprise.com:foo/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.enterprise.com:foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testDuplicateTransitiveIdentityUnfamiliarURLs() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/foo/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/foo-moved/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/foo-moved/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // 9/2021 this is currently emitting a warning only to support backwards compatibility
        // we will escalate this to an error in a few versions to tighten up the validation
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                result.check(
                    diagnostic: "Conflicting identity for foo: dependency 'github.com/foo-moved/foo' and dependency 'github.com/foo/foo' both point to the same package identity 'foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/bar->github.com/foo-moved/foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->github.com/foo/foo. If there are multiple chains that lead to the same dependency, only the first chain is shown here. To see all chains use debug output option. To resolve the conflict, coordinate with the maintainer of the package that introduces the conflicting dependency. This will be escalated to an error in future versions of SwiftPM.",
                    severity: .warning
                )
            }
        }
    }

    func testDuplicateTransitiveIdentityWithSimilarURLs() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/baz.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://github.com/org/bar.git",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "Foo"),
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/ORG/Foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(url: "https://github.com/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://github.com/org/baz.git",
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                // URL with different casing
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/ORG/Foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                // URL with no .git extension
                MockPackage(
                    name: "BazPackage",
                    url: "https://github.com/org/baz",
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // 9/2021 this is currently emitting a warning only to support backwards compatibility
        // we will escalate this to an error in a few versions to tighten up the validation
        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics, minSeverity: .info) { result in
                result.checkUnordered(
                    diagnostic: "dependency on 'foo' is represented by similar locations ('https://github.com/org/foo.git' and 'https://github.com/ORG/Foo.git') which are treated as the same canonical location 'github.com/org/foo'.",
                    severity: .info
                )
                result.checkUnordered(
                    diagnostic: "dependency on 'baz' is represented by similar locations ('https://github.com/org/baz.git' and 'https://github.com/org/baz') which are treated as the same canonical location 'github.com/org/baz'.",
                    severity: .info
                )
            }
        }
    }

    func testDuplicateNestedTransitiveIdentityWithNames() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooUtilityProduct", package: "FooUtilityPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FooUtilityPackage",
                            path: "foo/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v6_0
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooUtilityTarget", dependencies: [
                            .product(name: "BarProduct", package: "BarPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "FooUtilityProduct", modules: ["FooUtilityTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "BarPackage",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "OtherUtilityProduct", package: "OtherUtilityPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "OtherUtilityPackage",
                            path: "other/utility",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "OtherUtilityPackage",
                    path: "other/utility",
                    targets: [
                        MockTarget(name: "OtherUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "OtherUtilityProduct", modules: ["OtherUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                result.check(
                    diagnostic: "Conflicting identity for utility: dependency '\(tmpDirCanonicalPackageLocation)/pkgs/other/utility' and dependency '\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility' both point to the same package identity 'utility'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility->\(tmpDirCanonicalPackageLocation)/pkgs/bar->\(tmpDirCanonicalPackageLocation)/pkgs/other/utility (B) \(tmpDirCanonicalPackageLocation)/roots/root->\(tmpDirCanonicalPackageLocation)/pkgs/foo/utility. If there are multiple chains that lead to the same dependency, only the first chain is shown here. To see all chains use debug output option. To resolve the conflict, coordinate with the maintainer of the package that introduces the conflicting dependency.",
                    severity: .error
                )
            }
        }
    }

    func testDuplicateNestedTransitiveIdentityWithoutNames() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooUtilityProduct", package: "FooUtilityPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(path: "foo/utility", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooUtilityPackage",
                    path: "foo/utility",
                    targets: [
                        MockTarget(name: "FooUtilityTarget", dependencies: [
                            .product(name: "BarProduct", package: "BarPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "FooUtilityProduct", modules: ["FooUtilityTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5
                ),
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "OtherUtilityProduct", package: "OtherUtilityPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "other/utility", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"],
                    toolsVersion: .v5
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "OtherUtilityPackage",
                    path: "other/utility",
                    targets: [
                        MockTarget(name: "OtherUtilityTarget"),
                    ],
                    products: [
                        MockProduct(name: "OtherUtilityProduct", modules: ["OtherUtilityTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                // FIXME: rdar://72940946
                // we need to improve this situation or diagnostics when working on identity
                result.check(
                    diagnostic: "cyclic dependency between packages Root -> FooUtilityPackage -> BarPackage -> FooUtilityPackage requires tools-version 6.0 or later",
                    severity: .error
                )
            }
        }
    }

    func testRootPathConflictsWithTransitiveIdentity() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "foo",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "BarProduct", package: "BarPackage"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "BarPackage",
                            path: "bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    toolsVersion: .v6_0
                ),
            ],
            packages: [
                MockPackage(
                    name: "BarPackage",
                    path: "bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "FooPackage"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControlWithDeprecatedName(
                            name: "FooPackage",
                            path: "foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                // this package never gets loaded since its identity is the same as "FooPackage"
                MockPackage(
                    name: "FooPackage",
                    path: "foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["foo"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                // FIXME: rdar://72940946
                // we need to improve this situation or diagnostics when working on identity
                result.check(
                    diagnostic: "product 'FooProduct' required by package 'bar' target 'BarTarget' not found in package 'FooPackage'.",
                    severity: .error
                )
            }
        }
    }

    func testDeterministicURLPreference() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "BarProduct", package: "bar"),
                            .product(name: "BazProduct", package: "baz"),
                            .product(name: "QuxProduct", package: "qux"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/baz.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/qux.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "BarPackage",
                    url: "https://github.com/org/bar.git",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://github.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "http://github.com/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://github.com/org/baz.git",
                    targets: [
                        MockTarget(name: "BazTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.com:org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "QuxPackage",
                    url: "https://github.com/org/qux.git",
                    targets: [
                        MockTarget(name: "QuxTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "QuxProduct", modules: ["QuxTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "baz", "foo", "Root", "qux")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "https://github.com/org/foo.git")
            }
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'git@github.com:org/foo.git' and 'https://github.com/org/foo.git'. using preferred variant 'https://github.com/org/foo.git'",
                    severity: .debug
                )
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'http://github.com/org/foo' and 'https://github.com/org/foo.git'. using preferred variant 'https://github.com/org/foo.git'",
                    severity: .debug
                )
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(
                result.managedDependencies["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }
    }

    func testDeterministicURLPreferenceWithRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.com:org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/baz.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://github.com/org/bar.git",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://github.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "http://github.com/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://github.com/org/baz.git",
                    targets: [
                        MockTarget(name: "BazTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "baz", "foo", "Root")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "git@github.com:org/foo.git")
            }
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'https://github.com/org/foo.git' and 'git@github.com:org/foo.git'. using preferred root variant 'git@github.com:org/foo.git'",
                    severity: .debug
                )
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'http://github.com/org/foo' and 'git@github.com:org/foo.git'. using preferred root variant 'git@github.com:org/foo.git'",
                    severity: .debug
                )
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(result.managedDependencies["foo"]?.packageRef.locationString, "git@github.com:org/foo.git")
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "git@github.com:org/foo.git"
            )
        }
    }

    func testCanonicalURLWithPreviousManagedState() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
                MockPackage(
                    name: "Root2",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "BarProduct", package: "bar"),
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/baz.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://github.com/org/bar.git",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.com:org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"],
                    revisionProvider: { _ in "bar" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://github.com/org/baz.git",
                    targets: [
                        MockTarget(name: "BazTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"],
                    revisionProvider: { _ in "baz" } // we need this to be consistent for fingerprints check to work
                ),
            ]
        )

        // resolve to set previous state

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "foo", "Root")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "git@github.com:org/foo.git")
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(result.managedDependencies["foo"]?.packageRef.locationString, "git@github.com:org/foo.git")
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "git@github.com:org/foo.git"
            )
        }

        // update to a different url via transitive dependencies

        try await workspace.checkPackageGraph(roots: ["Root2"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "baz", "foo", "Root2")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "git@github.com:org/foo.git")
            }
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                result.checkUnordered(
                    diagnostic: "required dependency 'foo' from 'https://github.com/org/foo' was not found in managed dependencies, using alternative location 'git@github.com:org/foo.git' instead",
                    severity: .info
                )
            }
        }

        await workspace.checkManagedDependencies { result in
            // we expect the managed dependency to carry the old state
            XCTAssertEqual(result.managedDependencies["foo"]?.packageRef.locationString, "git@github.com:org/foo.git")
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "https://github.com/org/foo"
            )
        }
    }

    func testCanonicalURLChanges() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
                MockPackage(
                    name: "Root2",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.com:org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
            ]
        )

        // check usage of canonical URL

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "foo", "Root")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "https://github.com/org/foo.git")
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(
                result.managedDependencies["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }

        // update URL to one with different scheme

        try await workspace.checkPackageGraph(roots: ["Root2"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "foo", "Root2")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "git@github.com:org/foo.git")
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(result.managedDependencies["foo"]?.packageRef.locationString, "git@github.com:org/foo.git")
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "git@github.com:org/foo.git"
            )
        }
    }

    func testCanonicalURLChangesWithTransitiveDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "https://github.com/org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
                MockPackage(
                    name: "Root2",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "git@github.com:org/foo.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .sourceControl(
                            url: "https://github.com/org/bar.git",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://github.com/org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://github.com/org/bar.git",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://github.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "http://github.com/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "git@github.com:org/foo.git",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"],
                    revisionProvider: { _ in "foo" } // we need this to be consistent for fingerprints check to work
                ),
            ]
        )

        // check usage of canonical URL

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "foo", "Root")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "https://github.com/org/foo.git")
            }
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'http://github.com/org/foo' and 'https://github.com/org/foo.git'. using preferred root variant 'https://github.com/org/foo.git'",
                    severity: .debug
                )
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(
                result.managedDependencies["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "https://github.com/org/foo.git"
            )
        }

        // update URL to one with different scheme

        try await workspace.checkPackageGraph(roots: ["Root2"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(packages: "bar", "foo", "Root2")
                let package = result.find(package: "foo")
                XCTAssertEqual(package?.manifest.packageLocation, "git@github.com:org/foo.git")
            }
            testPartialDiagnostics(diagnostics, minSeverity: .debug) { result in
                result.checkUnordered(
                    diagnostic: "similar variants of package 'foo' found at 'http://github.com/org/foo' and 'git@github.com:org/foo.git'. using preferred root variant 'git@github.com:org/foo.git'",
                    severity: .debug
                )
            }
        }

        await workspace.checkManagedDependencies { result in
            XCTAssertEqual(result.managedDependencies["foo"]?.packageRef.locationString, "git@github.com:org/foo.git")
        }

        workspace.checkResolved { result in
            XCTAssertEqual(
                result.store.resolvedPackages["foo"]?.packageRef.locationString,
                "git@github.com:org/foo.git"
            )
        }
    }

    func testCycleRoot() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root1",
                    targets: [
                        .init(name: "Root1Target", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "Root2Product", package: "Root2"),
                        ]),
                    ],
                    products: [
                        .init(name: "Root1Product", modules: ["Root1Target"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://scm.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .fileSystem(path: "Root2"),
                    ]
                ),
                MockPackage(
                    name: "Root2",
                    targets: [
                        .init(name: "Root2Target", dependencies: [
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [
                        .init(name: "Root2Product", modules: ["Root2Target"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://scm.com/org/bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "http://scm.com/org/foo",
                    targets: [
                        .init(name: "FooTarget", dependencies: [
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [
                        .init(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://scm.com/org/bar",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "http://scm.com/org/bar",
                    targets: [
                        .init(name: "BarTarget", dependencies: [
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    products: [
                        .init(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://scm.com/org/baz",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "http://scm.com/org/baz",
                    targets: [
                        .init(name: "BazTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        .init(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(
                            url: "http://scm.com/org/foo",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root1", "Root2"]) { _, diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .regex("cyclic dependency declaration found: Root[1|2]Target -> *"),
                    severity: .error
                )
            }
        }
    }

    func testResolutionBranchAndVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/foo", requirement: .branch("experiment")),
                        .sourceControl(url: "http://localhost/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "http://localhost/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "experiment"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "http://localhost/org/bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "bar", "foo", "Root")
                result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                result.checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.branch("experiment")))
            result.check(dependency: "bar", at: .checkout(.version("1.0.0")))
        }
    }

    func testBinaryArtifactsInvalidPath() async throws {
        try await testWithTemporaryDirectory { path in
            let fs = localFileSystem
            let observability = ObservabilitySystem.makeForTesting()

            let foo = path.appending("foo")
            try fs.writeFileContents(
                foo.appending("Package.swift"),
                string: """
                // swift-tools-version:5.3
                import PackageDescription
                let package = Package(
                    name: "Best",
                    targets: [
                        .binaryTarget(name: "best", path: "/best.xcframework")
                    ]
                )
                """
            )

            let manifestLoader = try ManifestLoader(toolchain: UserToolchain.default)
            let sandbox = path.appending("ws")
            let workspace = try Workspace(
                fileSystem: fs,
                forRootPackage: sandbox,
                customManifestLoader: manifestLoader,
                delegate: MockWorkspaceDelegate()
            )

            try await workspace.resolve(root: .init(packages: [foo]), observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "invalid local path '/best.xcframework' for binary target 'best', path expected to be relative to package root.",
                    severity: .error
                )
            }
        }
    }

    func testManifestLoaderDiagnostics() async throws {
        struct TestLoader: ManifestLoaderProtocol {
            let error: Error?

            init(error: Error?) {
                self.error = error
            }

            func load(
                manifestPath: AbsolutePath,
                manifestToolsVersion: ToolsVersion,
                packageIdentity: PackageIdentity,
                packageKind: PackageReference.Kind,
                packageLocation: String,
                packageVersion: (version: Version?, revision: String?)?,
                identityResolver: IdentityResolver,
                dependencyMapper: DependencyMapper,
                fileSystem: FileSystem,
                observabilityScope: ObservabilityScope,
                delegateQueue: DispatchQueue
            ) async throws -> Manifest {
                if let error {
                    throw error
                } else {
                    return Manifest.createManifest(
                        displayName: packageIdentity.description,
                        path: manifestPath,
                        packageKind: packageKind,
                        packageIdentity: packageIdentity,
                        packageLocation: packageLocation,
                        platforms: [],
                        toolsVersion: manifestToolsVersion
                    )
                }
            }

            func resetCache(observabilityScope: ObservabilityScope) {}
            func purgeCache(observabilityScope: ObservabilityScope) {}
        }

        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()
        let observability = ObservabilitySystem.makeForTesting()

        // write a manifest
        try fs.writeFileContents(.root.appending(component: Manifest.filename), bytes: "")
        try ToolsVersionSpecificationWriter.rewriteSpecification(
            manifestDirectory: .root,
            toolsVersion: .current,
            fileSystem: fs
        )

        let customHostToolchain = try UserToolchain.mockHostToolchain(fs)

        do {
            // no error
            let delegate = MockWorkspaceDelegate()
            let workspace = try Workspace(
                fileSystem: fs,
                environment: .mockEnvironment,
                forRootPackage: .root,
                customHostToolchain: customHostToolchain,
                customManifestLoader: TestLoader(error: .none),
                delegate: delegate
            )
            try await workspace.loadPackageGraph(rootPath: .root, observabilityScope: observability.topScope)

            XCTAssertNotNil(delegate.manifest)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(delegate.manifestLoadingDiagnostics ?? [])
        }

        do {
            // actual error
            let delegate = MockWorkspaceDelegate()
            let workspace = try Workspace(
                fileSystem: fs,
                environment: .mockEnvironment,
                forRootPackage: .root,
                customHostToolchain: customHostToolchain,
                customManifestLoader: TestLoader(error: StringError("boom")),
                delegate: delegate
            )
            try await workspace.loadPackageGraph(rootPath: .root, observabilityScope: observability.topScope)

            XCTAssertNil(delegate.manifest)
            testDiagnostics(delegate.manifestLoadingDiagnostics ?? []) { result in
                result.check(diagnostic: .equal("boom"), severity: .error)
            }
            testDiagnostics(delegate.manifestLoadingDiagnostics ?? []) { result in
                result.check(diagnostic: .equal("boom"), severity: .error)
            }
        }
    }

    func testBasicResolutionFromSourceControl() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget1",
                            dependencies: [
                                .product(name: "Foo", package: "foo"),
                            ]
                        ),
                        MockTarget(
                            name: "MyTarget2",
                            dependencies: [
                                .product(name: "Bar", package: "bar"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget1", "MyTarget2"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "http://localhost/org/bar", requirement: .upToNextMajor(from: "2.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "http://localhost/org/foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0", "1.5.0", "1.5.1"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "http://localhost/org/bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["2.0.0", "2.1.0", "2.2.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "MyPackage")
                result.check(packages: "Bar", "Foo", "MyPackage")
                result.check(modules: "Foo", "Bar", "MyTarget1", "MyTarget2")
                result.checkTarget("MyTarget1") { result in result.check(dependencies: "Foo") }
                result.checkTarget("MyTarget2") { result in result.check(dependencies: "Bar") }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.5.1")))
            result.check(dependency: "bar", at: .checkout(.version("2.2.0")))
        }

        // Check the load-package callbacks.
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for remoteSourceControl package: http://localhost/org/foo (identity: foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for remoteSourceControl package: http://localhost/org/foo (identity: foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for remoteSourceControl package: http://localhost/org/bar (identity: bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for remoteSourceControl package: http://localhost/org/bar (identity: bar)"]
        )
    }

    func testBasicTransitiveResolutionFromSourceControl() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget1",
                            dependencies: [
                                .product(name: "Foo", package: "foo"),
                            ]
                        ),
                        MockTarget(
                            name: "MyTarget2",
                            dependencies: [
                                .product(name: "Bar", package: "bar"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget1", "MyTarget2"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "http://localhost/org/bar", requirement: .upToNextMajor(from: "2.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    url: "http://localhost/org/foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(name: "Baz", package: "baz"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/baz", requirement: .range("2.0.0" ..< "4.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "Bar",
                    url: "http://localhost/org/bar",
                    targets: [
                        MockTarget(
                            name: "Bar",
                            dependencies: [
                                .product(name: "Baz", package: "baz"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "http://localhost/org/baz", requirement: .upToNextMajor(from: "3.0.0")),
                    ],
                    versions: ["2.0.0", "2.1.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "http://localhost/org/baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0", "3.0.0", "3.1.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "MyPackage")
                result.check(packages: "Bar", "Baz", "Foo", "MyPackage")
                result.check(modules: "Foo", "Bar", "Baz", "MyTarget1", "MyTarget2")
                result.checkTarget("MyTarget1") { result in result.check(dependencies: "Foo") }
                result.checkTarget("MyTarget2") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "foo", at: .checkout(.version("1.1.0")))
            result.check(dependency: "bar", at: .checkout(.version("2.1.0")))
            result.check(dependency: "baz", at: .checkout(.version("3.1.0")))
        }

        // Check the load-package callbacks.
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for remoteSourceControl package: http://localhost/org/foo (identity: foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for remoteSourceControl package: http://localhost/org/foo (identity: foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for remoteSourceControl package: http://localhost/org/bar (identity: bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for remoteSourceControl package: http://localhost/org/bar (identity: bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for remoteSourceControl package: http://localhost/org/baz (identity: baz)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for remoteSourceControl package: http://localhost/org/baz (identity: baz)"]
        )
    }

    func testBasicResolutionFromRegistry() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget1",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                        MockTarget(
                            name: "MyTarget2",
                            dependencies: [
                                .product(name: "Bar", package: "org.bar"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget1", "MyTarget2"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "2.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0", "1.5.0", "1.5.1"]
                ),
                MockPackage(
                    name: "Bar",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["2.0.0", "2.1.0", "2.2.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "MyPackage")
                result.check(packages: "org.bar", "org.foo", "mypackage")
                result.check(modules: "Foo", "Bar", "MyTarget1", "MyTarget2")
                result.checkTarget("MyTarget1") { result in result.check(dependencies: "Foo") }
                result.checkTarget("MyTarget2") { result in result.check(dependencies: "Bar") }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.foo", at: .registryDownload("1.5.1"))
            result.check(dependency: "org.bar", at: .registryDownload("2.2.0"))
        }

        // Check the load-package callbacks.
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for registry package: org.foo (identity: org.foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for registry package: org.foo (identity: org.foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for registry package: org.bar (identity: org.bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for registry package: org.bar (identity: org.bar)"]
        )
    }

    func testBasicTransitiveResolutionFromRegistry() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget1",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                        MockTarget(
                            name: "MyTarget2",
                            dependencies: [
                                .product(name: "Bar", package: "org.bar"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget1", "MyTarget2"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "2.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(name: "Baz", package: "org.baz"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.baz", requirement: .range("2.0.0" ..< "4.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "Bar",
                    identity: "org.bar",
                    targets: [
                        MockTarget(
                            name: "Bar",
                            dependencies: [
                                .product(name: "Baz", package: "org.baz"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.baz", requirement: .upToNextMajor(from: "3.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0"]
                ),
                MockPackage(
                    name: "Baz",
                    identity: "org.baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0", "3.0.0", "3.1.0"]
                ),
            ]
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "MyPackage")
                result.check(packages: "org.bar", "org.baz", "org.foo", "mypackage")
                result.check(modules: "Foo", "Bar", "Baz", "MyTarget1", "MyTarget2")
                result.checkTarget("MyTarget1") { result in result.check(dependencies: "Foo") }
                result.checkTarget("MyTarget2") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.foo", at: .registryDownload("1.1.0"))
            result.check(dependency: "org.bar", at: .registryDownload("2.1.0"))
            result.check(dependency: "org.baz", at: .registryDownload("3.1.0"))
        }

        // Check the load-package callbacks.
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "will load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            [
                "did load manifest for root package: \(sandbox.appending(components: "roots", "MyPackage")) (identity: mypackage)",
            ]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for registry package: org.foo (identity: org.foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for registry package: org.foo (identity: org.foo)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for registry package: org.bar (identity: org.bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for registry package: org.bar (identity: org.bar)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["will load manifest for registry package: org.baz (identity: org.baz)"]
        )
        XCTAssertMatch(
            workspace.delegate.events,
            ["did load manifest for registry package: org.baz (identity: org.baz)"]
        )
    }

    func testTransitiveResolutionFromRegistryWithByNameDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    identity: "org.bar",
                    alternativeURLs: ["https://git/org/Bar"],
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget", dependencies: [
                            "Bar",
                        ]),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        workspace.sourceControlToRegistryDependencyTransformation = .swizzle

        try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "org.bar", "org.foo", "Root")
                result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                result.checkTarget("RootTarget") { result in
                    result.check(dependencies: "FooProduct")
                }
                result.checkTarget("FooTarget") { result in
                    result.check(dependencies: "Bar")
                }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
            result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
        }
    }

    // no dups
    func testResolutionMixedRegistryAndSourceControl1() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget"),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }
    }

    func testTransitiveResolutionFromRegistryWithDifferentPackageNameCasing() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "Foo"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        workspace.sourceControlToRegistryDependencyTransformation = .swizzle

        try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                result.check(roots: "Root")
                result.check(packages: "org.foo", "Root")
                result.check(modules: "FooTarget", "RootTarget")
                result.checkTarget("RootTarget") { result in
                    result.check(dependencies: "FooProduct")
                }
                result.checkTarget("FooTarget") { result in
                    result.check(dependencies: [])
                }
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
        }
    }

    // duplicate package at root level
    func testResolutionMixedRegistryAndSourceControl2() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled

            await XCTAssertAsyncThrowsError(try await workspace.checkPackageGraph(roots: ["root"]) { _, _ in
            }) { error in
                XCTAssertEqual(
                    (error as? PackageGraphError)?.description,
                    "multiple packages (\'foo\' (from \'https://git/org/foo\'), \'org.foo\') declare products with a conflicting name: \'FooProduct’; product names need to be unique across the package graph"
                )
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: "Conflicting identity for org.foo: dependency 'org.foo' and dependency 'git/org/foo' both point to the same package identity 'org.foo'.",
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            // TODO: this error message should be improved
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: "Conflicting identity for org.foo: dependency 'org.foo' and dependency 'org.foo' both point to the same package identity 'org.foo'.",
                        severity: .error
                    )
                }
            }
        }
    }

    // mixed graph root --> dep1 scm
    //                  --> dep2 scm --> dep1 registry
    func testResolutionMixedRegistryAndSourceControl3() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://git/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://git/org/bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "2.0.0", "2.1.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                    result.check(
                        diagnostic: .contains("""
                        dependency 'org.foo' and dependency 'git/org/foo' both point to the same package identity 'org.foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->git/org/bar->org.foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->git/org/foo.
                        """),
                        severity: .warning
                    )
                }

                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.1.0")))
                result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)

                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.1.0"))
                result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.1.0"))
                result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            }
        }
    }

    // mixed graph root --> dep1 scm
    //                  --> dep2 registry --> dep1 registry
    func testResolutionMixedRegistryAndSourceControl4() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.1.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.2.0")),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                    result.check(
                        diagnostic: .contains("""
                        dependency 'org.foo' and dependency 'git/org/foo' both point to the same package identity 'org.foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->org.bar->org.foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->git/org/foo.
                        """),
                        severity: .warning
                    )
                }
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }
    }

    // mixed graph root --> dep1 scm
    //                  --> dep2 scm --> dep1 registry incompatible version
    func testResolutionMixedRegistryAndSourceControl5() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://git/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    url: "https://git/org/bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic:
                        """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'bar' 1.0.0..<2.0.0.
                        'bar' >= 1.0.0 practically depends on 'org.foo' 2.0.0..<3.0.0 because no versions of 'bar' match the requirement 1.0.1..<2.0.0 and 'bar' 1.0.0 depends on 'org.foo' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic:
                        """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'bar' 1.0.0..<2.0.0.
                        'bar' >= 1.0.0 practically depends on 'org.foo' 2.0.0..<3.0.0 because no versions of 'bar' match the requirement 1.0.1..<2.0.0 and 'bar' 1.0.0 depends on 'org.foo' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }
    }

    // mixed graph root --> dep1 registry
    //                  --> dep2 registry --> dep1 scm
    func testResolutionMixedRegistryAndSourceControl6() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.1.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "1.2.0")),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        dependency 'git/org/foo' and dependency 'org.foo' both point to the same package identity 'org.foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->org.bar->git/org/foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->org.foo.
                        """),
                        severity: .warning
                    )
                    if ToolsVersion.current >= .v5_8 {
                        result.check(
                            diagnostic: .contains("""
                            product 'FooProduct' required by package 'org.bar' target 'BarTarget' not found in package 'foo'.
                            """),
                            severity: .error
                        )
                    }
                }
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }
    }

    // mixed graph root --> dep1 registry
    //                  --> dep2 registry --> dep1 scm incompatible version
    func testResolutionMixedRegistryAndSourceControl7() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic:
                        """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'org.bar' 1.0.0..<2.0.0.
                        'org.bar' >= 1.0.0 practically depends on 'org.foo' 2.0.0..<3.0.0 because no versions of 'org.bar' match the requirement 1.0.1..<2.0.0 and 'org.bar' 1.0.0 depends on 'org.foo' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic:
                        """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'org.bar' 1.0.0..<2.0.0.
                        'org.bar' >= 1.0.0 practically depends on 'org.foo' 2.0.0..<3.0.0 because no versions of 'org.bar' match the requirement 1.0.1..<2.0.0 and 'org.bar' 1.0.0 depends on 'org.foo' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }
    }

    // mixed graph root --> dep1 registry --> dep3 scm
    //                  --> dep2 registry --> dep3 registry
    func testResolutionMixedRegistryAndSourceControl8() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "FooTarget", dependencies: [
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/baz", requirement: .upToNextMajor(from: "1.1.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "BazProduct", package: "org.baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://git/org/baz",
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    identity: "org.baz",
                    alternativeURLs: ["https://git/org/baz"],
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0", "1.1.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'BazTarget' appear in registry package 'org.baz' and source control package 'baz'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
                    result.check(
                        diagnostic: .contains("""
                        dependency 'git/org/baz' and dependency 'org.baz' both point to the same package identity 'org.baz'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->org.foo->git/org/baz (B) \(tmpDirCanonicalPackageLocation)/roots/root->org.bar->org.baz.
                        """),
                        severity: .warning
                    )
                    if ToolsVersion.current >= .v5_8 {
                        result.check(
                            diagnostic: .contains("""
                            product 'BazProduct' required by package 'org.foo' target 'FooTarget' not found in package 'baz'.
                            """),
                            severity: .error
                        )
                    }
                }
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.baz", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "BazTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                    if ToolsVersion.current < .v5_8 {
                        result.checkTarget("FooTarget") { result in result.check(dependencies: "BazProduct") }
                    }
                    result.checkTarget("BarTarget") { result in result.check(dependencies: "BazProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.baz", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                XCTAssertNoDiagnostics(diagnostics)
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.baz", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "BazTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                    result.checkTarget("FooTarget") { result in result.check(dependencies: "BazProduct") }
                    result.checkTarget("BarTarget") { result in result.check(dependencies: "BazProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.baz", at: .registryDownload("1.1.0"))
            }
        }
    }

    // mixed graph root --> dep1 registry --> dep3 scm
    //                  --> dep2 registry --> dep3 registry incompatible version
    func testResolutionMixedRegistryAndSourceControl9() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "FooTarget", dependencies: [
                            .product(name: "BazProduct", package: "baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(url: "https://git/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "BazProduct", package: "org.baz"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.baz", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    url: "https://git/org/baz",
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "BazPackage",
                    identity: "org.baz",
                    alternativeURLs: ["https://git/org/baz"],
                    targets: [
                        MockTarget(name: "BazTarget"),
                    ],
                    products: [
                        MockProduct(name: "BazProduct", modules: ["BazTarget"]),
                    ],
                    versions: ["1.0.0", "2.0.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'BazTarget' appear in registry package 'org.baz' and source control package 'baz'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'org.bar' 1.0.0..<2.0.0.
                        'org.bar' is incompatible with 'org.foo' because 'org.foo' 1.0.0 depends on 'org.baz' 1.0.0..<2.0.0 and no versions of 'org.foo' match the requirement 1.0.1..<2.0.0.
                        'org.bar' >= 1.0.0 practically depends on 'org.baz' 2.0.0..<3.0.0 because no versions of 'org.bar' match the requirement 1.0.1..<2.0.0 and 'org.bar' 1.0.0 depends on 'org.baz' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: """
                        Dependencies could not be resolved because root depends on 'org.foo' 1.0.0..<2.0.0 and root depends on 'org.bar' 1.0.0..<2.0.0.
                        'org.bar' is incompatible with 'org.foo' because 'org.foo' 1.0.0 depends on 'org.baz' 1.0.0..<2.0.0 and no versions of 'org.foo' match the requirement 1.0.1..<2.0.0.
                        'org.bar' >= 1.0.0 practically depends on 'org.baz' 2.0.0..<3.0.0 because no versions of 'org.bar' match the requirement 1.0.1..<2.0.0 and 'org.bar' 1.0.0 depends on 'org.baz' 2.0.0..<3.0.0.
                        """,
                        severity: .error
                    )
                }
            }
        }
    }

    // mixed graph root --> dep1 scm branch
    //                  --> dep2 registry --> dep1 registry
    func testResolutionMixedRegistryAndSourceControl10() async throws {
        let sandbox: AbsolutePath = AbsolutePath("/tmp/ws/")
        let tmpDirCanonicalPackageLocation = CanonicalPackageLocation(sandbox.pathString)
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    path: "root",
                    targets: [
                        MockTarget(name: "RootTarget", dependencies: [
                            .product(name: "FooProduct", package: "foo"),
                            .product(name: "BarProduct", package: "org.bar"),
                        ]),
                    ],
                    products: [],
                    dependencies: [
                        .sourceControl(url: "https://git/org/foo", requirement: .branch("experiment")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    toolsVersion: .v5_6
                ),
            ],
            packages: [
                MockPackage(
                    name: "FooPackage",
                    url: "https://git/org/foo",
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["experiment"]
                ),
                MockPackage(
                    name: "BarPackage",
                    identity: "org.bar",
                    targets: [
                        MockTarget(name: "BarTarget", dependencies: [
                            .product(name: "FooProduct", package: "org.foo"),
                        ]),
                    ],
                    products: [
                        MockProduct(name: "BarProduct", modules: ["BarTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "FooPackage",
                    identity: "org.foo",
                    alternativeURLs: ["https://git/org/foo"],
                    targets: [
                        MockTarget(name: "FooTarget"),
                    ],
                    products: [
                        MockProduct(name: "FooProduct", modules: ["FooTarget"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .disabled
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        multiple similar targets 'FooTarget' appear in registry package 'org.foo' and source control package 'foo'
                        """),
                        severity: .error
                    )
                }
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        dependency 'org.foo' and dependency 'git/org/foo' both point to the same package identity 'org.foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->org.bar->org.foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->git/org/foo.
                        """),
                        severity: .warning
                    )
                }
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.branch("experiment")))
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
            }
        }

        // reset
        try await workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        dependency 'org.foo' and dependency 'git/org/foo' both point to the same package identity 'org.foo'. The dependencies are introduced through the following chains: (A) \(tmpDirCanonicalPackageLocation)/roots/root->org.bar->org.foo (B) \(tmpDirCanonicalPackageLocation)/roots/root->git/org/foo.
                        """),
                        severity: .warning
                    )
                }
                PackageGraphTester(graph) { result in
                    result.check(roots: "Root")
                    result.check(packages: "org.bar", "org.foo", "Root")
                    result.check(modules: "FooTarget", "BarTarget", "RootTarget")
                    result
                        .checkTarget("RootTarget") { result in result.check(dependencies: "BarProduct", "FooProduct") }
                }
            }

            await workspace.checkManagedDependencies { result in
                result
                    .check(
                        dependency: "org.foo",
                        at: .checkout(.branch("experiment"))
                    ) // we cannot swizzle branch based deps
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
            }
        }
    }

    func testCustomPackageContainerProvider() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let customFS = InMemoryFileSystem()
        // write a manifest
        try customFS.writeFileContents(.root.appending(component: Manifest.filename), bytes: "")
        try ToolsVersionSpecificationWriter.rewriteSpecification(
            manifestDirectory: .root,
            toolsVersion: .current,
            fileSystem: customFS
        )
        // write the sources
        let sourcesDir = AbsolutePath("/Sources")
        let targetDir = sourcesDir.appending("Baz")
        try customFS.createDirectory(targetDir, recursive: true)
        try customFS.writeFileContents(targetDir.appending("file.swift"), bytes: "")

        let bazURL = SourceControlURL("https://example.com/baz")
        let bazPackageReference = PackageReference(
            identity: PackageIdentity(url: bazURL),
            kind: .remoteSourceControl(bazURL)
        )
        let bazContainer = MockPackageContainer(
            package: bazPackageReference,
            dependencies: ["1.0.0": []],
            fileSystem: customFS,
            customRetrievalPath: .root
        )

        let fooPath = sandbox.appending("Foo")
        let fooPackageReference = PackageReference(identity: PackageIdentity(path: fooPath), kind: .root(fooPath))
        let fooContainer = MockPackageContainer(package: fooPackageReference)

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(name: "Foo", dependencies: ["Bar"]),
                        MockTarget(name: "Bar", dependencies: [.product(name: "Baz", package: "baz")]),
                        MockTarget(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(url: bazURL, requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    url: bazURL.absoluteString,
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            customPackageContainerProvider: MockPackageContainerProvider(containers: [fooContainer, bazContainer])
        )

        let deps: [MockDependency] = [
            .sourceControl(url: bazURL, requirement: .exact("1.0.0")),
        ]
        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "Bar", "Baz", "Foo")
                result.check(testModules: "BarTests")
                result.checkTarget("Foo") { result in result.check(dependencies: "Bar") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
                result.checkTarget("BarTests") { result in result.check(dependencies: "Bar") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .custom(Version(1, 0, 0), .root))
        }
    }

    func testRegistryMissingConfigurationErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let registryClient = try makeRegistryClient(
            packageIdentity: .plain("org.foo"),
            packageVersion: "1.0.0",
            configuration: .init(),
            fileSystem: fs
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            registryClient: registryClient
        )

        await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("no registry configured for 'org' scope"), severity: .error)
            }
    }
    }

    func testRegistryReleasesServerErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                releasesRequestHandler: { _, _ in
                    throw StringError("boom")
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal("failed fetching org.foo releases list from http://localhost: boom"),
                        severity: .error
                    )
                }
            }
        }

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                releasesRequestHandler: { _, _ in
                    .serverError()
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed fetching org.foo releases list from http://localhost: server error 500: Internal Server Error"
                        ),
                        severity: .error
                    )
                }
            }
        }
    }

    func testRegistryReleaseChecksumServerErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                versionMetadataRequestHandler: { _, _ in
                    throw StringError("boom")
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed fetching org.foo version 1.0.0 release information from http://localhost: boom"
                        ),
                        severity: .error
                    )
                }
            }
        }

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                versionMetadataRequestHandler: { _, _ in
                    .serverError()
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed fetching org.foo version 1.0.0 release information from http://localhost: server error 500: Internal Server Error"
                        ),
                        severity: .error
                    )
                }
            }
        }
    }

    func testRegistryManifestServerErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                manifestRequestHandler: { _, _ in
                    throw StringError("boom")
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed retrieving org.foo version 1.0.0 manifest from http://localhost: boom"
                        ),
                        severity: .error
                    )
                }
            }
        }

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                manifestRequestHandler: { _, _ in
                    .serverError()
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed retrieving org.foo version 1.0.0 manifest from http://localhost: server error 500: Internal Server Error"
                        ),
                        severity: .error
                    )
                }
            }
        }
    }

    func testRegistryDownloadServerErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ]
        )

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                downloadArchiveRequestHandler: { _, _ in
                    throw StringError("boom")
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed downloading org.foo version 1.0.0 source archive from http://localhost: boom"
                        ),
                        severity: .error
                    )
                }
            }
        }

        do {
            let registryClient = try makeRegistryClient(
                packageIdentity: .plain("org.foo"),
                packageVersion: "1.0.0",
                downloadArchiveRequestHandler: { _, _ in
                    .serverError()
                },
                fileSystem: fs
            )

            try await workspace.closeWorkspace()
            workspace.registryClient = registryClient
            await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .equal(
                            "failed downloading org.foo version 1.0.0 source archive from http://localhost: server error 500: Internal Server Error"
                        ),
                        severity: .error
                    )
                }
            }
        }
    }

    func testRegistryArchiveErrors() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let registryClient = try makeRegistryClient(
            packageIdentity: .plain("org.foo"),
            packageVersion: "1.0.0",
            archiver: MockArchiver(handler: { _, _, _, completion in
                completion(.failure(StringError("boom")))
            }),
            fileSystem: fs
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            registryClient: registryClient
        )

        try await workspace.closeWorkspace()
        workspace.registryClient = registryClient
        await workspace.checkPackageGraphFailure(roots: ["MyPackage"]) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(
                    diagnostic: .regex(
                        "failed extracting '.*[\\\\/]registry[\\\\/]downloads[\\\\/]org[\\\\/]foo[\\\\/]1.0.0.zip' to '.*[\\\\/]registry[\\\\/]downloads[\\\\/]org[\\\\/]foo[\\\\/]1.0.0': boom"
                    ),
                    severity: .error
                )
            }
        }
    }

    func testRegistryMetadata() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let registryURL = URL("https://packages.example.com")
        var registryConfiguration = RegistryConfiguration()
        registryConfiguration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        registryConfiguration.security = RegistryConfiguration.Security()
        registryConfiguration.security!.default.signing = RegistryConfiguration.Security.Signing()
        registryConfiguration.security!.default.signing!.onUnsigned = .silentAllow

        let registryClient = try makeRegistryClient(
            packageIdentity: .plain("org.foo"),
            packageVersion: "1.5.1",
            targets: ["Foo"],
            configuration: registryConfiguration,
            fileSystem: fs
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            registryClient: registryClient
        )

        // for mock manifest loader to work with an actual registry download
        // we populate the mock manifest with a pointer to the correct download location
        let defaultLocations = try Workspace.Location(forRootPackage: sandbox, fileSystem: fs)
        let packagePath = defaultLocations.registryDownloadDirectory.appending(components: ["org", "foo", "1.5.1"])
        workspace.manifestLoader.manifests[.init(url: "org.foo", version: "1.5.1")] =
            try Manifest.createManifest(
                displayName: "Foo",
                path: packagePath.appending(component: Manifest.filename),
                packageKind: .registry("org.foo"),
                packageIdentity: .plain("Foo"),
                packageLocation: "org.foo",
                toolsVersion: .current,
                products: [
                    .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                ],
                targets: [
                    .init(name: "Foo"),
                ]
            )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                guard let foo = result.find(package: "org.foo") else {
                    return XCTFail("missing package")
                }
                XCTAssertNotNil(foo.registryMetadata, "expecting registry metadata")
                XCTAssertEqual(foo.registryMetadata?.source, .registry(registryURL))
                XCTAssertMatch(foo.registryMetadata?.metadata.description, .contains("org.foo"))
                XCTAssertMatch(foo.registryMetadata?.metadata.readmeURL?.absoluteString, .contains("org.foo"))
                XCTAssertMatch(foo.registryMetadata?.metadata.licenseURL?.absoluteString, .contains("org.foo"))
            }
        }

        await workspace.checkManagedDependencies { result in
            result.check(dependency: "org.foo", at: .registryDownload("1.5.1"))
        }
    }

    func testRegistryDefaultRegistryConfiguration() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        var configuration = RegistryConfiguration()
        configuration.security = .testDefault

        let registryClient = try makeRegistryClient(
            packageIdentity: .plain("org.foo"),
            packageVersion: "1.0.0",
            configuration: configuration,
            fileSystem: fs
        )

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0"]
                ),
            ],
            registryClient: registryClient,
            defaultRegistry: .init(
                url: "http://some-registry.com",
                supportsAvailability: false
            )
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                XCTAssertNotNil(result.find(package: "org.foo"), "missing package")
            }
        }
    }

    // MARK: - Expected signing entity verification

    func createBasicRegistryWorkspace(
        metadata: [String: RegistryReleaseMetadata],
        mirrors: DependencyMirrors? = nil
    ) async throws -> MockWorkspace {
        // let sandbox = AbsolutePath.root.appending("swiftpm-tests-can-be-deleted/tmp/ws")
        let sandbox = AbsolutePath.root.appending(components: ["swiftpm-tests-can-be-deleted", "tmp", "ws"])
        let fs = InMemoryFileSystem()

        return try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "MyPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget1",
                            dependencies: [
                                .product(name: "Foo", package: "org.foo"),
                            ]
                        ),
                        MockTarget(
                            name: "MyTarget2",
                            dependencies: [
                                .product(name: "Bar", package: "org.bar"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["MyTarget1", "MyTarget2"]),
                    ],
                    dependencies: [
                        .registry(identity: "org.foo", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "org.bar", requirement: .upToNextMajor(from: "2.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Foo",
                    identity: "org.foo",
                    metadata: metadata["org.foo"],
                    targets: [
                        MockTarget(name: "Foo"),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo"]),
                    ],
                    versions: ["1.0.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0", "1.5.0", "1.5.1"]
                ),
                MockPackage(
                    name: "Bar",
                    identity: "org.bar",
                    metadata: metadata["org.bar"],
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["2.0.0", "2.1.0", "2.2.0"]
                ),
                MockPackage(
                    name: "BarMirror",
                    url: "https://scm.com/org/bar-mirror",
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["2.0.0", "2.1.0", "2.2.0"]
                ),
                MockPackage(
                    name: "BarMirrorRegistry",
                    identity: "ecorp.bar",
                    metadata: metadata["ecorp.bar"],
                    targets: [
                        MockTarget(name: "Bar"),
                    ],
                    products: [
                        MockProduct(name: "Bar", modules: ["Bar"]),
                    ],
                    versions: ["2.0.0", "2.1.0", "2.2.0"]
                ),
            ],
            mirrors: mirrors
        )
    }

    func testSigningEntityVerification_SignedCorrectly() async throws {
        let actualMetadata = RegistryReleaseMetadata.createWithSigningEntity(
            .recognized(
                type: "adp",
                commonName: "John Doe",
                organization: "Example Corp",
                identity: "XYZ"
            )
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: ["org.bar": actualMetadata])

        try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
            PackageIdentity.plain("org.bar"): XCTUnwrap(actualMetadata.signature?.signedBy),
        ]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
    }

    func testSigningEntityVerification_SignedIncorrectly() async throws {
        let actualMetadata = RegistryReleaseMetadata.createWithSigningEntity(
            .recognized(
                type: "adp",
                commonName: "John Doe",
                organization: "Example Corp",
                identity: "XYZ"
            )
        )
        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "John Doe",
            organization: "Evil Corp",
            identity: "ABC"
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: ["org.bar": actualMetadata])

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("org.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.mismatchedSigningEntity(_, let expected, let actual) {
            XCTAssertEqual(actual, actualMetadata.signature?.signedBy)
            XCTAssertEqual(expected, expectedSigningEntity)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSigningEntityVerification_Unsigned() async throws {
        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "Jane Doe",
            organization: "Example Corp",
            identity: "XYZ"
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: [:])

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("org.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.unsigned(_, let expected) {
            XCTAssertEqual(expected, expectedSigningEntity)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSigningEntityVerification_NotFound() async throws {
        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "Jane Doe",
            organization: "Example Corp",
            identity: "XYZ"
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: [:])

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("foo.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.expectedIdentityNotFound(let package) {
            XCTAssertEqual(package.description, "foo.bar")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSigningEntityVerification_MirroredSignedCorrectly() async throws {
        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "ecorp.bar", for: "org.bar")

        let actualMetadata = RegistryReleaseMetadata.createWithSigningEntity(
            .recognized(
                type: "adp",
                commonName: "John Doe",
                organization: "Example Corp",
                identity: "XYZ"
            )
        )

        let workspace = try await createBasicRegistryWorkspace(
            metadata: ["ecorp.bar": actualMetadata],
            mirrors: mirrors
        )

        try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
            PackageIdentity.plain("org.bar"): XCTUnwrap(actualMetadata.signature?.signedBy),
        ]) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTester(graph) { result in
                XCTAssertNotNil(result.find(package: "ecorp.bar"), "missing package")
                XCTAssertNil(result.find(package: "org.bar"), "unexpectedly present package")
            }
        }
    }

    func testSigningEntityVerification_MirrorSignedIncorrectly() async throws {
        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "ecorp.bar", for: "org.bar")

        let actualMetadata = RegistryReleaseMetadata.createWithSigningEntity(
            .recognized(
                type: "adp",
                commonName: "John Doe",
                organization: "Example Corp",
                identity: "XYZ"
            )
        )
        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "John Doe",
            organization: "Evil Corp",
            identity: "ABC"
        )

        let workspace = try await createBasicRegistryWorkspace(
            metadata: ["ecorp.bar": actualMetadata],
            mirrors: mirrors
        )

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("org.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.mismatchedSigningEntity(_, let expected, let actual) {
            XCTAssertEqual(actual, actualMetadata.signature?.signedBy)
            XCTAssertEqual(expected, expectedSigningEntity)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSigningEntityVerification_MirroredUnsigned() async throws {
        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "ecorp.bar", for: "org.bar")

        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "Jane Doe",
            organization: "Example Corp",
            identity: "XYZ"
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: [:], mirrors: mirrors)

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("org.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.unsigned(_, let expected) {
            XCTAssertEqual(expected, expectedSigningEntity)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSigningEntityVerification_MirroredToSCM() async throws {
        let mirrors = try DependencyMirrors()
        try mirrors.set(mirror: "https://scm.com/org/bar-mirror", for: "org.bar")

        let expectedSigningEntity: RegistryReleaseMetadata.SigningEntity = .recognized(
            type: "adp",
            commonName: "Jane Doe",
            organization: "Example Corp",
            identity: "XYZ"
        )

        let workspace = try await createBasicRegistryWorkspace(metadata: [:], mirrors: mirrors)

        do {
            try await workspace.checkPackageGraph(roots: ["MyPackage"], expectedSigningEntities: [
                PackageIdentity.plain("org.bar"): expectedSigningEntity,
            ]) { _, _ in }
            XCTFail("should not succeed")
        } catch Workspace.SigningError.expectedSignedMirroredToSourceControl(_, let expected) {
            XCTAssertEqual(expected, expectedSigningEntity)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTraitConfigurationExists_NoDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    // Trait1 enabled; should be present in list of dependencies
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    // Trait2 disabled; should generate unused dependency warning
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: ["Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Only Trait1 is configured to be enabled; since `pruneDependencies` is false
            // by default, there will be unused dependencies present
            traitConfiguration: .init(enabledTraits: ["Trait1"], enableAllTraits: false)
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Boo")
                result.check(modules: "Bar", "Baz", "Boo", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .contains("dependency 'boo' is not used by any target"), severity: .warning)
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testTraitConfigurationExists_WithDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration overrides default traits; all traits set to enabled.
            traitConfiguration: .init(enabledTraits: [], enableAllTraits: true),
            // With this configuration, no dependencies are unused so nothing should be pruned
            // despite the `pruneDependencies` flag being set to true.
            pruneDependencies: true
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Boo")
                result.check(modules: "Bar", "Baz", "Boo", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz", "Boo") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "boo", at: .checkout(.version("1.0.0")))
        }
    }

    func testTraitConfiguration_WithPrunedDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        // unused dependency due to trait guarding; should be omitted
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                        // unused dependency; should be omitted
                        .sourceControl(path: "./Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration overrides default traits; no traits enabled
            traitConfiguration: .init(enabledTraits: [], enableAllTraits: false),
            pruneDependencies: true
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "Bar", "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: []) }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testNoTraitConfiguration_WithDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"]) // Baz dependency guarded by traits.
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]), // Baz dependency not guarded by traits.
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTester(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Boo", "Foo")
                result.check(modules: "Bar", "Baz", "Boo", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Boo") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testInvalidTrait_WhenParentPackageEnablesTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0"), traits: ["TraitNotFound"]),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    traits: ["TraitFound"],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"]), traits: ["TraitFound"]),
        ]

        try await workspace.checkPackageGraphFailure(roots: ["Foo"], deps: deps) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("Trait 'TraitNotFound' enabled by parent package 'foo' is not declared by package 'Baz'. The available traits declared by this package are: TraitFound."), severity: .error)
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testInvalidTraitConfiguration_ForRootPackage() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0"), traits: ["TraitFound"]),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    traits: ["TraitFound"],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration containing trait that isn't defined in the root package.
            traitConfiguration: .enabledTraits(["TraitNotFound"]),
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"]), traits: ["TraitFound"]),
        ]

        try await workspace.checkPackageGraphFailure(roots: ["Foo"], deps: deps) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("Trait 'TraitNotFound' is not declared by package 'Foo'. The available traits declared by this package are: Trait1, Trait2, default."), severity: .error)
            }
        }
    }

    func makeRegistryClient(
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        targets: [String] = [],
        configuration: PackageRegistry.RegistryConfiguration? = .none,
        identityResolver: IdentityResolver? = .none,
        fingerprintStorage: PackageFingerprintStorage? = .none,
        fingerprintCheckingMode: FingerprintCheckingMode = .strict,
        signingEntityStorage: PackageSigningEntityStorage? = .none,
        signingEntityCheckingMode: SigningEntityCheckingMode = .strict,
        authorizationProvider: AuthorizationProvider? = .none,
        releasesRequestHandler: HTTPClient.Implementation? = .none,
        versionMetadataRequestHandler: HTTPClient.Implementation? = .none,
        manifestRequestHandler: HTTPClient.Implementation? = .none,
        downloadArchiveRequestHandler: HTTPClient.Implementation? = .none,
        archiver: Archiver? = .none,
        fileSystem: FileSystem
    ) throws -> RegistryClient {
        let jsonEncoder = JSONEncoder.makeWithDefaults()

        guard let identity = packageIdentity.registry else {
            throw StringError("Invalid package identifier: '\(packageIdentity)'")
        }

        let configuration = configuration ?? {
            var configuration = PackageRegistry.RegistryConfiguration()
            configuration.defaultRegistry = .init(url: "http://localhost", supportsAvailability: false)
            configuration.security = .testDefault
            return configuration
        }()

        let releasesRequestHandler = releasesRequestHandler ?? { _, _ in
            let metadata = RegistryClient.Serialization.PackageMetadata(
                releases: [packageVersion.description: .init(url: .none, problem: .none)]
            )
            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/json",
                ],
                body: try! jsonEncoder.encode(metadata)
            )
        }

        let versionMetadataRequestHandler = versionMetadataRequestHandler ?? { _, _ in
            let metadata = RegistryClient.Serialization.VersionMetadata(
                id: packageIdentity.description,
                version: packageVersion.description,
                resources: [
                    .init(
                        name: "source-archive",
                        type: "application/zip",
                        checksum: "",
                        signing: nil
                    ),
                ],
                metadata: .init(
                    description: "package \(identity) description",
                    licenseURL: "/\(identity)/license",
                    readmeURL: "/\(identity)/readme"
                ),
                publishedAt: nil
            )
            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/json",
                ],
                body: try! jsonEncoder.encode(metadata)
            )
        }

        let manifestRequestHandler = manifestRequestHandler ?? { _, _ in
            HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "text/x-swift",
                ],
                body: Data("// swift-tools-version:\(ToolsVersion.current)".utf8)
            )
        }

        let downloadArchiveRequestHandler = downloadArchiveRequestHandler ?? { request, _ in
            switch request.kind {
            case .download(let fileSystem, let destination):
                // creates a dummy zipfile which is required by the archiver step
                try! fileSystem.createDirectory(destination.parentDirectory, recursive: true)
                try! fileSystem.writeFileContents(destination, string: "")
            default:
                preconditionFailure("invalid request")
            }

            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/zip",
                ],
                body: Data("".utf8)
            )
        }

        let archiver = archiver ?? MockArchiver(handler: { _, _, to, completion in
            do {
                let packagePath = to.appending("top")
                try fileSystem.createDirectory(packagePath, recursive: true)
                try fileSystem.writeFileContents(packagePath.appending(component: Manifest.filename), bytes: [])
                try ToolsVersionSpecificationWriter.rewriteSpecification(
                    manifestDirectory: packagePath,
                    toolsVersion: .current,
                    fileSystem: fileSystem
                )
                for target in targets {
                    try fileSystem.createDirectory(
                        packagePath.appending(components: "Sources", target),
                        recursive: true
                    )
                    try fileSystem.writeFileContents(
                        packagePath.appending(components: ["Sources", target, "file.swift"]),
                        bytes: []
                    )
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })
        let fingerprintStorage = fingerprintStorage ?? MockPackageFingerprintStorage()
        let signingEntityStorage = signingEntityStorage ?? MockPackageSigningEntityStorage()

        return RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            skipSignatureValidation: false,
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode,
            authorizationProvider: authorizationProvider,
            customHTTPClient: HTTPClient(configuration: .init(), implementation: { request, progress in
                switch request.url.path {
                // request to get package releases
                case "/\(identity.scope)/\(identity.name)":
                    return try await releasesRequestHandler(request, progress)
                // request to get package version metadata
                case "/\(identity.scope)/\(identity.name)/\(packageVersion)":
                    return try await versionMetadataRequestHandler(request, progress)
                // request to get package manifest
                case "/\(identity.scope)/\(identity.name)/\(packageVersion)/Package.swift":
                    return try await manifestRequestHandler(request, progress)
                // request to get download the version source archive
                case "/\(identity.scope)/\(identity.name)/\(packageVersion).zip":
                    return try await downloadArchiveRequestHandler(request, progress)
                default:
                    throw StringError("unexpected url \(request.url)")
                }
            }),
            customArchiverProvider: { _ in archiver },
            delegate: .none,
            checksumAlgorithm: MockHashAlgorithm()
        )
    }
}

func createDummyXCFramework(fileSystem: FileSystem, path: AbsolutePath, name: String) throws {
    let path = path.appending("\(name).xcframework")
    try fileSystem.createDirectory(path, recursive: true)
    try fileSystem.writeFileContents(
        path.appending("info.plist"),
        string: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AvailableLibraries</key>
            <array></array>
            <key>CFBundlePackageType</key>
            <string>XFWK</string>
            <key>XCFrameworkFormatVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
    )
}

func createDummyArtifactBundle(fileSystem: FileSystem, path: AbsolutePath, name: String) throws {
    let path = path.appending("\(name).artifactbundle")
    try fileSystem.createDirectory(path, recursive: true)
    try fileSystem.writeFileContents(
        path.appending("info.json"),
        string: """
        {
            "schemaVersion": "1.0",
            "artifacts": {}
        }
        """
    )
}

struct DummyError: LocalizedError, Equatable {
    public var errorDescription: String? { "dummy error" }
}

extension RegistryReleaseMetadata {
    fileprivate static func createWithSigningEntity(
        _ entity: RegistryReleaseMetadata
            .SigningEntity
    ) -> RegistryReleaseMetadata {
        self.init(
            source: .registry(URL(string: "https://example.com")!),
            metadata: .init(scmRepositoryURLs: nil),
            signature: .init(signedBy: entity, format: "xyz", value: [])
        )
    }
}
