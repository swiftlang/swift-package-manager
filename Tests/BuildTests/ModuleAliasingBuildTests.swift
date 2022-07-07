@testable import Build
@testable import PackageGraph
@testable import PackageModel
import Basics
import PackageLoading
import SPMBuildCore
import SPMTestSupport
import SwiftDriver
import TSCBasic
import Workspace
import XCTest

final class ModuleAliasingBuildTests: XCTestCase {

    func testModuleAliasingEmptyAlias() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/fooPkg/Sources/Logging/fileLogging.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Foo",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": ""]
                                                                 ),
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("empty or invalid module alias; ['Logging': '']"), severity: .error)
        }
    }

    func testModuleAliasingInvalidIdentifierAlias() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/fooPkg/Sources/Logging/fileLogging.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Foo",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "P$0%^#@"]
                                                                 ),
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("empty or invalid module alias; ['Logging': 'P$0%^#@']"), severity: .error)
        }
    }

    func testModuleAliasingDuplicateProductNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" && $0.target.moduleAliases?["Logging"] == "BarLogging" })
    }

    func testModuleAliasingDuplicateDylibProductNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("multiple products named 'Logging' in: 'barpkg', 'foopkg'"), severity: .error)
        }
    }

    func testModuleAliasingDuplicateDylibStaticLibProductNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let _ = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.static), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("multiple products named 'Logging' in: 'barpkg', 'foopkg'"), severity: .error)
        }
    }

    func testModuleAliasingDuplicateDylibAutomaticProductNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/bazPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 ),
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" && $0.target.moduleAliases?["Logging"] == "BarLogging" })
        #if os(macOS)
        let dylib = try result.buildProduct(for: "Logging")
        XCTAssertTrue(dylib.binary.basename == "libLogging.dylib" && dylib.package.identity.description == "barpkg")
        #endif
    }

    func testModuleAliasingDuplicateStaticLibAutomaticProductNames() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/bazPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bazPkg",
                    path: .init("/bazPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.static), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/bazPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "bazPkg",
                                                                  moduleAliases: ["Logging": "BazLogging"]
                                                                 )

                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BazLogging" && $0.target.moduleAliases?["Logging"] == "BazLogging" })
        #if os(macOS)
        let staticlib = try result.buildProduct(for: "Logging")
        XCTAssertTrue(staticlib.binary.basename == "libLogging.a" && staticlib.package.identity.description == "bazpkg")
        #endif
    }

    func testModuleAliasingDuplicateProductNamesUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/aPkg/Sources/A/file.swift",
                                    "/xPkg/Sources/Logging/fileLogging.swift",
                                    "/bPkg/Sources/B/file.swift",
                                    "/yPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                name: "xPkg",
                path: .init("/xPkg"),
                products: [
                    ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["Logging"]),
                ],
                targets: [
                    TargetDescription(name: "Logging",
                                      dependencies: []),
                ]),
                Manifest.createFileSystemManifest(
                    name: "yPkg",
                    path: .init("/yPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging",
                                          dependencies: []),

                    ]),
                Manifest.createFileSystemManifest(
                    name: "aPkg",
                    path: .init("/aPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xPkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.dynamic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "Logging", package: "xPkg")
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bPkg",
                    path: .init("/bPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/yPkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.dynamic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            .product(name: "Logging", package: "yPkg")
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/aPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/bPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "A",
                                                                  package: "aPkg",
                                                                  moduleAliases: ["Logging": "ALogging"]
                                                                 ),
                                                         .product(name: "B",
                                                                  package: "bPkg"
                                                                 )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(4)
        result.checkTargetsCount(5)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "ALogging" && $0.target.moduleAliases?["Logging"] == "ALogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Logging"] == "ALogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases == nil })
        #if os(macOS)
        let dylib = try result.buildProduct(for: "Logging")
        XCTAssertTrue(dylib.binary.basename == "libLogging.dylib" && dylib.package.identity.description == "xpkg")
        #endif
    }

    func testModuleAliasingDirectDeps() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/fooPkg/Sources/Logging/fileLogging.swift",
                                        "/barPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Logging",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 )
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" && $0.target.moduleAliases?["Logging"] == "BarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        
        let fooLoggingArgs = try result.target(for: "FooLogging").swiftTarget().compileArguments()
        let barLoggingArgs = try result.target(for: "BarLogging").swiftTarget().compileArguments()
        let loggingArgs = try result.target(for: "Logging").swiftTarget().compileArguments()
        #if os(macOS)
        XCTAssertMatch(fooLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/FooLogging.build/FooLogging-Swift.h", .anySequence])
        XCTAssertMatch(barLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/BarLogging.build/BarLogging-Swift.h", .anySequence])
        XCTAssertMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #else
        XCTAssertNoMatch(fooLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/FooLogging.build/FooLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(barLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/BarLogging.build/BarLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #endif
    }

    func testModuleAliasingDuplicateTargetNameInUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/otherPkg/Sources/Utils/fileUtils.swift",
                                        "/otherPkg/Sources/Logging/fileLogging.swift",
                                        "/otherPkg/Sources/Math/file.swift",
                                        "/otherPkg/Sources/Tools/file.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "otherPkg",
                    path: .init("/otherPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "Math", type: .library(.automatic), targets: ["Math"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Math", dependencies: ["Tools"]),
                        TargetDescription(name: "Tools", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/otherPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Math",
                                                                  package: "otherPkg"),
                                                         .product(name: "Utils",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "OtherLogging"])]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(6)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "OtherLogging" && $0.target.moduleAliases?["Logging"] == "OtherLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "OtherLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })

        let otherLoggingArgs = try result.target(for: "OtherLogging").swiftTarget().compileArguments()
        let loggingArgs = try result.target(for: "Logging").swiftTarget().compileArguments()
        
        #if os(macOS)
        XCTAssertMatch(otherLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/OtherLogging.build/OtherLogging-Swift.h", .anySequence])
        XCTAssertMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #else
        XCTAssertNoMatch(otherLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/OtherLogging.build/OtherLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #endif
    }

    func testModuleAliasingMultipleAliasesInProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/otherPkg/Sources/Utils/fileUtils.swift",
                                        "/otherPkg/Sources/Logging/fileLogging.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "otherPkg",
                    path: .init("/otherPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "LoggingProd", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/otherPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "UtilsLogging"]),
                                                         .product(name: "LoggingProd",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "OtherLogging"])]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
                    realError.description == "multiple aliases: ['UtilsLogging', 'OtherLogging'] found for target 'Logging' in product 'LoggingProd' from package 'otherPkg'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
        }
    }

    func testModuleAliasingSameNameTargetsWithAliasesInMultiProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                        "/swift-log/Sources/Logging/fileLogging.swift",
                                        "/swift-metrics/Sources/Metrics/file.swift",
                                        "/swift-metrics/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "swift-log",
                    path: .init("/swift-log"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "swift-metrics",
                    path: .init("/swift-metrics"),
                    products: [
                        ProductDescription(name: "Metrics", type: .library(.automatic), targets: ["Metrics"]),
                    ],
                    targets: [
                        TargetDescription(name: "Metrics", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/swift-log"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/swift-metrics"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "swift-log"
                                                                 ),
                                                         .product(name: "Metrics",
                                                                  package: "swift-metrics",
                                                                  moduleAliases: ["Logging": "MetricsLogging"]
                                                                 )
                                                        ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "MetricsLogging" && $0.target.moduleAliases?["Logging"] == "MetricsLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingInvalidSourcesUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.m",
                                    "/fooPkg/Sources/Logging/include/fileLogging.h"
        )
        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
                    realError.description == "module aliasing can only be used for Swift based targets; non-Swift sources found in target 'Logging' for product 'Utils' from package 'foopkg'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
        }
    }

    func testModuleAliasingInvalidSourcesNestedUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.m",
                                    "/barPkg/Sources/Logging/include/fileLogging.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging", package: "barPkg")]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
                    realError.description == "module aliasing can only be used for Swift based targets; non-Swift sources found in target 'Logging' for product 'Logging' from package 'barpkg'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
        }
    }

    func testModuleAliasingInvalidSourcesInNonAliasedModulesUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/fooPkg/Sources/Logging/fileLogging.swift",
                                    "/fooPkg/Sources/Logging/guidelines.txt",
                                    "/fooPkg/Sources/Perf/filePerf.m",
                                    "/fooPkg/Sources/Perf/include/filePerf.h"
        )
        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertNoThrow(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "Perf", type: .library(.automatic), targets: ["Perf"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Perf", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        ))
    }

    func testModuleAliasingInvalidSourcesInNonAliasedModulesNestedUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Logging/readme.md",
                                    "/barPkg/Sources/Perf/filePerf.m",
                                    "/barPkg/Sources/Perf/include/filePerf.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertNoThrow(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                        ProductDescription(name: "Perf", type: .library(.automatic), targets: ["Perf"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Perf", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging", package: "barPkg")]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        ))
    }

    func testModuleAliasingDuplicateTargetNameInNestedUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging", package: "barPkg")]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingOverrideMultipleAliases() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file1.swift",
                                    "/thisPkg/Sources/Math/file2.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Math/fileMath.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "LoggingProd", type: .library(.automatic), targets: ["Logging"]),
                        ProductDescription(name: "MathProd", type: .library(.automatic), targets: ["Math"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Math", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "LoggingProd",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 ),
                                                         .product(name: "MathProd",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Math": "BarMath"])
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         "Math",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["BarLogging": "FooLogging", "BarMath": "FooMath"])
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Math", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(6)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooMath" && $0.target.moduleAliases?["Math"] == "FooMath" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" && $0.target.moduleAliases?["Math"] == "FooMath" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Math" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "exe" && $0.target.moduleAliases == nil})
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testModuleAliasingAliasSkipUpstreamTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Foo/file.swift",
                                    "/xPkg/Sources/X/file.swift",
                                    "/yPkg/Sources/Y/file.swift",
                                    "/zPkg/Sources/Z/file.swift",
                                    "/zPkg/Sources/Foo/file.swift",
                                    "/aPkg/Sources/A/file.swift",
                                    "/bPkg/Sources/B/file.swift",
                                    "/cPkg/Sources/C/file.swift",
                                    "/cPkg/Sources/Foo/file.swift",
                                    "/dPkg/Sources/D/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "cPkg",
                    path: .init("/cPkg"),
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"]),
                    ],
                    targets: [
                        TargetDescription(name: "C", dependencies: ["Foo"]),
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "dPkg",
                    path: .init("/dPkg"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"]),
                    ],
                    targets: [
                        TargetDescription(name: "D", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bPkg",
                    path: .init("/bPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/cPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            .product(name: "C",
                                                     package: "cPkg"),
                                            .product(name: "D",
                                                     package: "dPkg")
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "aPkg",
                    path: .init("/aPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [.product(name: "B",
                                                                  package: "bPkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "zPkg",
                    path: .init("/zPkg"),
                    products: [
                        ProductDescription(name: "Z", type: .library(.automatic), targets: ["Z"]),
                    ],
                    targets: [
                        TargetDescription(name: "Z", dependencies: ["Foo"]),
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "yPkg",
                    path: .init("/yPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/zPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Y", type: .library(.automatic), targets: ["Y"]),
                    ],
                    targets: [
                        TargetDescription(name: "Y",
                                          dependencies: [
                                            .product(name: "Z",
                                                     package: "zPkg"
                                          )]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "xPkg",
                    path: .init("/xPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/yPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [.product(name: "Y",
                                                                  package: "yPkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/aPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/xPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [ "Foo",
                                                         .product(name: "A",
                                                                  package: "aPkg",
                                                                  moduleAliases: ["Foo": "FooA"]),
                                                         .product(name: "X",
                                                                  package: "xPkg",
                                                                  moduleAliases: ["Foo": "FooX"])
                                                        ]
                                         ),
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(11)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "D" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooA" && $0.target.moduleAliases?["Foo"] == "FooA" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "C" && $0.target.moduleAliases?["Foo"] == "FooA" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases?["Foo"] == "FooA" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Foo"] == "FooA" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooX" && $0.target.moduleAliases?["Foo"] == "FooX" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Z" && $0.target.moduleAliases?["Foo"] == "FooX" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Y" && $0.target.moduleAliases?["Foo"] == "FooX" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["Foo"] == "FooX" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingAllConflictingAliasesFromMultiProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/aPkg/Sources/A/main.swift",
                                    "/aPkg/Sources/A/file.swift",
                                    "/bPkg/Sources/B/file.swift",
                                    "/bPkg/Sources/Utils/file.swift",
                                    "/cPkg/Sources/C/file.swift",
                                    "/cPkg/Sources/Log/file.swift",
                                    "/dPkg/Sources/D/file.swift",
                                    "/dPkg/Sources/Utils/file.swift",
                                    "/dPkg/Sources/Log/file.swift",
                                    "/gPkg/Sources/G/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "gPkg",
                    path: .init("/gPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "G", type: .library(.automatic), targets: ["G"]),
                    ],
                    targets: [
                        TargetDescription(name: "G",
                                          dependencies: [.product(name: "D",
                                                                  package: "dPkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "dPkg",
                    path: .init("/dPkg"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"]),
                    ],
                    targets: [
                        TargetDescription(name: "D", dependencies: ["Utils", "Log"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Log", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "cPkg",
                    path: .init("/cPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"]),
                        ProductDescription(name: "LogInC", type: .library(.automatic), targets: ["Log"]),
                    ],
                    targets: [
                        TargetDescription(name: "C", dependencies: ["Log"]),
                        TargetDescription(name: "Log",
                                          dependencies: [
                                            .product(name: "D",
                                                     package: "dPkg",
                                                     moduleAliases: ["Log" : "ZLog"]
                                                    ),
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bPkg",
                    path: .init("/bPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/cPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "C",
                                                     package: "cPkg",
                                                     moduleAliases: ["Utils": "YUtils",
                                                                     "Log": "YLog"
                                                                    ]
                                            ),
                                          ]),
                        TargetDescription(name: "Utils", dependencies: [])
                    ]),
                Manifest.createRootManifest(
                    name: "aPkg",
                    path: .init("/aPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/gPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "G",
                                                     package: "gPkg"),
                                            .product(name: "B",
                                                     package: "bPkg",
                                                     moduleAliases: ["Utils": "XUtils",
                                                                     "YLog": "XLog"]
                                                    ),
                                          ]
                                         ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(9)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "C" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?["Utils"] == "YUtils" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XLog" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?["Utils"] == "YUtils" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "D" && $0.target.moduleAliases?["Utils"] == "YUtils" && $0.target.moduleAliases?["Log"] == "ZLog" && $0.target.moduleAliases?.count == 2})
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "YUtils" && $0.target.moduleAliases?["Utils"] == "YUtils" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "ZLog" && $0.target.moduleAliases?["Log"] == "ZLog" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "G" && $0.target.moduleAliases?["Utils"] == "YUtils" && $0.target.moduleAliases?["Log"] == "ZLog" && $0.target.moduleAliases?.count == 2})
    }

    func testModuleAliasingSomeConflictingAliasesInMultiProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/aPkg/Sources/A/main.swift",
                                    "/aPkg/Sources/A/file.swift",
                                    "/bPkg/Sources/B/file.swift",
                                    "/cPkg/Sources/C/file.swift",
                                    "/dPkg/Sources/D/file.swift",
                                    "/dPkg/Sources/Utils/file.swift",
                                    "/dPkg/Sources/Log/file.swift",
                                    "/gPkg/Sources/G/file.swift",
                                    "/hPkg/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "hPkg",
                    path: .init("/hPkg"),
                    dependencies: [
                    ],
                    products: [
                        ProductDescription(name: "H", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gPkg",
                    path: .init("/gPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/hPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "G", type: .library(.automatic), targets: ["G"]),
                    ],
                    targets: [
                        TargetDescription(name: "G",
                                          dependencies: [.product(name: "H",
                                                                  package: "hPkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "dPkg",
                    path: .init("/dPkg"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"]),
                    ],
                    targets: [
                        TargetDescription(name: "D", dependencies: ["Utils", "Log"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Log", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "cPkg",
                    path: .init("/cPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"]),
                    ],
                    targets: [
                        TargetDescription(name: "C",
                                          dependencies: [
                                            .product(name: "D",
                                                     package: "dPkg",
                                                     moduleAliases: ["Log" : "ZLog"]
                                                    ),
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bPkg",
                    path: .init("/bPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/cPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            .product(name: "C",
                                                     package: "cPkg",
                                                     moduleAliases: ["Utils": "YUtils",
                                                                     "ZLog": "YLog"
                                                                    ]
                                            ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "aPkg",
                    path: .init("/aPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/gPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "B",
                                                     package: "bPkg",
                                                     moduleAliases: ["YUtils": "XUtils",
                                                                     "YLog": "XLog"]
                                                    ),
                                            .product(name: "G",
                                                     package: "gPkg",
                                                     moduleAliases: ["Utils": "GUtils"]),
                                          ]
                                         ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(8)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "C" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "D" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2})
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XLog" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "G" && $0.target.moduleAliases?["Utils"] == "GUtils" && $0.target.moduleAliases?.count == 1})
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "GUtils" && $0.target.moduleAliases?["Utils"] == "GUtils" && $0.target.moduleAliases?.count == 1})
    }

    func testModuleAliasingMergeAliasesOfSameTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/aPkg/Sources/A/main.swift",
                                    "/aPkg/Sources/A/file.swift",
                                    "/bPkg/Sources/B/file.swift",
                                    "/cPkg/Sources/C/file.swift",
                                    "/dPkg/Sources/D/file.swift",
                                    "/dPkg/Sources/Utils/file.swift",
                                    "/dPkg/Sources/Log/file.swift",
                                    "/gPkg/Sources/G/file.swift",
                                    "/hPkg/Sources/H/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "hPkg",
                    path: .init("/hPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "H", type: .library(.automatic), targets: ["H"]),
                    ],
                    targets: [
                        TargetDescription(name: "H",
                                          dependencies: [.product(name: "D",
                                                                  package: "dPkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gPkg",
                    path: .init("/gPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/hPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "G", type: .library(.automatic), targets: ["G"]),
                    ],
                    targets: [
                        TargetDescription(name: "G",
                                          dependencies: [.product(name: "H",
                                                                  package: "hPkg",
                                                                  moduleAliases: [
                                                                    "Utils": "GUtils",
                                                                    "Log": "GLog"
                                                                  ]
                                                                 )
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "dPkg",
                    path: .init("/dPkg"),
                    products: [
                        ProductDescription(name: "D", type: .library(.automatic), targets: ["D"]),
                    ],
                    targets: [
                        TargetDescription(name: "D", dependencies: ["Utils", "Log"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Log", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "cPkg",
                    path: .init("/cPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/dPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "C", type: .library(.automatic), targets: ["C"]),
                    ],
                    targets: [
                        TargetDescription(name: "C",
                                          dependencies: [
                                            .product(name: "D",
                                                     package: "dPkg",
                                                     moduleAliases: ["Log" : "ZLog"]
                                                    ),
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bPkg",
                    path: .init("/bPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/cPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            .product(name: "C",
                                                     package: "cPkg",
                                                     moduleAliases: ["Utils": "YUtils",
                                                                     "ZLog": "YLog"
                                                                    ]
                                            ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "aPkg",
                    path: .init("/aPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/gPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "G",
                                                     package: "gPkg"),
                                            .product(name: "B",
                                                     package: "bPkg",
                                                     moduleAliases: ["YUtils": "XUtils",
                                                                     "YLog": "XLog"]
                                                    ),
                                            ]
                                         ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(8)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "C" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?.count == 2 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "D" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2})
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XLog" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 1 })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "G" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2})
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "H" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["Log"] == "XLog" && $0.target.moduleAliases?.count == 2})
    }

    func testModuleAliasingOverrideSameNameTargetAndDepWithAliases() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file1.swift",
                                    "/appPkg/Sources/Render/file2.swift",
                                    "/libPkg/Sources/Lib/fileLib.swift",
                                    "/gamePkg/Sources/Game/fileGame.swift",
                                    "/gamePkg/Sources/Render/fileRender.swift",
                                    "/gamePkg/Sources/Utils/fileUtils.swift",
                                    "/drawPkg/Sources/Render/fileDraw.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "drawPkg",
                    path: .init("/drawPkg"),
                    products: [
                        ProductDescription(name: "DrawProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gamePkg",
                    path: .init("/gamePkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/drawPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Game", type: .library(.automatic), targets: ["Game"]),
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "RenderProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Game", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render",
                                          dependencies: [
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"]
                                          )]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "libPkg",
                    path: .init("/libPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/gamePkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "LibProd", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib",
                                          dependencies: [
                                            .product(name: "Game",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Utils": "GameUtils"]
                                                                 ),
                                                         .product(name: "RenderProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Render": "GameRender"]
                                                                 )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/libPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         "Render",
                                                         .product(name: "LibProd",
                                                                  package: "libPkg",
                                                                  moduleAliases: ["GameUtils": "LibUtils", "GameRender": "LibRender"]
                                                        )]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(8)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" && $0.target.moduleAliases?["Utils"] == "LibUtils" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibRender" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibUtils" && $0.target.moduleAliases?["Utils"] == "LibUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Game" && $0.target.moduleAliases?["Utils"] == "LibUtils" && $0.target.moduleAliases?["Render"] == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "DrawRender" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Render" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "GameUtils"})

    }

    func testModuleAliasingAddOverrideAliasesUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file1.swift",
                                    "/appPkg/Sources/Render/file2.swift",
                                    "/libPkg/Sources/Lib/fileLib.swift",
                                    "/gamePkg/Sources/Render/fileRender.swift",
                                    "/gamePkg/Sources/Utils/fileUtils.swift",
                                    "/drawPkg/Sources/Render/fileDraw.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "drawPkg",
                    path: .init("/drawPkg"),
                    products: [
                        ProductDescription(name: "DrawProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gamePkg",
                    path: .init("/gamePkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/drawPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Game", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "RenderProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Game", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render",
                                          dependencies: [
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"]
                                          )]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "libPkg",
                    path: .init("/libPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/gamePkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "LibProd", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib",
                                          dependencies: [.product(name: "UtilsProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Utils": "GameUtils"]
                                                                 ),
                                                         .product(name: "RenderProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Render": "GameRender"]
                                                                 )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/libPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         "Render",
                                                         .product(name: "LibProd",
                                                                  package: "libPkg"
                                                        )]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(7)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" && $0.target.moduleAliases?["Utils"] == "GameUtils" && $0.target.moduleAliases?["Render"] == "GameRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "GameRender" && $0.target.moduleAliases?["Render"] == "GameRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "GameUtils" && $0.target.moduleAliases?["Utils"] == "GameUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "DrawRender" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Render" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingOverrideUpstreamTargetsWithAliases() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file1.swift",
                                    "/appPkg/Sources/Render/file2.swift",
                                    "/libPkg/Sources/Lib/fileLib.swift",
                                    "/gamePkg/Sources/Scene/fileScene.swift",
                                    "/gamePkg/Sources/Render/fileRender.swift",
                                    "/gamePkg/Sources/Utils/fileUtils.swift",
                                    "/drawPkg/Sources/Render/fileDraw.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "drawPkg",
                    path: .init("/drawPkg"),
                    products: [
                        ProductDescription(name: "DrawProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gamePkg",
                    path: .init("/gamePkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/drawPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Game", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "RenderProd", type: .library(.automatic), targets: ["Render"]),
                        ProductDescription(name: "SceneProd", type: .library(.automatic), targets: ["Scene"]),
                    ],
                    targets: [
                        TargetDescription(name: "Game", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                        TargetDescription(name: "Scene",
                                          dependencies: [
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"]
                                          )]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "libPkg",
                    path: .init("/libPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/gamePkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "LibProd", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib",
                                          dependencies: [.product(name: "UtilsProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Utils": "GameUtils"]
                                                                 ),
                                                         .product(name: "RenderProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Render": "GameRender"]
                                                                 ),
                                                         .product(name: "SceneProd",
                                                                  package: "gamePkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/libPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         "Render",
                                                         .product(name: "LibProd",
                                                                  package: "libPkg"
                                                        )]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(8)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" && $0.target.moduleAliases?["Utils"] == "GameUtils" && $0.target.moduleAliases?["Render"] == "GameRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "GameRender" && $0.target.moduleAliases?["Render"] == "GameRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "GameUtils" && $0.target.moduleAliases?["Utils"] == "GameUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Scene" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "DrawRender" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Render" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingOverrideUpstreamTargetsWithAliasesMultipleAliasesInProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file1.swift",
                                    "/appPkg/Sources/Render/file2.swift",
                                    "/libPkg/Sources/Lib/fileLib.swift",
                                    "/gamePkg/Sources/Game/fileGame.swift",
                                    "/gamePkg/Sources/Utils/fileUtils.swift",
                                    "/drawPkg/Sources/Render/fileDraw.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "drawPkg",
                    path: .init("/drawPkg"),
                    products: [
                        ProductDescription(name: "DrawProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gamePkg",
                    path: .init("/gamePkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/drawPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "GameProd", type: .library(.automatic), targets: ["Game"]),
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Game",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"])
                                          ]),
                        TargetDescription(name: "Utils",
                                          dependencies: [
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"])
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "libPkg",
                    path: .init("/libPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/gamePkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "LibProd", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib",
                                          dependencies: [.product(name: "UtilsProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Utils": "GameUtils", "Render": "GameRender"]
                                                                 ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/libPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         "Render",
                                                         .product(name: "LibProd",
                                                                  package: "libPkg",
                                                                  moduleAliases: ["GameUtils": "LibUtils", "GameRender": "LibRender"]
                                                        )]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(7)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" && $0.target.moduleAliases?["Utils"] == "LibUtils" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibRender" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibUtils" && $0.target.moduleAliases?["Utils"] == "LibUtils" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "DrawRender" || $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Game" && $0.target.moduleAliases?["Utils"] == "LibUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Render" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingOverrideUpstreamTargetsWithAliasesDownstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file1.swift",
                                    "/appPkg/Sources/Render/file2.swift",
                                    "/libPkg/Sources/Lib/fileLib.swift",
                                    "/gamePkg/Sources/Scene/fileScene.swift",
                                    "/gamePkg/Sources/Render/fileRender.swift",
                                    "/gamePkg/Sources/Utils/fileUtils.swift",
                                    "/gamePkg/Sources/Game/fileGame.swift",
                                    "/drawPkg/Sources/Render/fileDraw.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "drawPkg",
                    path: .init("/drawPkg"),
                    products: [
                        ProductDescription(name: "DrawProd", type: .library(.automatic), targets: ["Render"]),
                    ],
                    targets: [
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "gamePkg",
                    path: .init("/gamePkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/drawPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Game", type: .library(.automatic), targets: ["Game"]),
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "RenderProd", type: .library(.automatic), targets: ["Render"]),
                        ProductDescription(name: "SceneProd", type: .library(.automatic), targets: ["Scene"]),
                    ],
                    targets: [
                        TargetDescription(name: "Game", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                        TargetDescription(name: "Scene",
                                          dependencies: [
                                            .product(name: "DrawProd",
                                                     package: "drawPkg",
                                                     moduleAliases: ["Render": "DrawRender"]
                                          )]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "libPkg",
                    path: .init("/libPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/gamePkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "LibProd", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib",
                                          dependencies: [.product(name: "UtilsProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Utils": "GameUtils"]
                                                                 ),
                                                         .product(name: "RenderProd",
                                                                  package: "gamePkg",
                                                                  moduleAliases: ["Render": "GameRender"]
                                                                 ),
                                                         .product(name: "SceneProd",
                                                                  package: "gamePkg"
                                                                 )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/libPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         "Render",
                                                         .product(name: "LibProd",
                                                                  package: "libPkg",
                                                                  moduleAliases: ["GameUtils": "LibUtils", "GameRender": "LibRender"]
                                                        )]),
                        TargetDescription(name: "Utils", dependencies: []),
                        TargetDescription(name: "Render", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(9)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" && $0.target.moduleAliases?["Utils"] == "LibUtils" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibRender" && $0.target.moduleAliases?["Render"] == "LibRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "LibUtils" && $0.target.moduleAliases?["Utils"] == "LibUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Game" && $0.target.moduleAliases?["Utils"] == "LibUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Scene" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "DrawRender" && $0.target.moduleAliases?["Render"] == "DrawRender" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Render" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingSameTargetFromUpstreamWithoutAlias() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/MyLogging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "barPkg"
                                                                 )]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["MyLogging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]),
                                                         .product(name: "Logging",
                                                                  package: "barPkg")
                                          ]),
                        TargetDescription(name: "MyLogging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "MyLogging" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingDuplicateTargetNamesFromMultiplePkgs() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/MyLogging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/carPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "carPkg",
                    path: .init("/carPkg"),
                    products: [
                        ProductDescription(name: "CarLog", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "BarLog", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "BarLog",
                                                                  package: "barPkg"
                                                                 )]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/carPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["MyLogging",
                                                         .product(name: "UtilsProd",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]),
                                                         .product(name: "CarLog",
                                                                  package: "carPkg",
                                                                  moduleAliases: ["Logging": "CarLogging"])
                                          ]),
                        TargetDescription(name: "MyLogging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(5)

        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "CarLogging" && $0.target.moduleAliases?["Logging"] == "CarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "MyLogging" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingTargetAndProductTargetWithSameName() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                    "/appPkg/Sources/App/main.swift",
                                    "/appPkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/xpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: ["Utils",
                                                         .product(name: "X",
                                                                  package: "xpkg",
                                                                  moduleAliases: ["Utils": "XUtils"])
                                          ]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingProductTargetsWithSameName1() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                    "/appPkg/Sources/App/main.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/bpkg/Sources/B/file.swift",
                                    "/cpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "cpkg",
                    path: .init("/cpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "bpkg",
                    path: .init("/bpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/cpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "B", type: .library(.automatic), targets: ["B"]),
                    ],
                    targets: [
                        TargetDescription(name: "B",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "cpkg"
                                                    ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "B",
                                                     package: "bpkg"
                                                    ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "ypkg"
                                                    ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [
                                            .product(name: "X",
                                                     package: "xpkg",
                                                     moduleAliases: ["Utils": "XUtils"]
                                                    ),
                                            .product(name: "A",
                                                     package: "apkg",
                                                     moduleAliases: ["Utils": "AUtils"]
                                                     )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(6)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "B" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingUpstreamProductTargetsWithSameName2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                    "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/bpkg/Sources/Utils/file.swift",
                                    "/cpkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/zpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "zpkg",
                    path: .init("/zpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/zpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "zpkg"),
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils": "YUtils"]
                                                     )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "cpkg",
                    path: .init("/cpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "bpkg",
                    path: .init("/bpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/cpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "cpkg"),
                                            .product(name: "Utils",
                                                     package: "bpkg",
                                                     moduleAliases: ["Utils": "BUtils"]
                                                     )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [
                                            .product(name: "X",
                                                     package: "xpkg",
                                                     moduleAliases: ["Utils": "XUtils"]
                                                    ),
                                            .product(name: "A",
                                                     package: "apkg",
                                                     moduleAliases: ["Utils": "AUtils"]
                                                    )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(7)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "YUtils" && $0.target.moduleAliases?["Utils"] == "YUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BUtils" && $0.target.moduleAliases?["Utils"] == "BUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
    }
    func testModuleAliasingUpstreamProductTargetsWithSameName3() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                    "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/apkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/zpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "zpkg",
                    path: .init("/zpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/zpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "zpkg"),
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils": "YUtils"]
                                                     )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A", dependencies: ["Utils"]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [
                                            .product(name: "X",
                                                     package: "xpkg"
                                                    ),
                                            .product(name: "A",
                                                     package: "apkg",
                                                     moduleAliases: ["Utils": "AUtils"]
                                                    )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(6)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "YUtils" && $0.target.moduleAliases?["Utils"] == "YUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingUpstreamProductTargetsWithSameName4() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                    "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/apkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/zpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "zpkg",
                    path: .init("/zpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/zpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "zpkg"),
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils": "YUtils"]
                                                     )
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [
                                            .product(name: "X",
                                                     package: "xpkg",
                                                     moduleAliases: ["Utils": "XUtils"]
                                                    ),
                                            .product(name: "A",
                                                     package: "apkg",
                                                     moduleAliases: ["Utils": "AUtils"]
                                                    )
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(5)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "YUtils" && $0.target.moduleAliases?["Utils"] == "YUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingChainedAliases1() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/apkg/Sources/Utils/file.swift",
                                    "/bpkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/xpkg/Sources/Utils/file.swift",
                                    "/ypkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    )
                                            ]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bpkg",
                    path: .init("/bpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bpkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "Utils",
                                                     package: "bpkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    )
                                            ]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [.product(name: "A",
                                                                  package: "apkg",
                                                                  moduleAliases: ["Utils": "AUtils", "FooUtils": "AFooUtils"]),
                                                         .product(name: "X",
                                                                  package: "xpkg",
                                                                  moduleAliases: ["Utils": "XUtils", "FooUtils": "XFooUtils"])
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(7)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "AUtils" && $0.target.moduleAliases?["FooUtils"] == "AFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["Utils"] == "XUtils" && $0.target.moduleAliases?["FooUtils"] == "XFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AFooUtils" && $0.target.moduleAliases?["Utils"] == "AFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XFooUtils" && $0.target.moduleAliases?["Utils"] == "XFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingChainedAliases2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/apkg/Sources/Utils/file.swift",
                                    "/bpkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/xpkg/Sources/Utils/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/zpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "zpkg",
                    path: .init("/zpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/zpkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    ),
                                            .product(name: "Utils",
                                                     package: "zpkg"
                                                    )
                                            ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bpkg",
                    path: .init("/bpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bpkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "Utils",
                                                     package: "bpkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    )
                                            ]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [.product(name: "A",
                                                                  package: "apkg",
                                                                  moduleAliases: ["Utils": "AUtils", "FooUtils": "AFUtils"]),
                                                         .product(name: "X",
                                                                  package: "xpkg",
                                                                  moduleAliases: ["FooUtils": "XFUtils"])
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(7)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "AUtils" && $0.target.moduleAliases?["FooUtils"] == "AFUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AFUtils" && $0.target.moduleAliases?["Utils"] == "AFUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["FooUtils"] == "XFUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XFUtils" && $0.target.moduleAliases?["Utils"] == "XFUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingChainedAliases3() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/appPkg/Sources/App/main.swift",
                                    "/apkg/Sources/A/file.swift",
                                    "/apkg/Sources/Utils/file.swift",
                                    "/bpkg/Sources/Utils/file.swift",
                                    "/xpkg/Sources/X/file.swift",
                                    "/xpkg/Sources/Utils/file.swift",
                                    "/ypkg/Sources/Utils/file.swift",
                                    "/zpkg/Sources/Utils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "zpkg",
                    path: .init("/zpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "ypkg",
                    path: .init("/ypkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "xpkg",
                    path: .init("/xpkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ypkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/zpkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "X", type: .library(.automatic), targets: ["X"]),
                    ],
                    targets: [
                        TargetDescription(name: "X",
                                          dependencies: [
                                            .product(name: "Utils",
                                                     package: "ypkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    ),
                                            .product(name: "Utils",
                                                     package: "zpkg",
                                                     moduleAliases: ["Utils" : "ZUtils"]
                                                    )
                                            ]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "bpkg",
                    path: .init("/bpkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "apkg",
                    path: .init("/apkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/bpkg"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    products: [
                        ProductDescription(name: "A", type: .library(.automatic), targets: ["A"]),
                    ],
                    targets: [
                        TargetDescription(name: "A",
                                          dependencies: [
                                            "Utils",
                                            .product(name: "Utils",
                                                     package: "bpkg",
                                                     moduleAliases: ["Utils" : "FooUtils"]
                                                    )
                                            ]),
                        TargetDescription(name: "Utils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "appPkg",
                    path: .init("/appPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/apkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/xpkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "App",
                                          dependencies: [.product(name: "A",
                                                                  package: "apkg",
                                                                  moduleAliases: ["Utils": "AUtils", "FooUtils": "AFooUtils"]),
                                                         .product(name: "X",
                                                                  package: "xpkg",
                                                                  moduleAliases: ["ZUtils": "XUtils", "FooUtils": "XFooUtils"])
                                          ]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(7)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "A" && $0.target.moduleAliases?["Utils"] == "AUtils" && $0.target.moduleAliases?["FooUtils"] == "AFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AUtils" && $0.target.moduleAliases?["Utils"] == "AUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "AFooUtils" && $0.target.moduleAliases?["Utils"] == "AFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "X" && $0.target.moduleAliases?["ZUtils"] == "XUtils" && $0.target.moduleAliases?["FooUtils"] == "XFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" && $0.target.moduleAliases?["Utils"] == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XFooUtils" && $0.target.moduleAliases?["Utils"] == "XFooUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "App" && $0.target.moduleAliases == nil })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases == nil })
    }
}
