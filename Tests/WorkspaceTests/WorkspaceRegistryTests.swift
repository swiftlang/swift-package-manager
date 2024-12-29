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
import PackageModel
import PackageRegistry
import PackageSigning
@testable import Workspace
import XCTest

import struct TSCUtility.Version

final class WorkspaceRegistryTests: XCTestCase {
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
        workspace.checkManagedDependencies { result in
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
        workspace.checkManagedDependencies { result in
            result.check(dependency: "bar-mirror", at: .checkout(.version("1.5.0")))
            result.check(dependency: "org.baz", at: .registryDownload("1.6.0"))
            result.check(notPresent: "org.bar")
        }
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

        workspace.checkManagedDependencies { result in
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

        workspace.checkManagedDependencies { result in
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: "'root' dependency on 'org.foo' conflicts with dependency on 'https://git/org/foo' which has the same identity 'org.foo'",
                        severity: .error
                    )
                }
            }
        }

        // reset
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            // TODO: this error message should be improved
            try await workspace.checkPackageGraph(roots: ["root"]) { _, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: "'root' dependency on 'org.foo' conflicts with dependency on 'org.foo' which has the same identity 'org.foo'",
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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'bar' dependency on 'org.foo' conflicts with dependency on 'https://git/org/foo' which has the same identity 'org.foo'.
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.1.0")))
                result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.1.0"))
                result.check(dependency: "bar", at: .checkout(.version("1.1.0")))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'org.bar' dependency on 'org.foo' conflicts with dependency on 'https://git/org/foo' which has the same identity 'org.foo'.
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.version("1.2.0")))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'org.bar' dependency on 'https://git/org/foo' conflicts with dependency on 'org.foo' which has the same identity 'org.foo'.
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.2.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'org.foo' dependency on 'https://git/org/baz' conflicts with dependency on 'org.baz' which has the same identity 'org.baz'.
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
                result.check(dependency: "org.baz", at: .registryDownload("1.1.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

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

            workspace.checkManagedDependencies { result in
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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

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
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .identity

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'org.bar' dependency on 'org.foo' conflicts with dependency on 'https://git/org/foo' which has the same identity 'org.foo'.
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

            workspace.checkManagedDependencies { result in
                result.check(dependency: "org.foo", at: .checkout(.branch("experiment")))
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
            }
        }

        // reset
        try workspace.closeWorkspace()

        do {
            workspace.sourceControlToRegistryDependencyTransformation = .swizzle

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                testDiagnostics(diagnostics) { result in
                    result.check(
                        diagnostic: .contains("""
                        'org.bar' dependency on 'org.foo' conflicts with dependency on 'https://git/org/foo' which has the same identity 'org.foo'.
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

            workspace.checkManagedDependencies { result in
                result
                    .check(
                        dependency: "org.foo",
                        at: .checkout(.branch("experiment"))
                    ) // we cannot swizzle branch based deps
                result.check(dependency: "org.bar", at: .registryDownload("1.0.0"))
            }
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

            try workspace.closeWorkspace()
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

        try workspace.closeWorkspace()
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

        workspace.checkManagedDependencies { result in
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
        let sandbox = AbsolutePath("/tmp/ws/")
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
            customHTTPClient: HTTPClient(implementation: { request, progress in
                switch request.url.path {
                // request to get package releases
                case "/\(identity.scope)/\(identity.name)":
                    try await releasesRequestHandler(request, progress)
                // request to get package version metadata
                case "/\(identity.scope)/\(identity.name)/\(packageVersion)":
                    try await versionMetadataRequestHandler(request, progress)
                // request to get package manifest
                case "/\(identity.scope)/\(identity.name)/\(packageVersion)/Package.swift":
                    try await manifestRequestHandler(request, progress)
                // request to get download the version source archive
                case "/\(identity.scope)/\(identity.name)/\(packageVersion).zip":
                    try await downloadArchiveRequestHandler(request, progress)
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

extension RegistryReleaseMetadata {
    fileprivate static func createWithSigningEntity(
        _ entity: RegistryReleaseMetadata.SigningEntity
    ) -> RegistryReleaseMetadata {
        self.init(
            source: .registry(URL(string: "https://example.com")!),
            metadata: .init(scmRepositoryURLs: nil),
            signature: .init(signedBy: entity, format: "xyz", value: [])
        )
    }
}
