/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import SPMTestSupport

import TSCBasic
import PackageModel
import TSCUtility

import PackageLoading

/// Tests for the handling of source layout conventions.
class PackageBuilderTests: XCTestCase {

    func testDotFilesAreIgnored() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/.Bar.swift",
            "/Sources/foo/Foo.swift")

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { moduleResult in
                moduleResult.check(c99name: "foo", type: .library)
                moduleResult.checkSources(root: "/Sources/foo", paths: "Foo.swift")
            }
        }
    }

    func testMixedSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/main.swift",
            "/Sources/foo/main.c")

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("target at '/Sources/foo' contains mixed language source files; feature not supported")
        }
    }

    func testBrokenSymlink() throws {
        mktmpdir { path in
            let fs = localFileSystem

            let sources = path.appending(components: "Sources", "foo")
            try fs.createDirectory(sources, recursive: true)
            try fs.writeFileContents(sources.appending(components: "foo.swift"), bytes: "")

            // Create a stray symlink in sources.
            let linkDestPath = path.appending(components: "link.swift")
            let linkPath = sources.appending(components: "link.swift")
            try fs.writeFileContents(linkDestPath, bytes: "")
            try createSymlink(linkPath, pointingAt: linkDestPath)
            try fs.removeFileTree(linkDestPath)

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "foo"),
                ]
            )

            PackageBuilderTester(manifest, path: path, in: fs) { result in
                result.checkDiagnostic("ignoring broken symlink \(linkPath)")
                result.checkModule("foo")
            }
        }
    }

    func testCInTests() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/MyPackage/main.swift",
            "/Tests/MyPackageTests/abc.c")

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            targets: [
                TargetDescription(name: "MyPackage"),
                TargetDescription(name: "MyPackageTests", dependencies: ["MyPackage"], type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("MyPackage") { moduleResult in
                moduleResult.check(type: .executable)
                moduleResult.checkSources(root: "/Sources/MyPackage", paths: "main.swift")
            }

            result.checkModule("MyPackageTests") { moduleResult in
                moduleResult.check(type: .test)
                moduleResult.checkSources(root: "/Tests/MyPackageTests", paths: "abc.c")
            }

            result.checkProduct("MyPackage") { _ in }

          #if os(Linux)
            result.checkDiagnostic("ignoring target 'MyPackageTests' in package 'MyPackage'; C language in tests is not yet supported")
          #elseif os(macOS) || os(Android)
            result.checkProduct("MyPackagePackageTests") { _ in }
          #endif
        }
    }

    func testValidSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/pkg/main.swift",
            "/Sources/pkg/noExtension",
            "/Sources/pkg/Package.swift",
            "/.git/anchor",
            "/.xcodeproj/anchor",
            "/.playground/anchor",
            "/Package.swift",
            "/Packages/MyPackage/main.c")

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                TargetDescription(name: "pkg"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("pkg") { moduleResult in
                moduleResult.check(type: .executable)
                moduleResult.checkSources(root: "/Sources/pkg", paths: "main.swift", "Package.swift")
            }
            result.checkProduct("pkg") { _ in }
        }
    }

    func testVersionSpecificManifests() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Package.swift",
            "/Package@swift-999.swift",
            "/Sources/Foo/Package.swift",
            "/Sources/Foo/Package@swift-1.swift")

        let name = "Foo"
        let manifest = Manifest.createV4Manifest(
            name: name,
            targets: [
                TargetDescription(name: name),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Package.swift", "Package@swift-1.swift")
            }
        }
    }

    func testModuleMapLayout() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/clib/include/module.modulemap",
            "/Sources/clib/include/clib.h",
            "/Sources/clib/clib.c"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            targets: [
                TargetDescription(name: "clib"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("clib") { moduleResult in
                moduleResult.check(c99name: "clib", type: .library)
                moduleResult.checkSources(root: "/Sources/clib", paths: "clib.c")
            }
        }
    }

    func testDeclaredExecutableProducts() {
        // Check that declaring executable product doesn't collide with the
        // inferred products.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/foo/foo.swift"
        )

        var manifest = Manifest.createV4Manifest(
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

        manifest = Manifest.createV4Manifest(
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
        manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        var manifest = Manifest.createV4Manifest(
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

        manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

    func testInvalidPublicHeadersPath() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/inc/module.modulemap",
                                    "/Sources/Foo/inc/Foo.h",
                                    "/Sources/Foo/Foo.c",
                                    "/Sources/Bar/include/module.modulemap",
                                    "/Sources/Bar/include/Bar.h",
                                    "/Sources/Bar/Bar.c"
        )

        let manifest = Manifest.createV4Manifest(
            name: "Foo",
            targets: [
                TargetDescription(
                    name: "Foo",
                    publicHeadersPath: "/inc"),
                TargetDescription(
                    name: "Bar"),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("invalid relative path \'/inc\'; relative path should not begin with \'/\' or \'~\'")
        }
    }

    func testTestsLayoutsv4() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Tests/B/Foo.swift",
            "/Tests/ATests/Foo.swift",
            "/Tests/TheTestOfA/Foo.swift")

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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
        var manifest = Manifest.createV4Manifest(
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
        manifest = Manifest.createV4Manifest(
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

    func testTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        let manifest = Manifest.createV4Manifest(
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

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "Random"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target Random should be located under 'Sources/Random', or a custom sources path can be set with the 'path' property in Package.swift")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/src/pkg/Foo.swift")
            // Reference an invalid dependency.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg", dependencies: [.target(name: "Foo")]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target Foo should be located under 'Sources/Foo', or a custom sources path can be set with the 'path' property in Package.swift")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg/Foo.swift")
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg", dependencies: []),
                    TargetDescription(name: "pkgTests", dependencies: [], type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target pkgTests should be located under 'Tests/pkgTests', or a custom sources path can be set with the 'path' property in Package.swift")
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference self in dependencies.
            let manifest = Manifest.createV4Manifest(
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
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "foo"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target foo should be located under 'Sources/foo', or a custom sources path can be set with the 'path' property in Package.swift")
            }
        }

        do {
            let fs = InMemoryFileSystem()
            // Binary target.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "foo", url: "https://bar.com/bar.zip", type: .binary, checksum: "checksum"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _ in }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg1/Foo.swift",
                "/Sources/pkg2/Foo.swift",
                "/Sources/pkg3/Foo.swift"
            )
            // Cyclic dependency.
            var manifest = Manifest.createV4Manifest(
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

            manifest = Manifest.createV4Manifest(
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

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    TargetDescription(name: "pkg2"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target pkg2 should be located under /Sources/pkg2")
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

            var manifest = Manifest.createV4Manifest(
                name: "Foo",
                targets: [
                    TargetDescription(name: "Foo", publicHeadersPath: "../inc"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("public headers directory path for 'Foo' is invalid or not contained in the target")
            }

            manifest = Manifest.createV4Manifest(
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

            let manifest = Manifest.createV4Manifest(
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

            let manifest = Manifest.createV4Manifest(
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

            let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        var manifest = Manifest.createV4Manifest(
            name: "pkg",
            pkgConfig: "foo"
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("configuration of package 'pkg' is invalid; the 'pkgConfig' property can only be used with a System Module Package")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(name: "SystemModulePackage")
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
            return Manifest.createV4Manifest(
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

        manifest = createManifest(
            swiftVersions: [SwiftLanguageVersion(string: "6")!, SwiftLanguageVersion(string: "7")!])
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("package \'pkg\' requires minimum Swift language version 6 which is not supported by the current tools version (\(ToolsVersion.currentToolsVersion))")
        }
    }

    func testPredefinedTargetSearchError() {

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/src/Bar/Bar.swift")

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    TargetDescription(name: "Bar"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target Bar should be located under 'Sources/Bar', or a custom sources path can be set with the 'path' property in Package.swift")
            }
        }

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/Tests/FooTests/Foo.swift",
                "/Source/BarTests/Foo.swift")

            var manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    TargetDescription(name: "BarTests", type: .test),
                    TargetDescription(name: "FooTests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { result in
                result.checkDiagnostic("Source files for target BarTests should be located under 'Tests/BarTests', or a custom sources path can be set with the 'path' property in Package.swift")
            }

            // We should be able to fix this by using custom paths.
            manifest = Manifest.createV4Manifest(
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

    func testSpecifiedCustomPathDoesNotExist() {
        let fs = InMemoryFileSystem(emptyFiles: "/Foo.swift")

        let manifest = Manifest.createV4Manifest(
            name: "Foo",
            targets: [
                TargetDescription(name: "Foo", path: "./NotExist")
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkDiagnostic("invalid custom path './NotExist' for target 'Foo'")
        }
    }

    func testSpecialTargetDir() {
        // Special directory should be src because both target and test target are under it.
        let fs = InMemoryFileSystem(emptyFiles:
            "/src/A/Foo.swift",
            "/src/ATests/Foo.swift")

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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

        let manifest = Manifest.createV4Manifest(
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
            result.checkDiagnostic("ignoring duplicate product 'foo' (static)")
            result.checkDiagnostic("ignoring duplicate product 'foo' (dynamic)")
        }
    }

    func testSystemPackageDeclaresTargetsDiagnostic() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap",
            "/Sources/foo/main.swift",
            "/Sources/bar/main.swift"
        )

        let manifest = Manifest.createV4Manifest(
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
            result.checkDiagnostic("ignoring declared target(s) 'foo, bar' in the system package")
        }
    }

    func testSystemLibraryTarget() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift"
        )

        let manifest = Manifest.createV4Manifest(
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

        var manifest = Manifest.createV4Manifest(
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

        manifest = Manifest.createV4Manifest(
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

    func testBadExecutableProductDecl() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/foo.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            products: [
                ProductDescription(name: "foo", type: .executable, targets: ["foo"]),
            ],
            targets: [
                TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkDiagnostic("executable product \'foo\' should have exactly one executable target")
        }
    }

    func testBadREPLPackage() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exe/main.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "Pkg",
            targets: [
                TargetDescription(name: "exe"),
            ]
        )

        PackageBuilderTester(manifest, createREPLProduct: true, in: fs) { result in
            result.checkModule("exe") { _ in }
            result.checkProduct("exe") { _ in }
            result.checkDiagnostic("unable to synthesize a REPL product as there are no library targets in the package")
        }
    }

    func testPlatforms() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift",
            "/Sources/cbar/bar.c",
            "/Sources/cbar/include/bar.h"
        )

        // One platform with an override.
        var manifest = Manifest.createManifest(
            name: "pkg",
            platforms: [
                PlatformDescription(name: "macos", version: "10.12"),
            ],
            v: .v5,
            targets: [
                TargetDescription(name: "foo", type: .system),
                TargetDescription(name: "cbar"),
                TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )

        var expectedPlatforms = [
            "linux": "0.0",
            "macos": "10.12",
            "ios": "8.0",
            "tvos": "9.0",
            "watchos": "2.0",
            "android": "0.0",
        ]

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            result.checkModule("bar") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            result.checkModule("cbar") { t in
                t.checkPlatforms(expectedPlatforms)
            }
        }

        // Two platforms with overrides.
        manifest = Manifest.createManifest(
            name: "pkg",
            platforms: [
                PlatformDescription(name: "macos", version: "10.12"),
                PlatformDescription(name: "tvos", version: "10.0"),
            ],
            v: .v5,
            targets: [
                TargetDescription(name: "foo", type: .system),
                TargetDescription(name: "cbar"),
                TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )

        expectedPlatforms = [
            "macos": "10.12",
            "tvos": "10.0",
            "linux": "0.0",
            "ios": "8.0",
            "watchos": "2.0",
            "android": "0.0",
        ]

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("foo") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            result.checkModule("bar") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            result.checkModule("cbar") { t in
                t.checkPlatforms(expectedPlatforms)
            }
        }
    }

    func testAsmIsIgnoredInV4_2Manifest() throws {
        // .s is not considered a valid source in 4.2 manifest.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/lib.s",
            "/Sources/lib/lib2.S",
            "/Sources/lib/lib.c",
            "/Sources/lib/include/lib.h"
        )

        let manifest = Manifest.createManifest(
            name: "pkg",
            v: .v4_2,
            targets: [
                TargetDescription(name: "lib", dependencies: []),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("lib") { moduleResult in
                moduleResult.checkSources(root: "/Sources/lib", paths: "lib.c")
            }
        }
    }

    func testAsmInV5Manifest() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/lib.s",
            "/Sources/lib/lib2.S",
            "/Sources/lib/lib.c",
            "/Sources/lib/include/lib.h"
        )

        let diagnostics = DiagnosticsEngine()
        let manifest = Manifest.createManifest(
            name: "Pkg",
            v: .v5,
            targets: [
                TargetDescription(name: "lib", dependencies: []),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("lib") { moduleResult in
                moduleResult.checkSources(root: "/Sources/lib", paths: "lib.c", "lib.s", "lib2.S")
            }
        }
    }

    func testBuildSettings() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exe/main.swift",
            "/Sources/bar/bar.swift",
            "/Sources/cbar/barcpp.cpp",
            "/Sources/cbar/bar.c",
            "/Sources/cbar/include/bar.h"
        )

        let manifest = Manifest.createManifest(
            name: "pkg",
            v: .v5,
            targets: [
                TargetDescription(
                    name: "cbar",
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, value: ["Sources/headers"]),
                        .init(tool: .cxx, name: .headerSearchPath, value: ["Sources/cppheaders"]),

                        .init(tool: .c, name: .define, value: ["CCC=2"]),
                        .init(tool: .cxx, name: .define, value: ["CXX"]),
                        .init(tool: .cxx, name: .define, value: ["RCXX"], condition: .init(config: "release")),

                        .init(tool: .c, name: .unsafeFlags, value: ["-Icfoo", "-L", "cbar"]),
                        .init(tool: .cxx, name: .unsafeFlags, value: ["-Icxxfoo", "-L", "cxxbar"]),
                    ]
                ),
                TargetDescription(
                    name: "bar", dependencies: ["foo"],
                    settings: [
                        .init(tool: .swift, name: .define, value: ["SOMETHING"]),
                        .init(tool: .swift, name: .define, value: ["LINUX"], condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, name: .define, value: ["RLINUX"], condition: .init(platformNames: ["linux"], config: "release")),
                        .init(tool: .swift, name: .define, value: ["DMACOS"], condition: .init(platformNames: ["macos"], config: "debug")),
                        .init(tool: .swift, name: .unsafeFlags, value: ["-Isfoo", "-L", "sbar"]),
                    ]
                ),
                TargetDescription(
                    name: "exe", dependencies: ["bar"],
                    settings: [
                        .init(tool: .linker, name: .linkedLibrary, value: ["sqlite3"]),
                        .init(tool: .linker, name: .linkedFramework, value: ["CoreData"], condition: .init(platformNames: ["ios"])),
                        .init(tool: .linker, name: .unsafeFlags, value: ["-Ilfoo", "-L", "lbar"]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { result in
            result.checkModule("cbar") { result in
                let scope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.macOS, .debug))
                XCTAssertEqual(scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS), ["CCC=2", "CXX"])
                XCTAssertEqual(scope.evaluate(.HEADER_SEARCH_PATHS), ["Sources/headers", "Sources/cppheaders"])
                XCTAssertEqual(scope.evaluate(.OTHER_CFLAGS), ["-Icfoo", "-L", "cbar"])
                XCTAssertEqual(scope.evaluate(.OTHER_CPLUSPLUSFLAGS), ["-Icxxfoo", "-L", "cxxbar"])

                let releaseScope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.macOS, .release))
                XCTAssertEqual(releaseScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS), ["CCC=2", "CXX", "RCXX"])
            }

            result.checkModule("bar") { result in
                let scope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.linux, .debug))
                XCTAssertEqual(scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "LINUX"])
                XCTAssertEqual(scope.evaluate(.OTHER_SWIFT_FLAGS), ["-Isfoo", "-L", "sbar"])

                let rscope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.linux, .release))
                XCTAssertEqual(rscope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "LINUX", "RLINUX"])

                let mscope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.macOS, .debug))
                XCTAssertEqual(mscope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "DMACOS"])
            }

            result.checkModule("exe") { result in
                let scope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.linux, .debug))
                XCTAssertEqual(scope.evaluate(.LINK_LIBRARIES), ["sqlite3"])
                XCTAssertEqual(scope.evaluate(.OTHER_LDFLAGS), ["-Ilfoo", "-L", "lbar"])
                XCTAssertEqual(scope.evaluate(.LINK_FRAMEWORKS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_SWIFT_FLAGS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_CFLAGS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_CPLUSPLUSFLAGS), [])

                let mscope = BuildSettings.Scope(result.target.buildSettings, boundCondition: (.iOS, .debug))
                XCTAssertEqual(mscope.evaluate(.LINK_LIBRARIES), ["sqlite3"])
                XCTAssertEqual(mscope.evaluate(.LINK_FRAMEWORKS), ["CoreData"])

            }

            result.checkProduct("exe")
        }
    }

    func testInvalidHeaderSearchPath() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Sources/exe/main.swift"
        )

        let manifest1 = Manifest.createManifest(
            name: "pkg",
            v: .v5,
            targets: [
                TargetDescription(
                    name: "exe",
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, value: ["/Sources/headers"]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest1, path: AbsolutePath("/pkg"), in: fs) { result in
            result.checkDiagnostic("invalid relative path '/Sources/headers'; relative path should not begin with '/' or '~'")
        }

        let manifest2 = Manifest.createManifest(
            name: "pkg",
            v: .v5,
            targets: [
                TargetDescription(
                    name: "exe",
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, value: ["../../.."]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest2, path: AbsolutePath("/pkg"), in: fs) { result in
            result.checkDiagnostic("invalid header search path '../../..'; header search path should not be outside the package root")
        }
    }

    func testDuplicateTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Foo/Sources/Foo2/foo.swift",
            "/Bar/Sources/Bar/bar.swift"
        )

        let manifest1 = Manifest.createManifest(
            name: "Foo",
            v: .v5,
            dependencies: [
                PackageDependencyDescription(name: nil, url: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            ],
            targets: [
                TargetDescription(
                    name: "Foo",
                    dependencies: [
                        "Bar",
                        "Bar",
                        "Foo2",
                        "Foo2",
                    ]),
                TargetDescription(name: "Foo2"),
            ]
        )

        PackageBuilderTester(manifest1, path: AbsolutePath("/Foo"), in: fs) { result in
            result.checkModule("Foo")
            result.checkModule("Foo2")
            result.checkDiagnostic("invalid duplicate target dependency declaration 'Bar' in target 'Foo'")
            result.checkDiagnostic("invalid duplicate target dependency declaration 'Foo2' in target 'Foo'")
        }
    }
}

extension PackageModel.Product: ObjectIdentifierProtocol {}

final class PackageBuilderTester {
    private enum Result {
        case package(PackageModel.Package)
        case error(String)
    }

    /// Contains the result produced by PackageBuilder.
    private let result: Result

    /// Contains the diagnostics which have not been checked yet.
    private var uncheckedDiagnostics = Set<String>()

    /// Contains the targets which have not been checked yet.
    private var uncheckedModules = Set<PackageModel.Target>()

    /// Contains the products which have not been checked yet.
    private var uncheckedProducts = Set<PackageModel.Product>()

    @discardableResult
    init(
        _ manifest: Manifest,
        path: AbsolutePath = .root,
        shouldCreateMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false,
        in fs: FileSystem,
        file: StaticString = #file,
        line: UInt = #line,
        _ body: (PackageBuilderTester) -> Void
    ) {
        let diagnostics = DiagnosticsEngine()
        do {
            // FIXME: We should allow customizing root package boolean.
            let builder = PackageBuilder(
                manifest: manifest, path: path, fileSystem: fs, diagnostics: diagnostics,
                shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts, createREPLProduct: createREPLProduct)
            let loadedPackage = try builder.construct()
            result = .package(loadedPackage)
            uncheckedModules = Set(loadedPackage.targets)
            uncheckedProducts = Set(loadedPackage.products)
        } catch {
            let errorStr = String(describing: error)
            result = .error(errorStr)
            uncheckedDiagnostics.insert(errorStr)
        }
        uncheckedDiagnostics.formUnion(diagnostics.diagnostics.map({ $0.description }))
        body(self)
        validateDiagnostics(file: file, line: line)
        validateCheckedModules(file: file, line: line)
    }

    private func validateDiagnostics(file: StaticString, line: UInt) {
        guard !uncheckedDiagnostics.isEmpty else { return }
        XCTFail("Unchecked diagnostics: \(uncheckedDiagnostics)", file: file, line: line)
    }

    private func validateCheckedModules(file: StaticString, line: UInt) {
        if !uncheckedModules.isEmpty {
            XCTFail("Unchecked targets: \(uncheckedModules)", file: file, line: line)
        }

        if !uncheckedProducts.isEmpty {
            XCTFail("Unchecked products: \(uncheckedProducts)", file: file, line: line)
        }
    }

    func checkDiagnostic(_ str: String, file: StaticString = #file, line: UInt = #line) {
        if uncheckedDiagnostics.contains(str) {
            uncheckedDiagnostics.remove(str)
        } else {
            XCTFail("\(result) did not have error: \"\(str)\" or is already checked", file: file, line: line)
        }
    }

    func checkPredefinedPaths(target: String, testTarget: String, file: StaticString = #file, line: UInt = #line) {
        guard case .package(let package) = result else {
            return XCTFail("Expected package did not load \(self)", file: file, line: line)
        }
        XCTAssertEqual(target, package.targetSearchPath.pathString, file: file, line: line)
        XCTAssertEqual(testTarget, package.testTargetSearchPath.pathString, file: file, line: line)
    }

    func checkModule(_ name: String, file: StaticString = #file, line: UInt = #line, _ body: ((ModuleResult) -> Void)? = nil) {
        guard case .package(let package) = result else {
            return XCTFail("Expected package did not load \(self)", file: file, line: line)
        }
        guard let target = package.targets.first(where: {$0.name == name}) else {
            return XCTFail("Module: \(name) not found", file: file, line: line)
        }
        uncheckedModules.remove(target)
        body?(ModuleResult(target))
    }

    func checkProduct(_ name: String, file: StaticString = #file, line: UInt = #line, _ body: ((ProductResult) -> Void)? = nil) {
        guard case .package(let package) = result else {
            return XCTFail("Expected package did not load \(self)", file: file, line: line)
        }
        let foundProducts = package.products.filter{$0.name == name}
        guard foundProducts.count == 1 else {
            return XCTFail("Couldn't get the product: \(name). Found products \(foundProducts)", file: file, line: line)
        }
        uncheckedProducts.remove(foundProducts[0])
        body?(ProductResult(foundProducts[0]))
    }

    final class ProductResult {
        private let product: PackageModel.Product

        init(_ product: PackageModel.Product) {
            self.product = product
        }

        func check(type: PackageModel.ProductType, targets: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(product.type, type, file: file, line: line)
            XCTAssertEqual(product.targets.map{$0.name}.sorted(), targets.sorted(), file: file, line: line)
        }

        func check(linuxMainPath: String?, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(product.linuxMain, linuxMainPath.map({ AbsolutePath($0) }), file: file, line: line)
        }
    }

    final class ModuleResult {
        let target: PackageModel.Target

        fileprivate init(_ target: PackageModel.Target) {
            self.target = target
        }

        func check(includeDir: String, file: StaticString = #file, line: UInt = #line) {
            guard case let target as ClangTarget = target else {
                return XCTFail("Include directory is being checked on a non clang target", file: file, line: line)
            }
            XCTAssertEqual(target.includeDir.pathString, includeDir, file: file, line: line)
        }

        func check(c99name: String? = nil, type: PackageModel.Target.Kind? = nil, file: StaticString = #file, line: UInt = #line) {
            if let c99name = c99name {
                XCTAssertEqual(target.c99name, c99name, file: file, line: line)
            }
            if let type = type {
                XCTAssertEqual(target.type, type, file: file, line: line)
            }
        }

        func checkSources(root: String? = nil, sources paths: [String], file: StaticString = #file, line: UInt = #line) {
            if let root = root {
                XCTAssertEqual(target.sources.root, AbsolutePath(root), file: file, line: line)
            }
            let sources = Set(self.target.sources.relativePaths.map({ $0.pathString }))
            XCTAssertEqual(sources, Set(paths), "unexpected source files in \(target.name)", file: file, line: line)
        }

        func checkSources(root: String? = nil, paths: String..., file: StaticString = #file, line: UInt = #line) {
            checkSources(root: root, sources: paths, file: file, line: line)
        }

        func check(dependencies depsToCheck: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(Set(depsToCheck), Set(target.dependencies.map{$0.name}), "unexpected dependencies in \(target.name)", file: file, line: line)
        }

        func check(productDeps depsToCheck: [(name: String, package: String?)], file: StaticString = #file, line: UInt = #line) {
            guard depsToCheck.count == target.productDependencies.count else {
                return XCTFail("Incorrect product dependencies", file: file, line: line)
            }
            for (idx, element) in depsToCheck.enumerated() {
                let rhs = target.productDependencies[idx]
                guard element.name == rhs.name && element.package == rhs.package else {
                    return XCTFail("Incorrect product dependencies", file: file, line: line)
                }
            }
        }

        func check(swiftVersion: String, file: StaticString = #file, line: UInt = #line) {
            guard case let swiftTarget as SwiftTarget = target else {
                return XCTFail("\(target) is not a swift target", file: file, line: line)
            }
            XCTAssertEqual(SwiftLanguageVersion(string: swiftVersion)!, swiftTarget.swiftVersion, file: file, line: line)
        }

        func checkPlatforms(_ platforms: [String: String], file: StaticString = #file, line: UInt = #line) {
            let targetPlatforms = Dictionary(uniqueKeysWithValues: target.platforms.map({ ($0.platform.name, $0.version.versionString) }))
            XCTAssertEqual(platforms, targetPlatforms, file: file, line: line)
        }
    }
}
