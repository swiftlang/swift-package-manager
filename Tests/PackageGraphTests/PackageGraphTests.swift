/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import PackageGraph
import PackageModel
import SPMTestSupport

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

        let diagnostics = DiagnosticsEngine()
        let g = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .local,
                    packageLocation: "/Foo",
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["FooDep"]),
                        TargetDescription(name: "FooDep", dependencies: []),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .root,
                    packageLocation: "/Bar",
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
                    path: "/Baz",
                    packageLocation: "/Baz",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["Bar"]),
                        TargetDescription(name: "BazTests", dependencies: ["Baz"], type: .test),
                    ]),
            ]
        )

        XCTAssertNoDiagnostics(diagnostics)
        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo", "Baz")
            result.check(targets: "Bar", "Foo", "Baz", "FooDep")
            result.check(testModules: "BazTests")
            result.checkTarget("Foo") { result in result.check(dependencies: "FooDep") }
            result.checkTarget("Bar") { result in result.check(dependencies: "Foo") }
            result.checkTarget("Baz") { result in result.check(dependencies: "Bar") }
        }
    }

    func testProductDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Source/Bar/source.swift",
            "/Bar/Source/CBar/module.modulemap"
        )

        let diagnostics = DiagnosticsEngine()
        let g = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
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

        XCTAssertNoDiagnostics(diagnostics)
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

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
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
                    path: "/Baz",
                    packageKind: .local,
                    packageLocation: "/Baz",
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

        XCTAssertEqual(diagnostics.diagnostics[0].description, "cyclic dependency declaration found: Foo -> Bar -> Baz -> Bar")
    }

    func testCycle2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Baz/Sources/Baz/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
            ]
        )

        XCTAssertEqual(diagnostics.diagnostics[0].description, "cyclic dependency declaration found: Foo -> Foo")
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

        let diagnostics = DiagnosticsEngine()
        let g = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .root,
                    packageLocation: "/Bar",
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .local,
                    packageLocation: "/Foo",
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ]
        )

        XCTAssertNoDiagnostics(diagnostics)
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

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .root,
                    packageLocation: "/Bar",
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        XCTAssertEqual(diagnostics.diagnostics[0].description, "multiple targets named 'Bar' in: Bar, Foo")
    }

    func testMultipleDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/First/source.swift",
            "/Third/Sources/First/source.swift",
            "/Second/Sources/First/source.swift",
            "/First/Sources/First/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    packageKind: .local,
                    packageLocation: "/Fourth",
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    packageKind: .local,
                    packageLocation: "/Third",
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: "/Second",
                    packageKind: .local,
                    packageLocation: "/Second",
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: "/First",
                    packageKind: .root,
                    packageLocation: "/First",
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

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'First' in: First, Fourth, Second, Third", behavior: .error)
        }
    }

    func testSeveralDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/Bar/source.swift",
            "/Third/Sources/Bar/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/First/Sources/Foo/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    packageKind: .local,
                    packageLocation: "/Fourth",
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    packageKind: .local,
                    packageLocation: "/Third",
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: "/Second",
                    packageKind: .local,
                    packageLocation: "/Second",
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: "/First",
                    packageKind: .root,
                    packageLocation: "/First",
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

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Bar' in: Fourth, Third", behavior: .error)
            result.check(diagnostic: "multiple targets named 'Foo' in: First, Second", behavior: .error)
        }
    }

    func testNestedDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/First/source.swift",
            "/Third/Sources/Third/source.swift",
            "/Second/Sources/Second/source.swift",
            "/First/Sources/First/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    packageKind: .local,
                    packageLocation: "/Fourth",
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    packageKind: .local,
                    packageLocation: "/Third",
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
                    path: "/Second",
                    packageKind: .local,
                    packageLocation: "/Second",
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
                    path: "/First",
                    packageKind: .root,
                    packageLocation: "/First",
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

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'First' in: First, Fourth", behavior: .error)
        }
    }

    func testEmptyDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/source.txt"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "Source files for target Bar should be located under /Bar/Sources/Bar", behavior: .warning, location: "'Bar' /Bar")
            result.check(diagnostic: "target 'Bar' referenced in product 'Bar' is empty", behavior: .error, location: "'Bar' /Bar")
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: ["Barx"]),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "product 'Barx' not found. it is required by package 'Foo' target 'FooTarget'.", behavior: .error, location: "'Foo' /Foo")
        }
    }

    func testProductDependencyNotFoundWithName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx", package: "Bar")]),
                    ]
                )
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "product 'Barx' not found in package 'Bar'. it is required by package 'Foo' target 'FooTarget'.", behavior: .error, location: "'Foo' /Foo")
        }
    }

    func testProductDependencyNotFoundWithNoName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(name: "FooTarget", dependencies: [.product(name: "Barx")]),
                    ]
                )
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "product 'Barx' not found. it is required by package 'Foo' target 'FooTarget'.", behavior: .error, location: "'Foo' /Foo")
        }
    }

    func testProductDependencyNotFoundImprovedDiagnostic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/BarLib/bar.swift",
            "/BizPath/Sources/Biz/biz.swift",
            "/FizPath/Sources/FizLib/fiz.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5_2,
                    dependencies: [
                        .scm(name: "Bar", location: "/Bar", requirement: .branch("master")),
                        .scm(location: "/BizPath", requirement: .exact("1.2.3")),
                        .scm(location: "/FizPath", requirement: .upToNextMajor(from: "1.1.2")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLib", "Biz", "FizLib"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .remote,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "BarLib", type: .library(.automatic), targets: ["BarLib"])
                    ],
                    targets: [
                        TargetDescription(name: "BarLib"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: "/BizPath",
                    packageKind: .remote,
                    packageLocation: "/BizPath",
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Fiz",
                    path: "/FizPath",
                    packageKind: .remote,
                    packageLocation: "/FizPath",
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "FizLib", type: .library(.automatic), targets: ["FizLib"])
                    ],
                    targets: [
                        TargetDescription(name: "FizLib"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.checkUnordered(
                diagnostic: """
                dependency 'BarLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "BarLib", package: "Bar")'
                """,
                behavior: .error,
                location: "'Foo' /Foo"
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'Biz' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Biz", package: "BizPath")'
                """,
                behavior: .error,
                location: "'Foo' /Foo"
            )
            result.checkUnordered(
                diagnostic: """
                dependency 'FizLib' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "FizLib", package: "FizPath")'
                """,
                behavior: .error,
                location: "'Foo' /Foo"
            )
        }
    }

    func testPackageNameValidationInProductTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5_2,
                    dependencies: [
                        .scm(name: "UnBar", location: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "BarProduct", package: "UnBar")]),
                    ]),
                Manifest.createV4Manifest(
                    name: "UnBar",
                    path: "/Bar",
                    packageKind: .remote,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "BarProduct", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        // Expect no diagnostics.
        DiagnosticsEngineTester(diagnostics) { _ in }
    }

    func testUnusedDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift",
            "/Biz/Sources/Biz/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
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
                    path: "/Biz",
                    packageKind: .local,
                    packageLocation: "/Biz",
                    products: [
                        ProductDescription(name: "biz", type: .executable, targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "BarLibrary", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    packageKind: .local,
                    packageLocation: "/Baz",
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "dependency 'Baz' is not used by any target", behavior: .warning)
            #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
            result.check(diagnostic: "dependency 'Biz' is not used by any target", behavior: .warning)
            #endif
        }
    }

    func testUnusedDependency2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/module.modulemap",
            "/Bar/Sources/Bar/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .root,
                    packageLocation: "/Bar",
                    dependencies: [
                        .scm(location: "/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .local,
                    packageLocation: "/Foo"),
            ]
        )

        // We don't expect any unused dependency diagnostics from a system module package.
        DiagnosticsEngineTester(diagnostics) { _ in }
    }

    func testDuplicateInterPackageTargetNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Start/Sources/Foo/foo.swift",
            "/Start/Sources/Bar/bar.swift",
            "/Dep1/Sources/Baz/baz.swift",
            "/Dep2/Sources/Foo/foo.swift",
            "/Dep2/Sources/Bam/bam.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Start",
                    path: "/Start",
                    packageKind: .root,
                    packageLocation: "/Start",
                    dependencies: [
                        .scm(location: "/Dep1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep1",
                    path: "/Dep1",
                    packageKind: .local,
                    packageLocation: "/Dep1",
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
                    path: "/Dep2",
                    packageKind: .local,
                    packageLocation: "/Dep2",
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

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Foo' in: Dep2, Start", behavior: .error)
        }
    }

    func testDuplicateProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .scm(location: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    packageKind: .local,
                    packageLocation: "/Baz",
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ]
        )

        XCTAssertTrue(diagnostics.diagnostics.contains(where: { $0.description.contains("multiple products named 'Bar' in: Bar, Baz") }), "\(diagnostics.diagnostics)")
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

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
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

        XCTAssertEqual(diagnostics.diagnostics.count, 3)
        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'TransitiveBar' contains unsafe build flags"), behavior: .error)
            result.checkUnordered(diagnostic: .contains("the target 'Bar' in product 'Bar' contains unsafe build flags"), behavior: .error)
            result.checkUnordered(diagnostic: .contains("the target 'Bar2' in product 'Bar' contains unsafe build flags"), behavior: .error)
        }
    }

    func testInvalidExplicitPackageDependencyName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Baar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    dependencies: [
                        .scm(name: "Baar", location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Baar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    products: [
                        ProductDescription(name: "Baar", type: .library(.automatic), targets: ["Baar"])
                    ],
                    targets: [
                        TargetDescription(name: "Baar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.check(
                diagnostic: """
                    'Foo' dependency on '/Bar' has an explicit name 'Baar' which does not match the name 'Bar' set for '/Bar'
                    """,
                behavior: .error,
                location: "'Foo' /Foo"
            )
        }
    }

    func testConditionalTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Bar/source.swift",
            "/Foo/Sources/Baz/source.swift",
            "/Biz/Sources/Biz/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = try loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageLocation: "/Foo",
                    dependencies: [
                        .local(path: "/Biz"),
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
                    path: "/Biz",
                    packageKind: .remote,
                    packageLocation: "/Biz",
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]
                ),
            ]
        )

        XCTAssertNoDiagnostics(diagnostics)
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

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Root",
                    path: "/Root",
                    packageKind: .root,
                    packageLocation: "/Root",
                    v: .v5_2,
                    dependencies: [
                        .scm(name: "Immediate", location: "/Immediate", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Root", dependencies: [
                            .product(name: "ImmediateUsed", package: "Immediate")
                        ]),
                    ]
                ),
                Manifest.createManifest(
                    name: "Immediate",
                    path: "/Immediate",
                    packageKind: .local,
                    packageLocation: "/Immediate",
                    v: .v5_2,
                    dependencies: [
                        .scm(
                            name: "Transitive",
                            location: "/Transitive",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .scm(
                            name: "Nonexistent",
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
                    path: "/Transitive",
                    packageKind: .local,
                    packageLocation: "/Transitive",
                    v: .v5_2,
                    dependencies: [
                        .scm(
                            name: "Nonexistent",
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

        XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    func testPinsStoreIsResilientAgainstDupes() throws {
        let json = try JSON(string: """
              {
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
        """)

        let fs = InMemoryFileSystem(emptyFiles: [])
        let store = try PinsStore(pinsFile: AbsolutePath("/pins"), fileSystem: fs)
        XCTAssertThrows(StringError("duplicated entry for package \"Yams\""), { try store.restore(from: json) })
    }

    func testTargetDependencies_Pre52() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    v: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    func testTargetDependencies_Pre52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    v: .v5,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' not found. it is required by package 'Foo' target 'Foo'.
                    """,
                behavior: .error,
                location: "'Foo' /Foo"
            )
        }
    }

    func testTargetDependencies_Post52_NamesAligned() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    v: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    func testTargetDependencies_Post52_UnknownProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
                    v: .v5_2,
                    dependencies: [
                        .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    packageKind: .local,
                    packageLocation: "/Bar",
                    v: .v5_2,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.check(
                diagnostic: """
                    product 'Unknown' not found. it is required by package 'Foo' target 'Foo'.
                    """,
                behavior: .error,
                location: "'Foo' /Foo"
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Bar",
                packageKind: .local,
                packageLocation: "/Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
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

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(name: "Bar", location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Bar",
                packageKind: .local,
                packageLocation: "/Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
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

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Some-Bar",
                packageKind: .local,
                packageLocation: "/Some-Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        dependency 'Bar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "Bar", package: "Some-Bar")'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
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

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Some-Bar",
                packageKind: .local,
                packageLocation: "/Some-Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Some-Bar")'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
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

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(name: "Bar", location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Some-Bar",
                packageKind: .local,
                packageLocation: "/Some-Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        let diagnostics = DiagnosticsEngine()
        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
        XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
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
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(name: "Bar", location: "/Some-Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Bar",
                path: "/Some-Bar",
                packageKind: .local,
                packageLocation: "/Some-Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        dependency 'ProductBar' in target 'Foo' requires explicit declaration; reference the package in the target dependency with '.product(name: "ProductBar", package: "Bar")'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
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

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
        }
    }
    
    func testTargetDependencies_Post52_ManifestNameNotMatchedWithURL() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let manifests = try [
            Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                packageKind: .root,
                packageLocation: "/Foo",
                v: .v5_2,
                dependencies: [
                    .scm(name: "Bar", location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createManifest(
                name: "Some-Bar",
                path: "/Bar",
                packageKind: .local,
                packageLocation: "/Bar",
                v: .v5_2,
                products: [
                    ProductDescription(name: "ProductBar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        do {
            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: manifests)
            DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
                result.check(
                    diagnostic: """
                        'Foo' dependency on '/Bar' has an explicit name 'Bar' which does not match the name 'Some-Bar' set for '/Bar'
                        """,
                    behavior: .error,
                    location: "'Foo' /Foo"
                )
            }
        }

        // fix it

        do {
            let fixedManifests = [
                try manifests[0].withDependencies([
                    .scm(name: "Some-Bar", location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                ]).withTargets([
                    TargetDescription(name: "Foo", dependencies: [.product(name: "ProductBar", package: "Some-Bar")]),
                ]),
                manifests[1] // same
            ]

            let diagnostics = DiagnosticsEngine()
            _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics, manifests: fixedManifests)
            XCTAssert(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
        }
    }
}


extension Manifest {
    func withTargets(_ targets: [TargetDescription]) -> Manifest {
        Manifest.createManifest(
            name: self.name,
            path: self.path.parentDirectory.pathString,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            v: self.toolsVersion,
            dependencies: self.dependencies,
            targets: targets
        )
    }

    func withDependencies(_ dependencies: [PackageDependencyDescription]) -> Manifest {
        Manifest.createManifest(
            name: self.name,
            path: self.path.parentDirectory.pathString,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            v: self.toolsVersion,
            dependencies: dependencies,
            targets: self.targets
        )
    }
}
