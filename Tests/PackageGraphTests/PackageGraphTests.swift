/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageGraph
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class PackageGraphTests: XCTestCase {

    func testBasic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/FooDep/source.swift",
            "/Foo/Tests/FooTests/source.swift",
            "/Bar/source.swift",
            "/Baz/Sources/Baz/source.swift",
            "/Baz/Tests/BazTests/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["FooDep"]),
                        TargetDescription(name: "FooDep", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init("/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"], path: "./")
                    ]),
                Manifest.createRootManifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["Bar"]),
                        TargetDescription(name: "BazTests", dependencies: ["Baz"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo", "Baz")
            result.check(targets: "Bar", "Foo", "Baz", "FooDep")
            result.check(testModules: "BazTests")
            result.checkTarget("Foo") { result in result.check(dependencies: "FooDep") }
            result.checkTarget("Bar") { result in result.check(dependencies: "Foo") }
            result.checkTarget("Baz") { result in result.check(dependencies: "Bar") }
        }

        let fooPackage = try XCTUnwrap(g.packages.first{ $0.identity == .plain("Foo") })
        let fooTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "Foo" })
        let fooDepTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "FooDep" })
        XCTAssert(g.package(for: fooTarget) == fooPackage)
        XCTAssert(g.package(for: fooDepTarget) == fooPackage)
        let barPackage = try XCTUnwrap(g.packages.first{ $0.identity == .plain("Bar") })
        let barTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "Bar" })
        XCTAssert(g.package(for: barTarget) == barPackage)
    }

    func testProductDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Source/Bar/source.swift",
            "/Bar/Source/CBar/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
                        ProductDescription(name: "CBar", type: .library(.automatic), targets: ["CBar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["CBar"]),
                        TargetDescription(name: "CBar", type: .system),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo")
            result.check(targets: "Bar", "CBar", "Foo")
            result.checkTarget("Foo") { result in result.check(dependencies: "Bar", "CBar") }
            result.checkTarget("Bar") { result in result.check(dependencies: "CBar") }
        }
    }

    func testCycle() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Baz/Sources/Baz/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init("/Baz"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Baz"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Baz", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["Bar"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "cyclic dependency declaration found: Foo -> Bar -> Baz -> Bar", severity: .error)
        }
    }

    func testCycle2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Baz/Sources/Baz/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "cyclic dependency declaration found: Foo -> Foo", severity: .error)
        }
    }

    // Make sure there is no error when we reference Test targets in a package and then
    // use it as a dependency to another package. SR-2353
    func testTestTargetDeclInExternalPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Tests/FooTests/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Bar/Tests/BarTests/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init("/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo")
            result.check(targets: "Bar", "Foo")
            result.check(testModules: "BarTests")
        }
    }

    func testDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Bar/source.swift",
            "/Bar/Sources/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createRootManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Bar' in: 'bar', 'foo'", severity: .error)
        }
    }

    func testMultipleDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/First/source.swift",
            "/Third/Sources/First/source.swift",
            "/Second/Sources/First/source.swift",
            "/First/Sources/First/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Third",
                    path: .init("/Third"),
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Second",
                    path: .init("/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createRootManifest(
                    name: "First",
                    path: .init("/First"),
                    dependencies: [
                        .localSourceControl(path: .init("/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "First", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'First' in: 'first', 'fourth', 'second', 'third'", severity: .error)
        }
    }

    func testSeveralDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/Bar/source.swift",
            "/Third/Sources/Bar/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/First/Sources/Foo/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Third",
                    path: .init("/Third"),
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Second",
                    path: .init("/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createRootManifest(
                    name: "First",
                    path: .init("/First"),
                    dependencies: [
                        .localSourceControl(path: .init("/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Bar' in: 'fourth', 'third'", severity: .error)
            result.check(diagnostic: "multiple targets named 'Foo' in: 'first', 'second'", severity: .error)
        }
    }

    func testNestedDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/First/source.swift",
            "/Third/Sources/Third/source.swift",
            "/Second/Sources/Second/source.swift",
            "/First/Sources/First/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Third",
                    path: .init("/Third"),
                    dependencies: [
                        .localSourceControl(path: .init("/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Third"])
                    ],
                    targets: [
                        TargetDescription(name: "Third", dependencies: ["Fourth"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Second",
                    path: .init("/Second"),
                    dependencies: [
                        .localSourceControl(path: .init("/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Second"])
                    ],
                    targets: [
                        TargetDescription(name: "Second", dependencies: ["Third"]),
                    ]),
                Manifest.createRootManifest(
                    name: "First",
                    path: .init("/First"),
                    dependencies: [
                        .localSourceControl(path: .init("/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First", dependencies: ["Second"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'First' in: 'first', 'fourth'", severity: .error)
        }
    }

    func testEmptyDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/source.txt"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "Source files for target Bar should be located under /Bar/Sources/Bar",
                severity: .warning
            )
            result.check(
                diagnostic: "target 'Bar' referenced in product 'Bar' is empty",
                severity: .error
            )
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: ["Barx"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found.",
                severity: .error
            )
        }
    }

    func testProductDependencyDeclaredInSamePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/src.swift",
            "/Foo/Tests/FooTests/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["FooTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Foo' is declared in the same package 'foo' and can't be used as a dependency for target 'FooTests'.",
                severity: .error
            )
        }
    }

    func testExecutableTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/XYZ/Sources/XYZ/main.swift",
                                    "/XYZ/Tests/XYZTests/tests.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "XYZ",
                    path: .init("/XYZ"),
                    targets: [
                        TargetDescription(name: "XYZ", dependencies: [], type: .executable),
                        TargetDescription(name: "XYZTests", dependencies: ["XYZ"], type: .test),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testSameProductAndTargetNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/src.swift",
            "/Foo/Tests/FooTests/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testProductDependencyNotFoundWithName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx", package: "Bar")]),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found in package 'Bar'.",
                severity: .error
            )
        }
    }

    func testProductDependencyNotFoundWithNoName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx")]),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found.",
                severity: .error
            )
        }
    }

    func testProductDependencyNotFoundImprovedDiagnostic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/BarLib/bar.swift",
            "/BizPath/Sources/Biz/biz.swift",
            "/FizPath/Sources/FizLib/fiz.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .branch("master")),
                        .localSourceControl(path: .init("/BizPath"), requirement: .exact("1.2.3")),
                        .localSourceControl(path: .init("/FizPath"), requirement: .upToNextMajor(from: "1.1.2")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLib", "Biz", "FizLib"]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "BarLib", type: .library(.automatic), targets: ["BarLib"])
                    ],
                    targets: [
                        TargetDescription(name: "BarLib"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    name: "Biz",
                    path: .init("/BizPath"),
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    name: "Fiz",
                    path: .init("/FizPath"),
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "FizLib", type: .library(.automatic), targets: ["FizLib"])
                    ],
                    targets: [
                        TargetDescription(name: "FizLib"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.checkUnordered(
                diagnostic: """
                dependency 'BarLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "BarLib", package: "Bar")'
                """,
                severity: .error
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'Biz' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Biz", package: "BizPath")'
                """,
                severity: .error
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'FizLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "FizLib", package: "FizPath")'
                """,
                severity: .error
            )
        }
    }

    func testPackageNameValidationInProductTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(deprecatedName: "UnBar", path: .init("/Bar"), requirement: .branch("master")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "BarProduct", package: "UnBar")]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    name: "UnBar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "BarProduct", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        // Expect no diagnostics.
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testUnusedDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift",
            "/Biz/Sources/Biz/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Baz"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Biz"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Biz",
                    path: .init("/Biz"),
                    products: [
                        ProductDescription(name: "biz", type: .executable, targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "BarLibrary", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "dependency 'baz' is not used by any target", severity: .warning)
            #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
            result.check(diagnostic: "dependency 'biz' is not used by any target", severity: .warning)
            #endif
        }
    }

    func testUnusedDependency2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/module.modulemap",
            "/Bar/Sources/Bar/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init("/Foo"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Foo",
                    path: .init("/Foo")
                ),
            ],
            observabilityScope: observability.topScope
        )

        // We don't expect any unused dependency diagnostics from a system module package.
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testDuplicateInterPackageTargetNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Start/Sources/Foo/foo.swift",
            "/Start/Sources/Bar/bar.swift",
            "/Dep1/Sources/Baz/baz.swift",
            "/Dep2/Sources/Foo/foo.swift",
            "/Dep2/Sources/Bam/bam.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Start",
                    path: .init("/Start"),
                    dependencies: [
                        .localSourceControl(path: .init("/Dep1"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Dep1",
                    path: .init("/Dep1"),
                    dependencies: [
                        .localSourceControl(path: .init("/Dep2"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["FooLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Dep2",
                    path: .init("/Dep2"),
                    products: [
                        ProductDescription(name: "FooLibrary", type: .library(.automatic), targets: ["Foo"]),
                        ProductDescription(name: "BamLibrary", type: .library(.automatic), targets: ["Bam"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bam"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Foo' in: 'dep2', 'start'", severity: .error)
        }
    }

    func testDuplicateProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/Baz"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple products named 'Bar' in: 'bar', 'baz'", severity: .error)
        }
    }

    func testUnsafeFlags() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Foo/Sources/Foo2/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Bar/Sources/Bar2/bar.swift",
            "/Bar/Sources/Bar3/bar.swift",
            "/Bar/Sources/TransitiveBar/bar.swift",
            "<end>"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar", "Bar2", "Bar3"]),
                        ProductDescription(name: "TransitiveBar", type: .library(.automatic), targets: ["TransitiveBar"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Bar",
                            settings: [
                                .init(tool: .swift, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                                .init(tool: .c, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar2",
                            settings: [
                                .init(tool: .swift, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                                .init(tool: .c, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar3"
                        ),
                        TargetDescription(
                            name: "TransitiveBar",
                            dependencies: ["Bar2"]
                        ),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertEqual(observability.diagnostics.count, 3)
        testDiagnostics(observability.diagnostics) { result in
            var expectedMetadata = ObservabilityMetadata()
            expectedMetadata.targetName = "Foo2"
            let diagnostic1 = result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'TransitiveBar' contains unsafe build flags"), severity: .error)
            XCTAssertEqual(diagnostic1?.metadata?.targetName, "Foo2")
            let diagnostic2 = result.checkUnordered(diagnostic: .contains("the target 'Bar' in product 'Bar' contains unsafe build flags"), severity: .error)
            XCTAssertEqual(diagnostic2?.metadata?.targetName, "Foo")
            let diagnostic3 = result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'Bar' contains unsafe build flags"), severity: .error)
            XCTAssertEqual(diagnostic3?.metadata?.targetName, "Foo")
        }
    }

    func testConditionalTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Bar/source.swift",
            "/Foo/Sources/Baz/source.swift",
            "/Biz/Sources/Biz/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .fileSystem(path: .init("/Biz")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [
                            .target(name: "Bar", condition: PackageConditionDescription(
                                platformNames: ["linux"],
                                config: nil
                            )),
                            .byName(name: "Baz", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                            .product(name: "Biz", package: "Biz", condition: PackageConditionDescription(
                                platformNames: ["watchos", "ios"],
                                config: "release"
                            ))
                        ]),
                        TargetDescription(name: "Bar"),
                        TargetDescription(name: "Baz"),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    name: "Biz",
                    path: .init("/Biz"),
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(graph) { result in
            result.check(targets: "Foo", "Bar", "Baz", "Biz")
            result.checkTarget("Foo") { result in
                result.check(dependencies: "Bar", "Baz", "Biz")
                result.checkDependency("Bar") { result in
                    result.checkConditions(satisfy: .init(platform: .linux, configuration: .debug))
                    result.checkConditions(satisfy: .init(platform: .linux, configuration: .release))
                    result.checkConditions(dontSatisfy: .init(platform: .macOS, configuration: .release))
                }
                result.checkDependency("Baz") { result in
                    result.checkConditions(satisfy: .init(platform: .watchOS, configuration: .debug))
                    result.checkConditions(satisfy: .init(platform: .tvOS, configuration: .debug))
                    result.checkConditions(dontSatisfy: .init(platform: .tvOS, configuration: .release))
                }
                result.checkDependency("Biz") { result in
                    result.checkConditions(satisfy: .init(platform: .watchOS, configuration: .release))
                    result.checkConditions(satisfy: .init(platform: .iOS, configuration: .release))
                    result.checkConditions(dontSatisfy: .init(platform: .iOS, configuration: .debug))
                    result.checkConditions(dontSatisfy: .init(platform: .macOS, configuration: .release))
                }
            }
        }
    }

    func testUnreachableProductsSkipped() throws {
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        #else
        try XCTSkipIf(true)
        #endif

        let fs = InMemoryFileSystem(emptyFiles:
            "/Root/Sources/Root/Root.swift",
            "/Immediate/Sources/ImmediateUsed/ImmediateUsed.swift",
            "/Immediate/Sources/ImmediateUnused/ImmediateUnused.swift",
            "/Transitive/Sources/TransitiveUsed/TransitiveUsed.swift",
            "/Transitive/Sources/TransitiveUnused/TransitiveUnused.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Root",
                    path: .init("/Root"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init("/Immediate"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Root", dependencies: [
                            .product(name: "ImmediateUsed", package: "Immediate")
                        ]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "Immediate",
                    path: .init("/Immediate"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(
                            path: .init("/Transitive"),
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .localSourceControl(
                            path: .init("/Nonexistent"),
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(name: "ImmediateUsed", type: .library(.automatic), targets: ["ImmediateUsed"]),
                        ProductDescription(name: "ImmediateUnused", type: .library(.automatic), targets: ["ImmediateUnused"])
                    ],
                    targets: [
                        TargetDescription(name: "ImmediateUsed", dependencies: [
                            .product(name: "TransitiveUsed", package: "Transitive")
                        ]),
                        TargetDescription(name: "ImmediateUnused", dependencies: [
                            .product(name: "TransitiveUnused", package: "Transitive"),
                            .product(name: "Nonexistent", package: "Nonexistent")
                        ]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "Transitive",
                    path: .init("/Transitive"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(
                            path: .init("/Nonexistent"),
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(name: "TransitiveUsed", type: .library(.automatic), targets: ["TransitiveUsed"])
                    ],
                    targets: [
                        TargetDescription(name: "TransitiveUsed"),
                        TargetDescription(name: "TransitiveUnused", dependencies: [
                            .product(name: "Nonexistent", package: "Nonexistent")
                        ])
                ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testPinsStoreIsResilientAgainstDupes() throws {
        let json = """
              {
                "version": 1,
                "object": {
                  "pins": [
                    {
                      "package": "Yams",
                      "repositoryURL": "https://github.com/jpsim/yams",
                      "state": {
                        "branch": null,
                        "revision": "b08dba4bcea978bf1ad37703a384097d3efce5af",
                        "version": "1.0.2"
                      }
                    },
                    {
                      "package": "Yams",
                      "repositoryURL": "https://github.com/jpsim/yams",
                      "state": {
                        "branch": null,
                        "revision": "b08dba4bcea978bf1ad37703a384097d3efce5af",
                        "version": "1.0.2"
                      }
                    }
                  ]
                }
              }
        """

        let fs = InMemoryFileSystem(files: ["/pins": ByteString(encodingAsUTF8: json)])

        XCTAssertThrows(StringError("Package.resolved file is corrupted or malformed; fix or delete the file to continue: duplicated entry for package \"yams\""), {
            _ = try PinsStore(pinsFile: AbsolutePath("/pins"), workingDirectory: .root, fileSystem: fs, mirrors: .init())
        })
    }

    func testResolutionDeterminism() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles: [
                "/A/Sources/A/A.swift",
                "/B/Sources/B/B.swift",
                "/C/Sources/C/C.swift",
                "/D/Sources/D/D.swift",
                "/E/Sources/E/E.swift",
                "/F/Sources/F/F.swift",
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/C"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/D"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/E"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/F"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "A", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "B",
                    path: .init("/B"),
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"])
                    ],
                    targets: [
                        TargetDescription(name: "B"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "C",
                    path: .init("/C"),
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"])
                    ],
                    targets: [
                        TargetDescription(name: "C"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "D",
                    path: .init("/D"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"])
                    ],
                    targets: [
                        TargetDescription(name: "D"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "E",
                    path: .init("/E"),
                    products: [
                        ProductDescription(name: "E", type: .library(.automatic), targets: ["E"])
                    ],
                    targets: [
                        TargetDescription(name: "E"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    name: "F",
                    path: .init("/F"),
                    products: [
                        ProductDescription(name: "F", type: .library(.automatic), targets: ["F"])
                    ],
                    targets: [
                        TargetDescription(name: "F"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "dependency 'b' is not used by any target", severity: .warning)
            result.check(diagnostic: "dependency 'c' is not used by any target", severity: .warning)
            result.check(diagnostic: "dependency 'd' is not used by any target", severity: .warning)
            result.check(diagnostic: "dependency 'e' is not used by any target", severity: .warning)
            result.check(diagnostic: "dependency 'f' is not used by any target", severity: .warning)
        }
    }

    func testTargetDependencies_Pre52() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testTargetDependencies_Pre52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' required by package 'foo' target 'Foo' not found.
                    """,
                severity: .error
            )
        }
    }

    func testTargetDependencies_Post52_NamesAligned() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    toolsVersion: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testTargetDependencies_Post52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    toolsVersion: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' required by package 'foo' target 'Foo' not found.
                    """,
                severity: .error
            )
        }
    }

    func testTargetDependencies_Post52_ProductPackageNoMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error
                )
            }
        }

        // fixit

        do {
            let fixedManifests = try [
                manifests[0].withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "ProductBar", package: "Bar")]),
                ]),
                manifests[1] // same
            ]

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }


    // TODO: remove this when we remove explicit dependency name
    func testTargetDependencies_Post52_ProductPackageNoMatch_DependencyExplicitName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error
                )
            }
        }


        // fixit

        do {
            let fixedManifests = try [
                manifests[0].withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "ProductBar", package: "Bar")]),
                ]),
                manifests[1] // same
            ]

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init("/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'Bar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Bar", package: "Some-Bar")'
                        """,
                    severity: .error
                )
            }
        }

        // fixit

        do {
            let fixedManifests = try [
                manifests[0].withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "Bar", package: "Some-Bar")]),
                ]),
                manifests[1] // same
            ]

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch_ProductPackageDontMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init("/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Some-Bar")'
                        """,
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .plain("foo"))
            }
        }

        // fix it

        do {
            let fixedManifests = try [
                manifests[0].withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "ProductBar", package: "Foo-Bar")]),
                ]),
                manifests[1] // same
            ]

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    // test backwards compatibility 5.2 < 5.4
    // TODO: remove this when we remove explicit dependency name
    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch_WithDependencyName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init("/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    // test backwards compatibility 5.2 < 5.4
    // TODO: remove this when we remove explicit dependency name
    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch_ProductPackageDontMatch_WithDependencyName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                name: "Foo",
                path: .init("/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init("/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests, observabilityScope: observability.topScope)
            testDiagnostics(observability.diagnostics) { result in
                let diagnostic = result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.packageIdentity, .plain("foo"))
            }
        }

        // fix it

        do {
            let fixedManifests = try [
                manifests[0].withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "ProductBar", package: "Some-Bar")]),
                ]),
                manifests[1] // same
            ]

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    // test backwards compatibility 5.2 < 5.4
    // TODO: remove this when we remove explicit dependency name
    func testTargetDependencies_Post52_AliasFindsIdentity() throws {
        let manifest = Manifest.createRootManifest(
            name: "Package",
            path: .init("/Package"),
            toolsVersion: .v5_2,
            dependencies: [
                .localSourceControl(
                    deprecatedName: "Alias",
                    path: .init("/Identity"),
                    requirement: .upToNextMajor(from: "1.0.0")
                ),
                .localSourceControl(
                    path: .init("/Unrelated"),
                    requirement: .upToNextMajor(from: "1.0.0")
                )
            ],
            targets: [
                try TargetDescription(
                    name: "Target",
                    dependencies: [
                        .product(name: "Product", package: "Alias"),
                        .product(name: "Unrelated", package: "Unrelated")
                    ]
                ),
            ])
        // Make sure aliases are found properly and do not fall back to pre‐5.2 behavior, leaking across onto other dependencies.
        let required = manifest.dependenciesRequired(for: .everything)
        let unrelated = try XCTUnwrap(required.first(where: { $0.nameForTargetDependencyResolutionOnly == "Unrelated" }))
        let requestedProducts = unrelated.productFilter
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        // Unrelated should not have been asked for Product, because it should know Product comes from Identity.
        XCTAssertFalse(requestedProducts.contains("Product"), "Product requests are leaking.")
        #endif
    }
}


extension Manifest {
    func withTargets(_ targets: [TargetDescription]) -> Manifest {
        Manifest.createManifest(
            name: self.displayName,
            path: self.path.parentDirectory,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            toolsVersion: self.toolsVersion,
            dependencies: self.dependencies,
            targets: targets
        )
    }

    func withDependencies(_ dependencies: [PackageDependency]) -> Manifest {
        Manifest.createManifest(
            name: self.displayName,
            path: self.path.parentDirectory,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            toolsVersion: self.toolsVersion,
            dependencies: dependencies,
            targets: self.targets
        )
    }
}
