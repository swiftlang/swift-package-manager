/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
import Utility

@testable import PackageLoading

extension Manifest {
    // FIXME: Can be replaced with Manifest.createV4Manifest.
    fileprivate convenience init(
        name: String,
        path: String = "/",
        url: String = "/",
        legacyProducts: [ProductDescription] = [],
        legacyExclude: [String] = [],
        version: Utility.Version? = nil,
        interpreterFlags: [String] = [],
        manifestVersion: ManifestVersion = .v4,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
        dependencies: [PackageDependencyDescription] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = []
    ) {
        self.init(
            name: name,
            path: AbsolutePath(path).appending(component: Manifest.filename),
            url: url,
            legacyProducts: legacyProducts,
            legacyExclude: legacyExclude,
            version: version,
            interpreterFlags: interpreterFlags,
            manifestVersion: manifestVersion,
            pkgConfig: pkgConfig,
            providers: providers,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard,
            swiftLanguageVersions: swiftLanguageVersions,
            dependencies: dependencies,
            products: products,
            targets: targets
        )
    }
}

class PackageBuilderV4Tests: XCTestCase {

    func testDeclaredExecutableProducts() {
        // Check that declaring executable product doesn't collide with the
        // inferred products.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/foo/foo.swift"
        )

        var manifest = Manifest(
            name: "pkg",
            products: [
                ProductDescription(name: "exec", type: .executable, targets: ["exec", "foo"]),
            ],
            targets: [
                TargetDescription(name: "foo"),
                TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec", "foo"])
            }
        }

        manifest = Manifest(
            name: "pkg",
            products: [],
            targets: [
                TargetDescription(name: "foo"),
                TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec"])
            }
        }

        // If we already have an explicit product, we shouldn't create an
        // implicit one.
        manifest = Manifest(
            name: "pkg",
            products: [
                ProductDescription(name: "exec1", type: .executable, targets: ["exec"]),
            ],
            targets: [
                TargetDescription(name: "foo"),
                TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "exe", path: "swift/exe"),
                TargetDescription(name: "tests", path: "swift/tests", type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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

    func testLinuxMainSearch() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/foo.swift",
            "/pkg/footests.swift"
        )

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "exe",
                    path: "./",
                    sources: ["foo.swift"]
                ),
                TargetDescription(
                    name: "tests",
                    path: "./",
                    sources: ["footests.swift"],
                    type: .test
                ),
            ]
        )
        PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { result in
            result.checkModule("exe") { _ in }
            result.checkModule("tests") { _ in }

            result.checkProduct("pkgPackageTests") { productResult in
                productResult.check(type: .test, targets: ["tests"])
                productResult.check(linuxMainPath: nil)
            }
        }
    }

    func testLinuxMainError() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/LinuxMain.swift",
            "/swift/LinuxMain.swift",
            "/swift/tests/footests.swift"
        )

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "tests",
                    path: "swift/tests",
                    type: .test
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "exe",
                    path: "mah/target/exe",
                    sources: ["swift"]),
                TargetDescription(
                    name: "clib",
                    path: "mah/target/exe",
                    sources: ["foo.c"]),
                TargetDescription(
                    name: "foo"),
                TargetDescription(
                    name: "bar",
                    path: "bar",
                    exclude: ["bar/excluded.swift", "bar/fixture"],
                    sources: ["bar"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in

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

        var manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "bar",
                    path: "target/bar"),
                TargetDescription(
                    name: "barTests",
                    path: "target/bar/Tests",
                    type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("target 'barTests' has sources overlapping sources: /target/bar/Tests/barTests.swift")
        }

        manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "bar",
                    path: "target/bar",
                    exclude: ["Tests"]),
                TargetDescription(
                    name: "barTests",
                    path: "target/bar/Tests",
                    type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in

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

        let manifest = Manifest(
            name: "Foo",
            targets: [
                TargetDescription(
                    name: "Foo",
                    publicHeadersPath: "inc"),
                TargetDescription(
                    name: "Bar"),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in

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

        let manifest = Manifest(
            name: "Foo",
            targets: [
                TargetDescription(name: "A"),
                TargetDescription(name: "TheTestOfA", dependencies: ["A"], type: .test),
                TargetDescription(name: "ATests", type: .test),
                TargetDescription(name: "B", type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in

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

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "foo"),
                TargetDescription(name: "fooTests", type: .test),
                TargetDescription(name: "barTests", type: .test),
            ]
        )

        PackageBuilderTester(manifest, shouldCreateMultipleTestProducts: true, in: fs) { result in
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

        PackageBuilderTester(manifest, shouldCreateMultipleTestProducts: false, in: fs) { result in
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
        var manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "Foo", dependencies: ["Bar"]),
                TargetDescription(name: "Bar"),
                TargetDescription(name: "Baz"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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
        manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "Foo", dependencies: ["Bar"]),
                TargetDescription(name: "Bar", dependencies: ["Baz"]),
                TargetDescription(name: "Baz"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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

        let manifest = Manifest(
            name: "A",
            targets: [
                TargetDescription(name: "A"),
                TargetDescription(name: "B"),
                TargetDescription(name: "A"),
                TargetDescription(name: "B"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("duplicate targets found: A, B")
        }
    }

    func testTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "Bar"),
                TargetDescription(name: "Baz"),
                TargetDescription(
                    name: "Foo",
                    dependencies: ["Bar", "Baz", "Bam"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in

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

            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "Random"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("could not find source files for target(s): Random; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/src/pkg/Foo.swift")
            // Reference an invalid dependency.
            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg", dependencies: [.target(name: "Foo")]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("could not find source files for target(s): Foo; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference self in dependencies.
            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg", dependencies: [.target(name: "pkg")]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg -> pkg")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference invalid target.
            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "foo"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("could not find source files for target(s): foo; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg1/Foo.swift",
                "/Sources/pkg2/Foo.swift",
                "/Sources/pkg3/Foo.swift"
            )
            // Cyclic dependency.
            var manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    TargetDescription(name: "pkg2", dependencies: ["pkg3"]),
                    TargetDescription(name: "pkg3", dependencies: ["pkg1"]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg1")
            }

            manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    TargetDescription(name: "pkg2", dependencies: ["pkg3"]),
                    TargetDescription(name: "pkg3", dependencies: ["pkg2"]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg2")
            }
        }

        do {
            // Reference a target which doesn't have sources.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg1/Foo.swift",
                "/Sources/pkg2/readme.txt")

            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    TargetDescription(name: "pkg2"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
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

            var manifest = Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Foo", publicHeadersPath: "../inc"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("public headers directory path for 'Foo' is invalid or not contained in the target")
            }

            manifest = Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Bar", publicHeadersPath: "inc/../../../foo"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("public headers directory path for 'Bar' is invalid or not contained in the target")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Foo", path: "../foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { result in
                result.checkDiagnostic("target 'Foo' in package 'Foo' is outside the package root")
            }
        }
        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Foo", path: "/foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { result in
                result.checkDiagnostic("target path \'/foo\' is not supported; it should be relative to package root")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Foo", path: "~/foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { result in
                result.checkDiagnostic("target path \'~/foo\' is not supported; it should be relative to package root")
            }
        }
    }

    func testExecutableAsADep() {
        // Executable as dependency.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/lib/lib.swift")

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "lib", dependencies: ["exec"]),
                TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
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

        var manifest = Manifest(
            name: "pkg",
            pkgConfig: "foo"
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("configuration of package 'pkg' is invalid; the 'pkgConfig' property can only be used with a System Module Package")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        manifest = Manifest(
            name: "pkg",
            providers: [.brew(["foo"])]
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("configuration of package 'pkg' is invalid; the 'providers' property can only be used with a System Module Package")
        }
    }

    func testResolvesSystemModulePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap")

        let manifest = Manifest(name: "SystemModulePackage")
        PackageBuilderTester(manifest, in: fs) { result in
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

        func createManifest(swiftVersions: [SwiftLanguageVersion]?) -> Manifest {
            return Manifest(
                name: "pkg",
                swiftLanguageVersions: swiftVersions,
                targets: [
                    TargetDescription(name: "foo", path: "foo"),
                ]
            )
        }

        var manifest = createManifest(swiftVersions: [.v3, .v4])

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: "4")
            }
            result.checkProduct("foo") { _ in }
        }

        manifest = createManifest(swiftVersions: [.v3])
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: "3")
            }
            result.checkProduct("foo") { _ in }
        }

        manifest = createManifest(swiftVersions: [.v4])
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: "4")
            }
            result.checkProduct("foo") { _ in }
        }

        manifest = createManifest(swiftVersions: nil)
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(swiftVersion: "4")
            }
            result.checkProduct("foo") { _ in }
        }

        manifest = createManifest(swiftVersions: [])
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("package 'pkg' supported Swift language versions is empty")
        }

        // package.swiftLanguageVersions = ["5", "6"]
        manifest = createManifest(
            swiftVersions: [SwiftLanguageVersion(string: "5")!, SwiftLanguageVersion(string: "6")!])
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("package \'pkg\' not compatible with current tools version (4.2.0); it supports: 5, 6")
        }
    }

    func testPredefinedTargetSearchError() {

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/src/Bar/Bar.swift")

            let manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    TargetDescription(name: "Bar"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("could not find source files for target(s): Bar; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }
        }

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/Tests/FooTests/Foo.swift",
                "/Source/BarTests/Foo.swift")

            var manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "BarTests", type: .test),
                    TargetDescription(name: "FooTests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("could not find source files for target(s): BarTests; use the 'path' property in the Swift 4 manifest to set a custom target path")
            }

            // We should be able to fix this by using custom paths.
            manifest = Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "BarTests", path: "Source/BarTests", type: .test),
                    TargetDescription(name: "FooTests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
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

        let manifest = Manifest(
            name: "Foo",
            targets: [
                TargetDescription(name: "A"),
                TargetDescription(name: "ATests", type: .test),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in

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

    func testExcludes() {
        // The exclude should win if a file is in exclude as well as sources.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/bar/barExcluded.swift",
            "/Sources/bar/bar.swift"
        )

        let manifest = Manifest(
            name: "pkg",
            targets: [
                TargetDescription(
                    name: "bar",
                    exclude: ["barExcluded.swift",],
                    sources: ["bar.swift", "barExcluded.swift"]
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("bar") { moduleResult in
                moduleResult.check(c99name: "bar", type: .library)
                moduleResult.checkSources(root: "/Sources/bar", paths: "bar.swift")
            }
        }
    }
    
    func testDuplicateProducts() {
        // Check that declaring executable product doesn't collide with the
        // inferred products.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/foo.swift"
        )
        
        let manifest = Manifest(
            name: "pkg",
            products: [
                ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
                ProductDescription(name: "foo", type: .library(.static), targets: ["foo"]),
                ProductDescription(name: "foo", type: .library(.dynamic), targets: ["foo"]),
                ProductDescription(name: "foo-dy", type: .library(.dynamic), targets: ["foo"]),
            ],
            targets: [
                TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkProduct("foo") { productResult in
                productResult.check(type: .library(.automatic), targets: ["foo"])
            }
            result.checkProduct("foo-dy") { productResult in
                productResult.check(type: .library(.dynamic), targets: ["foo"])
            }
            result.checkDiagnostic("Ignoring duplicate product 'foo' (static)")
            result.checkDiagnostic("Ignoring duplicate product 'foo' (dynamic)")
        }
    }

    func testSystemPackageDeclaresTargetsDiagnostic() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap",
            "/Sources/foo/main.swift",
            "/Sources/bar/main.swift"
        )

        let manifest = Manifest(
            name: "SystemModulePackage",
            targets: [
                TargetDescription(name: "foo"),
                TargetDescription(name: "bar"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("SystemModulePackage") { moduleResult in
                moduleResult.check(c99name: "SystemModulePackage", type: .systemModule)
                moduleResult.checkSources(root: "/")
            }
            result.checkDiagnostic("Ignoring declared target(s) 'foo, bar' in the system package")
        }
    }

    func testSystemLibraryTarget() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift"
        )

        let manifest = Manifest(
            name: "pkg",
            products: [
                ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo"]),
            ],
            targets: [
                TargetDescription(name: "foo", type: .system),
                TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(c99name: "foo", type: .systemModule)
                moduleResult.checkSources(root: "/Sources/foo")
            }
            result.checkModule("bar") { moduleResult in
                moduleResult.check(c99name: "bar", type: .library)
                moduleResult.checkSources(root: "/Sources/bar", paths: "bar.swift")
                moduleResult.check(dependencies: ["foo"])
            }
            result.checkProduct("foo") { productResult in
                productResult.check(type: .library(.automatic), targets: ["foo"])
            }
        }
    }

    func testSystemLibraryTargetDiagnostics() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift"
        )

        var manifest = Manifest(
            name: "SystemModulePackage",
            products: [
                ProductDescription(name: "foo", type: .library(.automatic), targets: ["foo", "bar"]),
            ],
            targets: [
                TargetDescription(name: "foo", type: .system),
                TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("bar") { _ in }
            result.checkDiagnostic("system library product foo shouldn\'t have a type and contain only one target")
        }

        manifest = Manifest(
            name: "SystemModulePackage",
            products: [
                ProductDescription(name: "foo", type: .library(.static), targets: ["foo"]),
            ],
            targets: [
                TargetDescription(name: "foo", type: .system),
                TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("bar") { _ in }
            result.checkDiagnostic("system library product foo shouldn't have a type and contain only one target")
        }
    }

    static var allTests = [
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testCustomTargetDependencies", testCustomTargetDependencies),
        ("testCustomTargetPaths", testCustomTargetPaths),
        ("testCustomTargetPathsOverlap", testCustomTargetPathsOverlap),
        ("testDeclaredExecutableProducts", testDeclaredExecutableProducts),
        ("testDuplicateProducts", testDuplicateProducts),
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
        ("testExcludes", testExcludes),
        ("testSystemPackageDeclaresTargetsDiagnostic", testSystemPackageDeclaresTargetsDiagnostic),
        ("testSystemLibraryTarget", testSystemLibraryTarget),
        ("testSystemLibraryTargetDiagnostics", testSystemLibraryTargetDiagnostics),
        ("testLinuxMainSearch", testLinuxMainSearch),
    ]
}
