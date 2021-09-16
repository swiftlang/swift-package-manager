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

        let observability = ObservabilitySystem.bootstrapForTesting()
        let g = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["FooDep"]),
                        TargetDescription(name: "FooDep", dependencies: []),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"], path: "./")
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["Bar"]),
                        TargetDescription(name: "BazTests", dependencies: ["Baz"], type: .test),
                    ]),
            ]
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

        let fooPackage = try XCTUnwrap(g.packages.first{ $0.manifestName == "Foo" })
        let fooTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "Foo" })
        let fooDepTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "FooDep" })
        XCTAssert(g.package(for: fooTarget) == fooPackage)
        XCTAssert(g.package(for: fooDepTarget) == fooPackage)
        let barPackage = try XCTUnwrap(g.packages.first{ $0.manifestName == "Bar" })
        let barTarget = try XCTUnwrap(g.allTargets.first{ $0.name == "Bar" })
        XCTAssert(g.package(for: barTarget) == barPackage)
    }

    func testProductDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Source/Bar/source.swift",
            "/Bar/Source/CBar/module.modulemap"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        let g = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
                        ProductDescription(name: "CBar", type: .library(.automatic), targets: ["CBar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["CBar"]),
                        TargetDescription(name: "CBar", type: .system),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    dependencies: [
                        .scm(location: "/Baz", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Baz"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    packageKind: .local,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Baz", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["Bar"]),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        let g = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: .init("/Third"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: .init("/Second"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: .init("/First"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "First", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: .init("/Third"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: .init("/Second"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: .init("/First"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: .init("/Fourth"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: .init("/Third"),
                    packageKind: .local,
                    dependencies: [
                        .scm(location: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Third"])
                    ],
                    targets: [
                        TargetDescription(name: "Third", dependencies: ["Fourth"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: .init("/Second"),
                    packageKind: .local,
                    dependencies: [
                        .scm(location: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Second"])
                    ],
                    targets: [
                        TargetDescription(name: "Second", dependencies: ["Third"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: .init("/First"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First", dependencies: ["Second"]),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "Source files for target Bar should be located under /Bar/Sources/Bar",
                severity: .warning,
                metadata: .packageMetadata(identity: .plain("bar"), location: "/Bar")
            )
            result.check(
                diagnostic: "target 'Bar' referenced in product 'Bar' is empty",
                severity: .error,
                metadata: .packageMetadata(identity: .plain("bar"), location: "/Bar")
            )
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: ["Barx"]),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found.",
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testProductDependencyDeclaredInSamePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/src.swift",
            "/Foo/Tests/FooTests/source.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["FooTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Foo' is declared in the same package 'foo' and can't be used as a dependency for target 'FooTests'.",
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testExecutableTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                "/XYZ/Sources/XYZ/main.swift",
                "/XYZ/Tests/XYZTests/tests.swift"
        )
        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
                                 manifests: [
                    Manifest.createV4Manifest(
                        name: "XYZ",
                        path: .init("/XYZ"),
                        packageKind: .root,
                        targets: [
                            TargetDescription(name: "XYZ", dependencies: [], type: .executable),
                            TargetDescription(name: "XYZTests", dependencies: ["XYZ"], type: .test),
                        ]),
                    ]
        )
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testSameProductAndTargetNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/src.swift",
            "/Foo/Tests/FooTests/source.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ]
        )
        testDiagnostics(observability.diagnostics) { _ in }
    }

    func testProductDependencyNotFoundWithName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx", package: "Bar")]),
                    ]
                )
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found in package 'Bar'.",
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testProductDependencyNotFoundWithNoName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx")]),
                    ]
                )
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "product 'Barx' required by package 'foo' target 'FooTarget' not found.",
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .branch("master")),
                        .scm(location: "/BizPath", requirement: .exact("1.2.3")),
                        .scm(location: "/FizPath", requirement: .upToNextMajor(from: "1.1.2")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLib", "Biz", "FizLib"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path:.init( "/Bar"),
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "BarLib", type: .library(.automatic), targets: ["BarLib"])
                    ],
                    targets: [
                        TargetDescription(name: "BarLib"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: .init("/BizPath"),
                    packageKind: .remote,
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Fiz",
                    path: .init("/FizPath"),
                    packageKind: .remote,
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "FizLib", type: .library(.automatic), targets: ["FizLib"])
                    ],
                    targets: [
                        TargetDescription(name: "FizLib"),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.checkUnordered(
                diagnostic: """
                dependency 'BarLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "BarLib", package: "Bar")'
                """,
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'Biz' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Biz", package: "BizPath")'
                """,
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'FizLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "FizLib", package: "FizPath")'
                """,
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testPackageNameValidationInProductTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5_2,
                    dependencies: [
                        .scm(deprecatedName: "UnBar", location: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "BarProduct", package: "UnBar")]),
                    ]),
                Manifest.createV4Manifest(
                    name: "UnBar",
                    path: .init("/Bar"),
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "BarProduct", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Biz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLibrary"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: .init("/Biz"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "biz", type: .executable, targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "BarLibrary", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .local
                ),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Start",
                    path: .init("/Start"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Dep1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep1",
                    path: .init("/Dep1"),
                    packageKind: .local,
                    dependencies: [
                        .scm(location: "/Dep2", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["FooLibrary"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep2",
                    path: .init("/Dep2"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "FooLibrary", type: .library(.automatic), targets: ["Foo"]),
                        ProductDescription(name: "BamLibrary", type: .library(.automatic), targets: ["Bam"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bam"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: .init("/Baz"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar", "Bar2", "Bar3"]),
                        ProductDescription(name: "TransitiveBar", type: .library(.automatic), targets: ["TransitiveBar"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Bar",
                            settings: [
                                .init(tool: .swift, name: .unsafeFlags, value: ["-Icfoo", "-L", "cbar"]),
                                .init(tool: .c, name: .unsafeFlags, value: ["-Icfoo", "-L", "cbar"]),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar2",
                            settings: [
                                .init(tool: .swift, name: .unsafeFlags, value: ["-Icfoo", "-L", "cbar"]),
                                .init(tool: .c, name: .unsafeFlags, value: ["-Icfoo", "-L", "cbar"]),
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
            ]
        )

        XCTAssertEqual(observability.diagnostics.count, 3)
        testDiagnostics(observability.diagnostics) { result in
            result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'TransitiveBar' contains unsafe build flags"), severity: .error)
            result.checkUnordered(diagnostic: .contains("the target 'Bar' in product 'Bar' contains unsafe build flags"), severity: .error)
            result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'Bar' contains unsafe build flags"), severity: .error)
        }
    }

    func testConditionalTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Bar/source.swift",
            "/Foo/Sources/Baz/source.swift",
            "/Biz/Sources/Biz/source.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .fileSystem(path: "/Biz"),
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
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: .init("/Biz"),
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]
                ),
            ]
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

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Root",
                    path: .init("/Root"),
                    packageKind: .root,
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Immediate", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Root", dependencies: [
                            .product(name: "ImmediateUsed", package: "Immediate")
                        ]),
                    ]
                ),
                Manifest.createManifest(
                    name: "Immediate",
                    path: .init("/Immediate"),
                    packageKind: .local,
                    v: .v5_2,
                    dependencies: [
                        .scm(
                            location: "/Transitive",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .scm(
                            location: "/Nonexistent",
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
                Manifest.createManifest(
                    name: "Transitive",
                    path: .init("/Transitive"),
                    packageKind: .local,
                    v: .v5_2,
                    dependencies: [
                        .scm(
                            location: "/Nonexistent",
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
            ]
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

        XCTAssertThrows(StringError("Package.resolved file is corrupted or malformed; fix or delete the file to continue: duplicated entry for package \"Yams\""), {
            _ = try PinsStore(pinsFile: AbsolutePath("/pins"), workingDirectory: .root, fileSystem: fs, mirrors: .init())
        })
    }

    func testTargetDependencies_Pre52() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    v: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testTargetDependencies_Pre52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    v: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' required by package 'foo' target 'Foo' not found.
                    """,
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testTargetDependencies_Post52_NamesAligned() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    v: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testTargetDependencies_Post52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    packageKind: .root,
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    packageKind: .local,
                    v: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' required by package 'foo' target 'Foo' not found.
                    """,
                severity: .error,
                metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
            )
        }
    }

    func testTargetDependencies_Post52_ProductPackageNoMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error,
                    metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
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

            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests)
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
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(deprecatedName: "Bar", location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error,
                    metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
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

            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'Bar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Bar", package: "Some-Bar")'
                        """,
                    severity: .error,
                    metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
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

            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    func testTargetDependencies_Post52_LocationAndManifestNameDontMatch_ProductPackageDontMatch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Some-Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Some-Bar")'
                        """,
                    severity: .error,
                    metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
                )
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

            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests)
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
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(deprecatedName: "Bar", location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        let observability = ObservabilitySystem.bootstrapForTesting()
        _ = try loadPackageGraph(fs: fs, manifests: manifests)
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
            Manifest.createManifest(
                name: "Foo",
                path: .init("/Foo"),
                packageKind: .root,
                v: .v5_2,
                dependencies: [
                    .scm(deprecatedName: "Bar", location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: .init("/Some-Bar"),
                packageKind: .local,
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: manifests)
            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    severity: .error,
                    metadata: .packageMetadata(identity: .plain("foo"), location: "/Foo")
                )
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

            let observability = ObservabilitySystem.bootstrapForTesting()
            _ = try loadPackageGraph(fs: fs, manifests: fixedManifests)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }
}


extension Manifest {
    func withTargets(_ targets: [TargetDescription]) -> Manifest {
        Manifest.createManifest(
            name: self.name,
            path: self.path.parentDirectory,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            v: self.toolsVersion,
            dependencies: self.dependencies,
            targets: targets
        )
    }

    func withDependencies(_ dependencies: [PackageDependency]) -> Manifest {
        Manifest.createManifest(
            name: self.name,
            path: self.path.parentDirectory,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            v: self.toolsVersion,
            dependencies: dependencies,
            targets: self.targets
        )
    }
}
