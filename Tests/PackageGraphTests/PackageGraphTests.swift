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
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Foo", targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["FooDep"]),
                        TargetDescription(name: "FooDep", dependencies: []),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"], path: "./")
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
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
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar"]),
                        ProductDescription(name: "CBar", targets: ["CBar"]),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Baz", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Baz"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Baz", targets: ["Baz"])
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
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
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Foo", targets: ["Foo"]),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    url: "/Third",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Third", targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: "/Second",
                    url: "/Second",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Second", targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: "/First",
                    url: "/First",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    url: "/Third",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Third", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: "/Second",
                    url: "/Second",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Second", targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: "/First",
                    url: "/First",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Fourth", targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Third",
                    path: "/Third",
                    url: "/Third",
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Third", targets: ["Third"])
                    ],
                    targets: [
                        TargetDescription(name: "Third", dependencies: ["Fourth"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Second",
                    path: "/Second",
                    url: "/Second",
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Second", targets: ["Second"])
                    ],
                    targets: [
                        TargetDescription(name: "Second", dependencies: ["Third"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "First",
                    path: "/First",
                    url: "/First",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", targets: ["First"])
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "Source files for target Bar should be located under /Bar/Sources/Bar", behavior: .warning)
            result.check(diagnostic: "target 'Bar' referenced in product 'Bar' is empty", behavior: .error, location: "'Bar' /Bar")
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Barx"]),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "product 'Barx' not found. It is required by target 'Foo'.", behavior: .error, location: "'Foo' /Foo")
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: "Bar", url: "/Bar", requirement: .branch("master")),
                        PackageDependencyDescription(name: nil, url: "/BizPath", requirement: .exact("1.2.3")),
                        PackageDependencyDescription(name: nil, url: "/FizPath", requirement: .upToNextMajor(from: "1.1.2")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLib", "Biz", "FizLib"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "BarLib", targets: ["BarLib"])
                    ],
                    targets: [
                        TargetDescription(name: "BarLib"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: "/BizPath",
                    url: "/BizPath",
                    version: "1.2.3",
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "Biz", targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Fiz",
                    path: "/FizPath",
                    url: "/FizPath",
                    version: "1.2.3",
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "FizLib", targets: ["FizLib"])
                    ],
                    targets: [
                        TargetDescription(name: "FizLib"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.checkUnordered(diagnostic: """
                dependency 'BarLib' in target 'Foo' requires explicit declaration; reference the package in the target \
                dependency with '.product(name: "BarLib", package: "Bar")'
                """, behavior: .error, location: "'Foo' /Foo")
            result.checkUnordered(diagnostic: """
                dependency 'Biz' in target 'Foo' requires explicit declaration; provide the name of the package \
                dependency with '.package(name: "Biz", url: "/BizPath", .exact("1.2.3"))'
                """, behavior: .error, location: "'Foo' /Foo")
            result.checkUnordered(diagnostic: """
                dependency 'FizLib' in target 'Foo' requires explicit declaration; reference the package in the target \
                dependency with '.product(name: "FizLib", package: "Fiz")' and provide the name of the package \
                dependency with '.package(name: "Fiz", url: "/FizPath", from: "1.1.2")'
                """, behavior: .error, location: "'Foo' /Foo")
        }
    }

    func testPackageNameValidationInProductTargetDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: "UnBar", url: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "BarProduct", package: "UnBar")]),
                    ]),
                Manifest.createV4Manifest(
                    name: "UnBar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "BarProduct", targets: ["Bar"])
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Biz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLibrary"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: "/Biz",
                    url: "/Biz",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "biz", type: .executable, targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "BarLibrary", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "BazLibrary", targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "dependency 'Baz' is not used by any target", behavior: .warning)
            result.check(diagnostic: "dependency 'Biz' is not used by any target", behavior: .warning)
        }
    }

    func testUnusedDependency2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/module.modulemap",
            "/Bar/Sources/Bar/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .local),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Start",
                    path: "/Start",
                    url: "/Start",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Dep1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep1",
                    path: "/Dep1",
                    url: "/Dep1",
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Dep2", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "BazLibrary", targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["FooLibrary"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep2",
                    path: "/Dep2",
                    url: "/Dep2",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "FooLibrary", targets: ["Foo"]),
                        ProductDescription(name: "BamLibrary", targets: ["Bam"]),
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(name: nil, url: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", targets: ["Baz"])
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
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar", "Bar2", "Bar3"]),
                        ProductDescription(name: "TransitiveBar", targets: ["TransitiveBar"]),
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

    func testInvalidExplicitPackageDependencyName() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Baar/bar.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: "Baar", url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Baar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Baar", targets: ["Baar"])
                    ],
                    targets: [
                        TargetDescription(name: "Baar"),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.check(
                diagnostic: """
                    declared name 'Baar' for package dependency '/Bar' does not match the actual package name 'Bar'
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
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(name: nil, url: "/Biz", requirement: .localPackage),
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
                    url: "/Biz",
                    packageKind: .remote,
                    products: [
                        ProductDescription(name: "Biz", targets: ["Biz"])
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

    func testUnreachableProductsSkipped() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Root/Sources/Root/Root.swift",
            "/Immediate/Sources/ImmediateUsed/ImmediateUsed.swift",
            "/Immediate/Sources/ImmediateUnused/ImmediateUnused.swift",
            "/Transitive/Sources/TransitiveUsed/TransitiveUsed.swift",
            "/Transitive/Sources/TransitiveUnused/TransitiveUnused.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Root",
                    path: "/Root",
                    url: "/Root",
                    v: .v5_2,
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: "Immediate", url: "/Immediate", requirement: .upToNextMajor(from: "1.0.0")),
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
                    url: "/Immediate",
                    v: .v5_2,
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(
                            name: "Transitive",
                            url: "/Transitive",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        PackageDependencyDescription(
                            name: "Nonexistent",
                            url: "/Nonexistent",
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(name: "ImmediateUsed", targets: ["ImmediateUsed"]),
                        ProductDescription(name: "ImmediateUnused", targets: ["ImmediateUnused"])
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
                    url: "/Transitive",
                    v: .v5_2,
                    packageKind: .local,
                    dependencies: [
                        PackageDependencyDescription(
                            name: "Nonexistent",
                            url: "/Nonexistent",
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(name: "TransitiveUsed", targets: ["TransitiveUsed"])
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
}
