/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph
import PackageModel
import TestSupport

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
        let g = loadPackageGraph(root: "/Baz", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
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
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
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
            result.check(dependencies: "FooDep", target: "Foo")
            result.check(dependencies: "Foo", target: "Bar")
            result.check(dependencies: "Bar", target: "Baz")
        }
    }

    func testProductDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Source/Bar/source.swift",
            "/Bar/Source/CBar/module.modulemap"
        )

        let diagnostics = DiagnosticsEngine()
        let g = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
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
            result.check(dependencies: "Bar", "CBar", target: "Foo")
            result.check(dependencies: "CBar", target: "Bar")
        }
    }

    func testCycle() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Baz/Sources/Baz/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    dependencies: [
                        PackageDependencyDescription(url: "/Baz", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
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
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
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
        let g = loadPackageGraph(root: "/Bar", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    dependencies: [
                        PackageDependencyDescription(url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
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
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
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
        _ = loadPackageGraph(root: "/First", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(root: "/First", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(root: "/First", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Fourth",
                    path: "/Fourth",
                    url: "/Fourth",
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Fourth", requirement: .upToNextMajor(from: "1.0.0")),
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Third", requirement: .upToNextMajor(from: "1.0.0")),
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
                    dependencies: [
                        PackageDependencyDescription(url: "/Second", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
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
            result.check(diagnostic: "target 'Bar' referenced in product 'Bar' could not be found", behavior: .error, location: "'Bar' /Bar")
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Barx"]),
                    ]),
            ]
        )

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: "Product 'Barx' not found. It is required by target 'Foo'.", behavior: .error, location: "'Foo' /Foo")
        }
    }

    func testUnusedDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift",
            "/Biz/Sources/Biz/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Biz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLibrary"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Biz",
                    path: "/Biz",
                    url: "/Biz",
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
        }
    }

    func testUnusedDependency2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/module.modulemap",
            "/Bar/Sources/Bar/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(root: "/Bar", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    dependencies: [
                        PackageDependencyDescription(url: "/Foo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo"),
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
        _ = loadPackageGraph(root: "/Start", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Start",
                    path: "/Start",
                    url: "/Start",
                    dependencies: [
                        PackageDependencyDescription(url: "/Dep1", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Dep1",
                    path: "/Dep1",
                    url: "/Dep1",
                    dependencies: [
                        PackageDependencyDescription(url: "/Dep2", requirement: .upToNextMajor(from: "1.0.0")),
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
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                        PackageDependencyDescription(url: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
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
            "/Bar/Sources/Bar/bar.swift",
            "/Bar/Sources/Bar2/bar.swift",
            "/Bar/Sources/Bar3/bar.swift",
            "<end>"
        )

        let diagnostics = DiagnosticsEngine()
        _ = loadPackageGraph(root: "/Foo", fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    dependencies: [
                        PackageDependencyDescription(url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    products: [
                        ProductDescription(name: "Bar", targets: ["Bar", "Bar2", "Bar3"])
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
                    ]),
            ]
        )

        XCTAssertEqual(diagnostics.diagnostics.count, 2)
        DiagnosticsEngineTester(diagnostics, ignoreNotes: true) { result in
            result.check(diagnostic: .contains("the target 'Bar' in product 'Bar' contains unsafe build flags"), behavior: .error)
            result.check(diagnostic: .contains("the target 'Bar2' in product 'Bar' contains unsafe build flags"), behavior: .error)
        }
    }
}
