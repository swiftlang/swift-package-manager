//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageGraph
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
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["FooDep"]),
                        TargetDescription(name: "FooDep", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"], path: "./")
                    ]),
                Manifest.createRootManifest(
                    displayName: "Baz",
                    path: .init(path: "/Baz"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar", "CBar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Baz"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Baz"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Baz",
                    path: .init(path: "/Baz"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Foo"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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

    func testTargetGroup() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/libpkg/Sources/ExampleApp/main.swift",
            "/libpkg/Sources/MainLib/file.swift",
            "/libpkg/Sources/Core/file.swift",
            "/libpkg/Tests/MainLibTests/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "libpkg",
                    path: .init(path: "/libpkg"),
                    toolsVersion: .vNext,
                    products: [
                        ProductDescription(name: "ExampleApp", type: .executable, targets: ["ExampleApp"]),
                        ProductDescription(name: "Lib", type: .library(.automatic), targets: ["MainLib"])
                    ],
                    targets: [
                        TargetDescription(name: "ExampleApp", group: .excluded, dependencies: ["MainLib"], type: .executable),
                        TargetDescription(name: "MainLib", group: .package, dependencies: ["Core"]),
                        TargetDescription(name: "Core"),
                        TargetDescription(name: "MainLibTests", group: .package, dependencies: ["MainLib"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(g) { result in
            result.check(targets: "ExampleApp", "MainLib", "Core")
            result.check(testModules: "MainLibTests")
            result.checkTarget("MainLib") { result in result.check(dependencies: "Core") }
            result.checkTarget("MainLibTests") { result in result.check(dependencies: "MainLib") }
            result.checkTarget("ExampleApp") { result in result.check(dependencies: "MainLib") }
        }
    }

    func testDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Bar/source.swift",
            "/Bar/Sources/Bar/source.swift",
            "/Bar/Sources/Baz/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createRootManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    targets: [
                        TargetDescription(name: "Bar"),
                        TargetDescription(name: "Baz"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'Bar' in: 'bar', 'foo'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
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
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Fourth",
                    path: .init(path: "/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Third",
                    path: .init(path: "/Third"),
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Second",
                    path: .init(path: "/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["First"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "First", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "multiple targets named 'First' in: 'first', 'fourth', 'second', 'third'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
        }
    }

    func testSeveralDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/Fourth/source.swift",
            "/Fourth/Sources/Bar/source.swift",
            "/Third/Sources/Third/source.swift",
            "/Third/Sources/Bar/source.swift",
            "/Second/Sources/Second/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/First/Sources/First/source.swift",
            "/First/Sources/Foo/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Fourth",
                    path: .init(path: "/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["Fourth", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Fourth"),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Third",
                    path: .init(path: "/Third"),
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Third", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Third"),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Second",
                    path: .init(path: "/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Second", "Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Second"),
                        TargetDescription(name: "Foo"),
                    ]),
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["First", "Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "First"),
                        TargetDescription(name: "Foo", dependencies: ["Second", "Third", "Fourth"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.checkUnordered(diagnostic: "multiple targets named 'Bar' in: 'fourth', 'third'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
            result.checkUnordered(diagnostic: "multiple targets named 'Foo' in: 'first', 'second'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
        }
    }

    func testNestedDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Fourth/Sources/First/source.swift",
            "/Fourth/Sources/Fourth/source.swift",
            "/Third/Sources/Third/source.swift",
            "/Second/Sources/Second/source.swift",
            "/First/Sources/First/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Fourth",
                    path: .init(path: "/Fourth"),
                    products: [
                        ProductDescription(name: "Fourth", type: .library(.automatic), targets: ["Fourth", "First"])
                    ],
                    targets: [
                        TargetDescription(name: "Fourth"),
                        TargetDescription(name: "First"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Third",
                    path: .init(path: "/Third"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Fourth"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Third", type: .library(.automatic), targets: ["Third"])
                    ],
                    targets: [
                        TargetDescription(name: "Third", dependencies: ["Fourth"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Second",
                    path: .init(path: "/Second"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Third"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Second"])
                    ],
                    targets: [
                        TargetDescription(name: "Second", dependencies: ["Third"]),
                    ]),
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Second"), requirement: .upToNextMajor(from: "1.0.0")),
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
            result.check(diagnostic: "multiple targets named 'First' in: 'first', 'fourth'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
        }
    }

    func testPotentiallyDuplicatePackages() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/First/Sources/Foo/source.swift",
            "/First/Sources/Bar/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/Second/Sources/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["Foo", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Second",
                    path: .init(path: "/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("multiple similar targets 'Bar', 'Foo' appear in package 'first' and 'second'"), severity: .error)
        }
    }

    func testPotentiallyDuplicatePackagesManyTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/First/Sources/Foo/source.swift",
            "/First/Sources/Bar/source.swift",
            "/First/Sources/Baz/source.swift",
            "/First/Sources/Qux/source.swift",
            "/First/Sources/Quux/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/Second/Sources/Bar/source.swift",
            "/Second/Sources/Baz/source.swift",
            "/Second/Sources/Qux/source.swift",
            "/Second/Sources/Quux/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Second"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["Foo", "Bar", "Baz", "Qux", "Quux"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                        TargetDescription(name: "Baz"),
                        TargetDescription(name: "Qux"),
                        TargetDescription(name: "Quux"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Second",
                    path: .init(path: "/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo", "Bar", "Baz", "Qux", "Quux"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                        TargetDescription(name: "Baz"),
                        TargetDescription(name: "Qux"),
                        TargetDescription(name: "Quux"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("multiple similar targets 'Bar', 'Baz', 'Foo' and 2 others appear in package 'first' and 'second'"), severity: .error)
        }
    }

    func testPotentiallyDuplicatePackagesRegistrySCM() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/First/Sources/Foo/source.swift",
            "/First/Sources/Bar/source.swift",
            "/Second/Sources/Foo/source.swift",
            "/Second/Sources/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "First",
                    path: .init(path: "/First"),
                    dependencies: [
                        .registry(identity: "test.second", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "First", type: .library(.automatic), targets: ["Foo", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createRegistryManifest(
                    displayName: "Second",
                    identity: .plain("test.second"),
                    path: .init(path: "/Second"),
                    products: [
                        ProductDescription(name: "Second", type: .library(.automatic), targets: ["Foo", "Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo"),
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("multiple similar targets 'Bar', 'Foo' appear in registry package 'test.second' and source control package 'first'"), severity: .error)
        }
    }

    func testEmptyDependency() throws {
        let Bar: AbsolutePath = AbsolutePath("/Bar")

        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            Bar.appending(components: "Sources", "Bar", "source.txt").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: try .init(validating: Bar.pathString),
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
                diagnostic: .contains("Source files for target Bar should be located under 'Sources/Bar'"),
                severity: .warning
            )
            result.check(
                diagnostic: "target 'Bar' referenced in product 'Bar' is empty",
                severity: .error
            )
        }
    }

    func testTargetOnlyContainingHeaders() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Bar/Sources/Bar/include/bar.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
        PackageGraphTester(g) { result in
            result.check(packages: "Bar")
            result.check(targets: "Bar")
        }
    }

    func testProductDependencyNotFound() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "XYZ",
                    path: .init(path: "/XYZ"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .branch("master")),
                        .localSourceControl(path: .init(path: "/BizPath"), requirement: .exact("1.2.3")),
                        .localSourceControl(path: .init(path: "/FizPath"), requirement: .upToNextMajor(from: "1.1.2")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLib", "Biz", "FizLib"]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    products: [
                        ProductDescription(name: "BarLib", type: .library(.automatic), targets: ["BarLib"])
                    ],
                    targets: [
                        TargetDescription(name: "BarLib"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Biz",
                    path: .init(path: "/BizPath"),
                    version: "1.2.3",
                    products: [
                        ProductDescription(name: "Biz", type: .library(.automatic), targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Fiz",
                    path: .init(path: "/FizPath"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(deprecatedName: "UnBar", path: .init(path: "/Bar"), requirement: .branch("master")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "BarProduct", package: "UnBar")]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "UnBar",
                    path: .init(path: "/Bar"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Baz"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Biz"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BarLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Biz",
                    path: .init(path: "/Biz"),
                    products: [
                        ProductDescription(name: "biz", type: .executable, targets: ["Biz"])
                    ],
                    targets: [
                        TargetDescription(name: "Biz"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    products: [
                        ProductDescription(name: "BarLibrary", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Baz",
                    path: .init(path: "/Baz"),
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
            let diagnostic = result.check(diagnostic: "dependency 'baz' is not used by any target", severity: .warning)
            XCTAssertEqual(diagnostic?.metadata?.packageIdentity, "foo")
            XCTAssertEqual(diagnostic?.metadata?.packageKind?.isRoot, true)
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Foo"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo")
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Start",
                    path: .init(path: "/Start"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Dep1"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["BazLibrary"]),
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Dep1",
                    path: .init(path: "/Dep1"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Dep2"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "BazLibrary", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz", dependencies: ["FooLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Dep2",
                    path: .init(path: "/Dep2"),
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
            result.check(diagnostic: "multiple targets named 'Foo' in: 'dep2', 'start'; consider using the `moduleAliases` parameter in manifest to provide unique names", severity: .error)
        }
    }

    func testDuplicateProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Baz/Sources/Baz/baz.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/Baz"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Baz",
                    path: .init(path: "/Baz"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Baz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baz"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
               realError.description == "multiple products named 'Bar' in: 'bar', 'baz'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
                            name: "Bar3",
                            settings: [
                                .init(tool: .swift, kind: .unsafeFlags([])),
                            ]
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .fileSystem(path: .init(path: "/Biz")),
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
                    displayName: "Biz",
                    path: .init(path: "/Biz"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: .init(path: "/Root"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Immediate"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Root", dependencies: [
                            .product(name: "ImmediateUsed", package: "Immediate")
                        ]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Immediate",
                    path: .init(path: "/Immediate"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(
                            path: .init(path: "/Transitive"),
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .localSourceControl(
                            path: .init(path: "/Nonexistent"),
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
                    displayName: "Transitive",
                    path: .init(path: "/Transitive"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(
                            path: .init(path: "/Nonexistent"),
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
            _ = try PinsStore(pinsFile: "/pins", workingDirectory: .root, fileSystem: fs, mirrors: .init())
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
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/C"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/D"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/E"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/F"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "A", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"])
                    ],
                    targets: [
                        TargetDescription(name: "B"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "C",
                    path: .init(path: "/C"),
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"])
                    ],
                    targets: [
                        TargetDescription(name: "C"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "D",
                    path: .init(path: "/D"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"])
                    ],
                    targets: [
                        TargetDescription(name: "D"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "E",
                    path: .init(path: "/E"),
                    products: [
                        ProductDescription(name: "E", type: .library(.automatic), targets: ["E"])
                    ],
                    targets: [
                        TargetDescription(name: "E"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "F",
                    path: .init(path: "/F"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5_2,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Unknown"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Bar"),
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Bar"),
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init(path: "/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Some-Bar"),
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(path: .init(path: "/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Some-Bar"),
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init(path: "/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Some-Bar"),
                toolsVersion: .v5_2,
                products: [
                    ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
                ],
                targets: [
                    TargetDescription(name: "Bar"),
                ]),
        ]

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
                displayName: "Foo",
                path: .init(path: "/Foo"),
                toolsVersion: .v5_2,
                dependencies: [
                    .localSourceControl(deprecatedName: "Bar", path: .init(path: "/Some-Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                ],
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["ProductBar"]),
                ]),
            Manifest.createFileSystemManifest(
                displayName: "Bar",
                path: .init(path: "/Some-Bar"),
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: manifests, observabilityScope: observability.topScope)
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
            _ = try loadPackageGraph(fileSystem: fs, manifests: fixedManifests, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }

    // test backwards compatibility 5.2 < 5.4
    // TODO: remove this when we remove explicit dependency name
    func testTargetDependencies_Post52_AliasFindsIdentity() throws {
        let manifest = Manifest.createRootManifest(
            displayName: "Package",
            path: .init(path: "/Package"),
            toolsVersion: .v5_2,
            dependencies: [
                .localSourceControl(
                    deprecatedName: "Alias",
                    path: .init(path: "/Identity"),
                    requirement: .upToNextMajor(from: "1.0.0")
                ),
                .localSourceControl(
                    path: .init(path: "/Unrelated"),
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

    func testPlatforms() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift",
            "/Sources/cbar/bar.c",
            "/Sources/cbar/include/bar.h",
            "/Tests/test/test.swift"
        )

        let defaultDerivedPlatforms = [
            "linux": "0.0",
            "macos": "10.13",
            "maccatalyst": "13.0",
            "ios": "11.0",
            "tvos": "11.0",
            "driverkit": "19.0",
            "watchos": "4.0",
            "android": "0.0",
            "windows": "0.0",
            "wasi": "0.0",
            "openbsd": "0.0"
        ]

        let customXCTestMinimumDeploymentTargets = [
            PackageModel.Platform.macOS: PlatformVersion("10.15"),
            PackageModel.Platform.iOS: PlatformVersion("11.0"),
            PackageModel.Platform.tvOS: PlatformVersion("11.0"),
            PackageModel.Platform.watchOS: PlatformVersion("4.0"),
        ]

        do {
            // One platform with an override.
            let manifest = Manifest.createRootManifest(
                displayName: "pkg",
                platforms: [
                    PlatformDescription(name: "macos", version: "10.14", options: ["option1"]),
                ],
                products: [
                    try ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
                    try ProductDescription(name: "cbar", type: .library(.automatic), targets: ["cbar"]),
                    try ProductDescription(name: "bar", type: .library(.automatic), targets: ["bar"]),
                    try ProductDescription(name: "multi-target", type: .library(.automatic), targets: ["bar", "cbar", "bar", "test"]),
                ],
                targets: [
                    try TargetDescription(name: "foo", type: .system),
                    try TargetDescription(name: "cbar"),
                    try TargetDescription(name: "bar", dependencies: ["foo"]),
                    try TargetDescription(name: "test", type: .test)
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [manifest],
                customXCTestMinimumDeploymentTargets: customXCTestMinimumDeploymentTargets,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            PackageGraphTester(graph) { result in
                let expectedDeclaredPlatforms = [
                    "macos": "10.14"
                ]

                // default platforms will be auto-added during package build
                let expectedDerivedPlatforms = defaultDerivedPlatforms.merging(expectedDeclaredPlatforms, uniquingKeysWith: { lhs, rhs in rhs })

                result.checkTarget("foo") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                    target.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    target.checkDerivedPlatformOptions(.iOS, options: [])
                }
                result.checkTarget("bar") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                    target.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    target.checkDerivedPlatformOptions(.iOS, options: [])

                }
                result.checkTarget("cbar") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                    target.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    target.checkDerivedPlatformOptions(.iOS, options: [])
                }
                result.checkTarget("test") { target in
                    var expected = expectedDerivedPlatforms
                    [PackageModel.Platform.macOS, .iOS, .tvOS, .watchOS].forEach {
                        expected[$0.name] = customXCTestMinimumDeploymentTargets[$0]?.versionString
                    }
                    target.checkDerivedPlatforms(expected)
                    target.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    target.checkDerivedPlatformOptions(.iOS, options: [])
                }
                result.checkProduct("foo") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                    product.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    product.checkDerivedPlatformOptions(.iOS, options: [])
                }
                result.checkProduct("bar") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                    product.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    product.checkDerivedPlatformOptions(.iOS, options: [])

                }
                result.checkProduct("cbar") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                    product.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    product.checkDerivedPlatformOptions(.iOS, options: [])
                }
                result.checkProduct("multi-target") { product in
                    var expected = expectedDerivedPlatforms
                    [PackageModel.Platform.macOS, .iOS, .tvOS, .watchOS].forEach {
                        expected[$0.name] = customXCTestMinimumDeploymentTargets[$0]?.versionString
                    }
                    product.checkDerivedPlatforms(expected)
                    product.checkDerivedPlatformOptions(.macOS, options: ["option1"])
                    product.checkDerivedPlatformOptions(.iOS, options: [])
                }
            }
        }

        do {
            // Two platforms with overrides.
            let manifest = Manifest.createRootManifest(
                displayName: "pkg",
                platforms: [
                    PlatformDescription(name: "macos", version: "10.14"),
                    PlatformDescription(name: "tvos", version: "12.0"),
                ],
                products: [
                    try ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
                    try ProductDescription(name: "cbar", type: .library(.automatic), targets: ["cbar"]),
                    try ProductDescription(name: "bar", type: .library(.automatic), targets: ["bar"]),
                ],
                targets: [
                    try TargetDescription(name: "foo", type: .system),
                    try TargetDescription(name: "cbar"),
                    try TargetDescription(name: "bar", dependencies: ["foo"]),
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [manifest],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            PackageGraphTester(graph) { result in
                let expectedDeclaredPlatforms = [
                    "macos": "10.14",
                    "tvos": "12.0",
                ]

                // default platforms will be auto-added during package build
                let expectedDerivedPlatforms = defaultDerivedPlatforms.merging(expectedDeclaredPlatforms, uniquingKeysWith: { lhs, rhs in rhs })

                result.checkTarget("foo") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkTarget("bar") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkTarget("cbar") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("foo") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("bar") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("cbar") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
            }
        }

        do {
            // Test MacCatalyst overriding behavior.
            let manifest = Manifest.createRootManifest(
                displayName: "pkg",
                platforms: [
                    PlatformDescription(name: "ios", version: "15.0"),
                ],
                products: [
                    try ProductDescription(name: "cbar", type: .library(.automatic), targets: ["cbar"]),
                ],
                targets: [
                    try TargetDescription(name: "cbar"),
                    try TargetDescription(name: "test", type: .test)
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [manifest],
                customXCTestMinimumDeploymentTargets: customXCTestMinimumDeploymentTargets,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            PackageGraphTester(graph) { result in
                let expectedDeclaredPlatforms = [
                    "ios": "15.0",
                ]

                var expectedDerivedPlatforms = defaultDerivedPlatforms.merging(expectedDeclaredPlatforms, uniquingKeysWith: { lhs, rhs in rhs })
                var expectedDerivedPlatformsForTests = defaultDerivedPlatforms.merging(customXCTestMinimumDeploymentTargets.map { ($0.name, $1.versionString) }, uniquingKeysWith: { lhs, rhs in rhs })
                expectedDerivedPlatformsForTests["ios"] = expectedDeclaredPlatforms["ios"]

                // Gets derived to be the same as the declared iOS deployment target.
                expectedDerivedPlatforms["maccatalyst"] = expectedDeclaredPlatforms["ios"]
                expectedDerivedPlatformsForTests["maccatalyst"] = expectedDeclaredPlatforms["ios"]

                result.checkTarget("test") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatformsForTests)
                }
                result.checkTarget("cbar") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("cbar") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
            }
        }
    }

    func testCustomPlatforms() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap"
        )

        let defaultDerivedPlatforms = [
            "linux": "0.0",
            "macos": "10.13",
            "maccatalyst": "13.0",
            "ios": "11.0",
            "tvos": "11.0",
            "driverkit": "19.0",
            "watchos": "4.0",
            "android": "0.0",
            "windows": "0.0",
            "wasi": "0.0",
            "openbsd": "0.0"
        ]

        do {
            // One custom platform.
            let manifest = Manifest.createRootManifest(
                displayName: "pkg",
                platforms: [
                    PlatformDescription(name: "customos", version: "1.0"),
                ],
                products: [
                    try ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
                ],
                targets: [
                    try TargetDescription(name: "foo", type: .system),
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [manifest],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            PackageGraphTester(graph) { result in
                let expectedDeclaredPlatforms = [
                    "customos": "1.0"
                ]

                // default platforms will be auto-added during package build
                let expectedDerivedPlatforms = defaultDerivedPlatforms.merging(expectedDeclaredPlatforms, uniquingKeysWith: { lhs, rhs in rhs })

                result.checkTarget("foo") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("foo") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
            }
        }

        do {
            // Two platforms with overrides.
            let manifest = Manifest.createRootManifest(
                displayName: "pkg",
                platforms: [
                    PlatformDescription(name: "customos", version: "1.0"),
                    PlatformDescription(name: "anothercustomos", version: "2.3"),
                ],
                products: [
                    try ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
                ],
                targets: [
                    try TargetDescription(name: "foo", type: .system),
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [manifest],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            PackageGraphTester(graph) { result in
                let expectedDeclaredPlatforms = [
                    "customos": "1.0",
                    "anothercustomos": "2.3"
                ]

                // default platforms will be auto-added during package build
                let expectedDerivedPlatforms = defaultDerivedPlatforms.merging(expectedDeclaredPlatforms, uniquingKeysWith: { lhs, rhs in rhs })

                result.checkTarget("foo") { target in
                    target.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    target.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
                result.checkProduct("foo") { product in
                    product.checkDeclaredPlatforms(expectedDeclaredPlatforms)
                    product.checkDerivedPlatforms(expectedDerivedPlatforms)
                }
            }
        }
    }

    func testDependencyOnUpcomingFeatures() throws {
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
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar"]),
                        TargetDescription(name: "Foo2", dependencies: ["TransitiveBar"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar", "Bar2", "Bar3"]),
                        ProductDescription(name: "TransitiveBar", type: .library(.automatic), targets: ["TransitiveBar"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Bar",
                            settings: [
                                .init(tool: .swift, kind: .enableUpcomingFeature("ConciseMagicFile")),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar2",
                            settings: [
                                .init(tool: .swift, kind: .enableUpcomingFeature("UnknownToTheseTools")),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar3",
                            settings: [
                                .init(tool: .swift, kind: .enableUpcomingFeature("ExistentialAny")),
                                .init(tool: .swift, kind: .enableUpcomingFeature("UnknownToTheseTools")),
                            ]
                        ),
                        TargetDescription(
                            name: "TransitiveBar",
                            dependencies: ["Bar2"]
                        ),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertEqual(observability.diagnostics.count, 0, "unexpected diagnostics: \(observability.diagnostics.map { $0.description })")
    }

    func testCustomNameInPackageDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar2/Sources/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    toolsVersion: .v5_9,
                    dependencies: [
                        .fileSystem(deprecatedName: "Bar", path: "/Bar2"),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: [.product(name: "Bar", package: "BAR")]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar2"),
                    toolsVersion: .v5_9,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar"),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertEqual(observability.diagnostics.count, 0, "unexpected diagnostics: \(observability.diagnostics.map { $0.description })")
    }
}


extension Manifest {
    func withTargets(_ targets: [TargetDescription]) -> Manifest {
        Manifest.createManifest(
            displayName: self.displayName,
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
            displayName: self.displayName,
            path: self.path.parentDirectory,
            packageKind: self.packageKind,
            packageLocation: self.packageLocation,
            toolsVersion: self.toolsVersion,
            dependencies: dependencies,
            targets: self.targets
        )
    }
}
