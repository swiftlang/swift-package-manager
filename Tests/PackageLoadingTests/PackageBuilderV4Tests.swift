/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import XCTest

import Basic
import PackageDescription4
import PackageModel
import Utility

@testable import PackageLoading

fileprivate typealias Package = PackageDescription4.Package

class PackageBuilderV4Tests: XCTestCase {

    func testDeclaredExecutableProducts() {
        // Check that declaring executable product doesn't collide with the
        // inferred products.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/foo/foo.swift"
        )

        let package = Package(
            name: "pkg",
            products: [
                .executable(name: "exec", targets: ["exec", "foo"]),
            ],
            targets: [
                .target(name: "foo"),
                .target(name: "exec"),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec", "foo"])
            }
        }

        package.products = []
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec"])
            }
        }

        // If we already have an explicit product, we shouldn't create an
        // implicit one.
        package.products = [
            .executable(name: "exec1", targets: ["exec"]),
        ]
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec1") { productResult in
                productResult.check(type: .executable, targets: ["exec"])
            }
        }
    }

    func testLinuxMain() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/swift/exe/foo.swift",
            "/LinuxMain.swift",
            "/swift/tests/footests.swift"
        )

        let package = Package(
            name: "pkg",
            targets: [
                .target(
                    name: "exe",
                    path: "swift/exe"
                ),
                .testTarget(
                    name: "tests",
                    path: "swift/tests"
                ),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("exe") { moduleResult in
                moduleResult.check(c99name: "exe", type: .library)
                moduleResult.checkSources(root: "/swift/exe", paths: "foo.swift")
            }

            result.checkModule("tests") { moduleResult in
                moduleResult.check(c99name: "tests", type: .test)
                moduleResult.checkSources(root: "/swift/tests", paths: "footests.swift")
            }

            result.checkProduct("pkgPackageTests") { productResult in
                productResult.check(type: .test, targets: ["tests"])
                productResult.check(linuxMainPath: "/LinuxMain.swift")
            }
        }
    }

    func testLinuxMainError() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/LinuxMain.swift",
            "/swift/LinuxMain.swift",
            "/swift/tests/footests.swift"
        )

        let package = Package(
            name: "pkg",
            targets: [
                .testTarget(
                    name: "tests",
                    path: "swift/tests"
                ),
            ]
        )

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("package 'pkg' has multiple linux main files: /LinuxMain.swift, /swift/LinuxMain.swift")
        }
    }

	func testCustomTargetPaths() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/mah/target/exe/swift/exe/main.swift",
            "/mah/target/exe/swift/exe/foo.swift",
            "/mah/target/exe/swift/bar.swift",
            "/mah/target/exe/shouldBeIgnored.swift",
            "/mah/target/exe/foo.c",
            "/Sources/foo/foo.swift",
            "/bar/bar/foo.swift",
            "/bar/bar/excluded.swift",
            "/bar/bar/fixture/fix1.swift",
            "/bar/bar/fixture/fix2.swift"
        )

        let package = Package(
            name: "pkg",
            targets: [
                .target(
                    name: "exe",
                    path: "mah/target/exe",
                    sources: ["swift"]),
                .target(
                    name: "clib",
                    path: "mah/target/exe",
                    sources: ["foo.c"]),
                .target(
                    name: "foo"),
                .target(
                    name: "bar",
                    path: "bar",
                    exclude: ["bar/excluded.swift", "bar/fixture"],
                    sources: ["bar"]),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            result.checkModule("exe") { moduleResult in
                moduleResult.check(c99name: "exe", type: .executable)
                moduleResult.checkSources(root: "/mah/target/exe",
                    paths: "swift/exe/main.swift", "swift/exe/foo.swift", "swift/bar.swift")
            }

            result.checkModule("clib") { moduleResult in
                moduleResult.check(c99name: "clib", type: .library)
                moduleResult.checkSources(root: "/mah/target/exe", paths: "foo.c")
            }

            result.checkModule("foo") { moduleResult in
                moduleResult.check(c99name: "foo", type: .library)
                moduleResult.checkSources(root: "/Sources/foo", paths: "foo.swift")
            }

            result.checkModule("bar") { moduleResult in
                moduleResult.check(c99name: "bar", type: .library)
                moduleResult.checkSources(root: "/bar", paths: "bar/foo.swift")
            }

            result.checkProduct("exe") { _ in }
        }
    }

    func testCustomTargetPathsOverlap() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/target/bar/bar.swift",
            "/target/bar/Tests/barTests.swift"
        )

        let package = Package(
            name: "pkg",
            targets: [
                .target(
                    name: "bar",
                    path: "target/bar"),
                .testTarget(
                    name: "barTests",
                    path: "target/bar/Tests"),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("target 'barTests' has sources overlapping sources: /target/bar/Tests/barTests.swift")
        }

        package.targets[0].exclude = ["Tests"]
        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            result.checkModule("bar") { moduleResult in
                moduleResult.check(c99name: "bar", type: .library)
                moduleResult.checkSources(root: "/target/bar", paths: "bar.swift")
            }

            result.checkModule("barTests") { moduleResult in
                moduleResult.check(c99name: "barTests", type: .test)
                moduleResult.checkSources(root: "/target/bar/Tests", paths: "barTests.swift")
            }

            result.checkProduct("pkgPackageTests")
        }
    }

    func testPublicHeadersPath() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/inc/module.modulemap",
            "/Sources/Foo/inc/Foo.h",
            "/Sources/Foo/Foo.c",
            "/Sources/Bar/include/module.modulemap",
            "/Sources/Bar/include/Bar.h",
            "/Sources/Bar/Bar.c"
        )

        let package = Package(
            name: "Foo",
            targets: [
                .target(name: "Foo", publicHeadersPath: "inc"),
                .target(name: "Bar"),
            ])

        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.c")
                moduleResult.check(includeDir: "/Sources/Foo/inc")
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "Bar.c")
                moduleResult.check(includeDir: "/Sources/Bar/include")
            }
        }
    }

    func testTestsLayoutsv4() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Tests/B/Foo.swift",
            "/Tests/ATests/Foo.swift",
            "/Tests/TheTestOfA/Foo.swift")

        let package = Package(
            name: "Foo",
            targets: [
                .target(name: "A"),
                .testTarget(name: "TheTestOfA", dependencies: ["A"]),
                .testTarget(name: "ATests"),
                .testTarget(name: "B"),
            ])

        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .executable)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.swift")
            }

            result.checkModule("TheTestOfA") { moduleResult in
                moduleResult.check(c99name: "TheTestOfA", type: .test)
                moduleResult.checkSources(root: "/Tests/TheTestOfA", paths: "Foo.swift")
                moduleResult.check(dependencies: ["A"])
            }

            result.checkModule("B") { moduleResult in
                moduleResult.check(c99name: "B", type: .test)
                moduleResult.checkSources(root: "/Tests/B", paths: "Foo.swift")
                moduleResult.check(dependencies: [])
            }

            result.checkModule("ATests") { moduleResult in
                moduleResult.check(c99name: "ATests", type: .test)
                moduleResult.checkSources(root: "/Tests/ATests", paths: "Foo.swift")
                moduleResult.check(dependencies: [])
            }

            result.checkProduct("FooPackageTests") { _ in }
            result.checkProduct("A") { _ in }
        }
    }

    func testMultipleTestProducts() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/foo.swift",
            "/Tests/fooTests/foo.swift",
            "/Tests/barTests/bar.swift"
        )
        let package = Package(
            name: "pkg",
            targets: [
                .target(name: "foo"),
                .testTarget(name: "fooTests"),
                .testTarget(name: "barTests"),
            ]
        )
        PackageBuilderTester(.v4(package), shouldCreateMultipleTestProducts: true, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("fooTests") { _ in }
            result.checkModule("barTests") { _ in }
            result.checkProduct("fooTests") { product in
                product.check(type: .test, targets: ["fooTests"])
            }
            result.checkProduct("barTests") { product in
                product.check(type: .test, targets: ["barTests"])
            }
        }

        PackageBuilderTester(.v4(package), shouldCreateMultipleTestProducts: false, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("fooTests") { _ in }
            result.checkModule("barTests") { _ in }
            result.checkProduct("pkgPackageTests") { product in
                product.check(type: .test, targets: ["barTests", "fooTests"])
            }
        }
    }

    func testCustomTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        // Direct.
        var package = Package(
            name: "pkg",
            targets: [
                .target(name: "Foo", dependencies: ["Bar"]),
                .target(name: "Bar"),
                .target(name: "Baz"),
            ]
        )

        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                moduleResult.check(dependencies: ["Bar"])
            }

            for target in ["Bar", "Baz"] {
                result.checkModule(target) { moduleResult in
                    moduleResult.check(c99name: target, type: .library)
                    moduleResult.checkSources(root: "/Sources/\(target)", paths: "\(target).swift")
                }
            }
        }

        // Transitive.
        package = Package(
            name: "pkg",
            targets: [
                .target(name: "Foo", dependencies: ["Bar"]),
                .target(name: "Bar", dependencies: ["Baz"]),
                .target(name: "Baz"),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                moduleResult.check(dependencies: ["Bar"])
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "Bar.swift")
                moduleResult.check(dependencies: ["Baz"])
            }

            result.checkModule("Baz") { moduleResult in
                moduleResult.check(c99name: "Baz", type: .library)
                moduleResult.checkSources(root: "/Sources/Baz", paths: "Baz.swift")
            }
        }
    }
    
    func testDuplicateTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Sources/A/foo.swift",
            "/Sources/B/bar.swift",
            "/Sources/C/baz.swift"
        )

        let package = Package(
            name: "A",
            targets: [
                .target(name: "A", dependencies: []),
                .target(name: "B", dependencies: []),
                .target(name: "A", dependencies: []),
                .target(name: "B", dependencies: []),
            ]
        )

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("duplicate targets found: A, B")
        }
    }

    func testTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        // We create a manifest which uses byName product dependencies.
        let package = Package(
            name: "pkg",
            targets: [
                .target(name: "Bar"),
                .target(name: "Baz"),
                .target(
                    name: "Foo",
                    dependencies: ["Bar", "Baz", "Bam"]
                ),
            ])

        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                moduleResult.check(dependencies: ["Bar", "Baz"])
                moduleResult.check(productDeps: [(name: "Bam", package: nil)])
            }

            for target in ["Bar", "Baz"] {
                result.checkModule(target) { moduleResult in
                    moduleResult.check(c99name: target, type: .library)
                    moduleResult.checkSources(root: "/Sources/\(target)", paths: "\(target).swift")
                }
            }
        }
    }

    func testManifestTargetDeclErrors() throws {
        do {
            // Reference a target which doesn't exist.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Foo.swift")
            let package = Package(name: "pkg", targets: [.target(name: "Random")])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("could not find target(s): Random; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/src/pkg/Foo.swift")
            // Reference an invalid dependency.
            let package = Package(
                name: "pkg",
                targets: [
                    .target(name: "pkg", dependencies: [.target(name: "Foo")]),
                ])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("could not find target(s): Foo; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference self in dependencies.
            let package = Package(name: "pkg", targets: [.target(name: "pkg", dependencies: ["pkg"])])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg -> pkg")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference invalid target.
            let package = Package(name: "pkg", targets: [.target(name: "foo")])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("could not find target(s): foo; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg1/Foo.swift",
                "/Sources/pkg2/Foo.swift",
                "/Sources/pkg3/Foo.swift"
            )
            // Cyclic dependency.
            var package = Package(name: "pkg", targets: [
                .target(name: "pkg1", dependencies: ["pkg2"]),
                .target(name: "pkg2", dependencies: ["pkg3"]),
                .target(name: "pkg3", dependencies: ["pkg1"]),
            ])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg1")
            }

            package = Package(name: "pkg", targets: [
                .target(name: "pkg1", dependencies: ["pkg2"]),
                .target(name: "pkg2", dependencies: ["pkg3"]),
                .target(name: "pkg3", dependencies: ["pkg2"]),
            ])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg2")
            }
        }

        do {
            // Reference a target which doesn't have sources.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg1/Foo.swift",
                "/Sources/pkg2/readme.txt")
            let package = Package(
                name: "pkg",
                targets: [
                    .target(name: "pkg1", dependencies: ["pkg2"]),
                    .target(name: "pkg2"),
            ])
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("target 'pkg2' in package 'pkg' contains no valid source files")
                result.checkModule("pkg1") { moduleResult in
                    moduleResult.check(c99name: "pkg1", type: .library)
                    moduleResult.checkSources(root: "/Sources/pkg1", paths: "Foo.swift")
                }
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/Foo/Foo.c",
                "/Sources/Bar/Bar.c")

            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: "Foo", publicHeadersPath: "../inc"),
                ])

            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("public headers directory path for 'Foo' is invalid or not contained in the target")
            }

            package.targets = [.target(name: "Bar", publicHeadersPath: "inc/../../../foo")]
            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("public headers directory path for 'Bar' is invalid or not contained in the target")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: "Foo", path: "../foo"),
                ])

            PackageBuilderTester(package, path: AbsolutePath("/pkg"), in: fs) { result in
                result.checkDiagnostic("target 'Foo' in package 'Foo' is outside the package root")
            }
        }
    }

    func testExecutableAsADep() {
        // Executable as dependency.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/lib/lib.swift")
        let package = Package(
            name: "pkg",
            targets: [
                .target(name: "lib", dependencies: ["exec"]),
                .target(name: "exec"),
            ])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("exec") { moduleResult in
                moduleResult.check(c99name: "exec", type: .executable)
                moduleResult.checkSources(root: "/Sources/exec", paths: "main.swift")
            }

            result.checkModule("lib") { moduleResult in
                moduleResult.check(c99name: "lib", type: .library)
                moduleResult.checkSources(root: "/Sources/lib", paths: "lib.swift")
            }

            result.checkProduct("exec")
        }
    }

    func testInvalidManifestConfigForNonSystemModules() {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift"
        )
        var package = Package(name: "pkg", pkgConfig: "foo")

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("configuration of package 'pkg' is invalid; the 'pkgConfig' property can only be used with a System Module Package")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        package = Package(name: "pkg", providers: [.brew(["foo"])])

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("configuration of package 'pkg' is invalid; the 'providers' property can only be used with a System Module Package")
        }
    }

    func testResolvesSystemModulePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap")

        let pkg = Package(name: "SystemModulePackage")
        PackageBuilderTester(pkg, in: fs) { result in
            result.checkModule("SystemModulePackage") { moduleResult in
                moduleResult.check(c99name: "SystemModulePackage", type: .systemModule)
                moduleResult.checkSources(root: "/")
            }
        }
    }

    func testCompatibleSwiftVersions() throws {
        // Single swift executable target.
        let fs = InMemoryFileSystem(emptyFiles:
            "/foo/main.swift"
        )

        let package = Package(
            name: "pkg",
            targets: [.target(name: "foo", path: "foo")],
            swiftLanguageVersions: [3, 4])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: 4)
            }
            result.checkProduct("foo") { _ in }
        }

        package.swiftLanguageVersions = [3]
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: 3)
            }
            result.checkProduct("foo") { _ in }
        }

        package.swiftLanguageVersions = [4]
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: 4)
            }
            result.checkProduct("foo") { _ in }
        }

        package.swiftLanguageVersions = nil
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: 4)
            }
            result.checkProduct("foo") { _ in }
        }

        package.swiftLanguageVersions = []
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("package 'pkg' supported Swift language versions is empty")
        }

        package.swiftLanguageVersions = [500, 600]
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("package \'pkg\' not compatible with current tools version (4); it supports: 500, 600")
        }
    }

    func testPredefinedTargetSearchError() {

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/src/Bar/Bar.swift")

            let package = Package(
                name: "pkg",
                targets: [
                    .target(name: "Foo", dependencies: ["Bar"]),
                    .target(name: "Bar"),
                ]
            )

            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("could not find target(s): Bar; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/Tests/FooTests/Foo.swift",
                "/Source/BarTests/Foo.swift")

            let package = Package(
                name: "pkg",
                targets: [
                    .testTarget(name: "BarTests"),
                    .testTarget(name: "FooTests"),
                ]
            )

            PackageBuilderTester(package, in: fs) { result in
                result.checkDiagnostic("could not find target(s): BarTests; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }

            // We should be able to fix this by using custom paths.
            package.targets[0] = .testTarget(name: "BarTests", path: "Source/BarTests")
            PackageBuilderTester(package, in: fs) { result in
                result.checkModule("BarTests") { moduleResult in
                    moduleResult.check(c99name: "BarTests", type: .test)
                }
                result.checkModule("FooTests") { moduleResult in
                    moduleResult.check(c99name: "FooTests", type: .test)
                }
                result.checkProduct("pkgPackageTests") { _ in }
            }
        }
    }

    func testSpecialTargetDir() {
        // Special directory should be src because both target and test target are under it.
        let fs = InMemoryFileSystem(emptyFiles:
            "/src/A/Foo.swift",
            "/src/ATests/Foo.swift")

        let package = Package(
            name: "Foo",
            targets: [
                .target(name: "A"),
                .testTarget(name: "ATests"),
            ]
        )

        PackageBuilderTester(package, in: fs) { result in

            result.checkPredefinedPaths(target: "/src", testTarget: "/src")

            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .library)
            }
            result.checkModule("ATests") { moduleResult in
                moduleResult.check(c99name: "ATests", type: .test)
            }

            result.checkProduct("FooPackageTests") { _ in }
        }
    }

    static var allTests = [
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testCustomTargetDependencies", testCustomTargetDependencies),
        ("testCustomTargetPaths", testCustomTargetPaths),
        ("testCustomTargetPathsOverlap", testCustomTargetPathsOverlap),
        ("testDeclaredExecutableProducts", testDeclaredExecutableProducts),
        ("testExecutableAsADep", testExecutableAsADep),
        ("testInvalidManifestConfigForNonSystemModules", testInvalidManifestConfigForNonSystemModules),
        ("testLinuxMain", testLinuxMain),
        ("testLinuxMainError", testLinuxMainError),
        ("testManifestTargetDeclErrors", testManifestTargetDeclErrors),
        ("testMultipleTestProducts", testMultipleTestProducts),
        ("testPublicHeadersPath", testPublicHeadersPath),
        ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
        ("testTargetDependencies", testTargetDependencies),
        ("testTestsLayoutsv4", testTestsLayoutsv4),
        ("testPredefinedTargetSearchError", testPredefinedTargetSearchError),
        ("testSpecialTargetDir", testSpecialTargetDir),
        ("testDuplicateTargets", testDuplicateTargets),
    ]
}
