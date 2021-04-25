/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
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
                try TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(c99name: "foo", type: .library)
                module.checkSources(root: "/Sources/foo", paths: "Foo.swift")
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
                try TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "target at '/Sources/foo' contains mixed language source files; feature not supported", behavior: .error)
        }
    }

    func testBrokenSymlink() throws {
        try testWithTemporaryDirectory { path in
            let fs = localFileSystem

            let sources = path.appending(components: "Sources", "foo")
            try fs.createDirectory(sources, recursive: true)
            try fs.writeFileContents(sources.appending(components: "foo.swift"), bytes: "")

            // Create a stray symlink in sources.
            let linkDestPath = path.appending(components: "link.swift")
            let linkPath = sources.appending(components: "link.swift")
            try fs.writeFileContents(linkDestPath, bytes: "")
            try fs.createSymbolicLink(linkPath, pointingAt: linkDestPath, relative: false)
            try fs.removeFileTree(linkDestPath)

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "foo"),
                ]
            )

            PackageBuilderTester(manifest, path: path, in: fs) { package, diagnostics in
                diagnostics.check(
                    diagnostic: "ignoring broken symlink \(linkPath)",
                    behavior: .warning,
                    location: "'pkg' \(path)")
                package.checkModule("foo")
            }
        }
    }

    func testSymlinkedSourcesDirectory() throws {
        try testWithTemporaryDirectory { path in
            let fs = localFileSystem

            let sources = path.appending(components: "Sources")
            let foo = sources.appending(components: "foo")
            let bar = sources.appending(components: "bar")
            try fs.createDirectory(foo, recursive: true)
            try fs.writeFileContents(foo.appending(components: "foo.swift"), bytes: "")

            // Create a symlink to foo.
            try fs.createSymbolicLink(bar, pointingAt: foo, relative: false)

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "bar"),
                ]
            )

            PackageBuilderTester(manifest, path: path, in: fs) { package, _ in
                package.checkModule("bar")
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
                try TargetDescription(name: "MyPackage"),
                try TargetDescription(name: "MyPackageTests", dependencies: ["MyPackage"], type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("MyPackage") { module in
                module.check(type: .executable)
                module.checkSources(root: "/Sources/MyPackage", paths: "main.swift")
            }

            package.checkModule("MyPackageTests") { module in
                module.check(type: .test)
                module.checkSources(root: "/Tests/MyPackageTests", paths: "abc.c")
            }

            package.checkProduct("MyPackage") { _ in }

          #if os(Linux)
            diagnostics.check(diagnostic: "ignoring target 'MyPackageTests' in package 'MyPackage'; C language in tests is not yet supported", behavior: .warning)
          #elseif os(macOS) || os(Android)
            package.checkProduct("MyPackagePackageTests") { _ in }
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
                try TargetDescription(name: "pkg"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("pkg") { module in
                module.check(type: .executable)
                module.checkSources(root: "/Sources/pkg", paths: "main.swift", "Package.swift")
            }
            package.checkProduct("pkg") { _ in }
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
                try TargetDescription(name: name),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule(name) { module in
                module.check(c99name: name, type: .library)
                module.checkSources(root: "/Sources/Foo", paths: "Package.swift", "Package@swift-1.swift")
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
                try TargetDescription(name: "clib"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("clib") { module in
                module.check(c99name: "clib", type: .library)
                module.checkSources(root: "/Sources/clib", paths: "clib.c")
                module.check(moduleMapType: .custom(AbsolutePath("/Sources/clib/include/module.modulemap")))
            }
        }
    }

    func testPublicIncludeDirMixedWithSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/clib/nested/nested.h",
            "/Sources/clib/nested/nested.c",
            "/Sources/clib/clib.h",
            "/Sources/clib/clib.c",
            "/Sources/clib/clib2.h",
            "/Sources/clib/clib2.c",
            "/done"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            targets: [
                try TargetDescription(
                    name: "clib",
                    path: "Sources",
                    sources: ["clib", "clib"],
                    publicHeadersPath: "."
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diags in
            diags.check(diagnostic: "found duplicate sources declaration in the package manifest: /Sources/clib", behavior: .warning)
            package.checkModule("clib") { module in
                module.check(c99name: "clib", type: .library)
                module.checkSources(root: "/Sources", paths: "clib/clib.c", "clib/clib2.c", "clib/nested/nested.c")
                module.check(moduleMapType: .umbrellaHeader(AbsolutePath("/Sources/clib/clib.h")))
            }
        }
    }

    func testDeclaredSourcesWithDot() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/swift.lib/foo.swift",
            "/Sources/swiftlib1/swift.lib/foo.swift",
            "/Sources/swiftlib2/swift.lib/foo.swift",
            "/Sources/swiftlib3/swift.lib/foo.swift",
            "/Sources/swiftlib3/swift.lib/foo.bar/bar.swift",
            "/done"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            targets: [
                try TargetDescription(
                    name: "swift.lib"
                ),
                try TargetDescription(
                    name: "swiftlib1",
                    path: "Sources/swiftlib1",
                    sources: ["swift.lib"]
                ),
                try TargetDescription(
                    name: "swiftlib2",
                    path: "Sources/swiftlib2/swift.lib"
                ),
                try TargetDescription(
                    name: "swiftlib3",
                    path: "Sources/swiftlib3/swift.lib"
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result, _ in
            result.checkModule("swift.lib") { module in
                module.checkSources(sources: ["foo.swift"])
            }
            result.checkModule("swiftlib1") { module in
                module.checkSources(sources: ["swift.lib/foo.swift"])
            }
            result.checkModule("swiftlib2") { module in
                module.checkSources(sources: ["foo.swift"])
            }
            result.checkModule("swiftlib3") { module in
                module.checkSources(sources: ["foo.bar/bar.swift", "foo.swift"])
            }
        }
    }

    func testOverlappingDeclaredSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/clib/subfolder/foo.h",
            "/Sources/clib/subfolder/foo.c",
            "/Sources/clib/bar.h",
            "/Sources/clib/bar.c",
            "/done"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            targets: [
                try TargetDescription(
                    name: "clib",
                    path: "Sources",
                    sources: ["clib", "clib/subfolder"]
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { result, _ in
            result.checkModule("clib") { module in
                module.checkSources(sources: ["clib/bar.c", "clib/subfolder/foo.c"])
            }
        }
    }

    func testDeclaredExecutableProducts() throws {
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
                try TargetDescription(name: "foo"),
                try TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { _ in }
            package.checkModule("exec") { _ in }
            package.checkProduct("exec") { product in
                product.check(type: .executable, targets: ["exec", "foo"])
            }
        }

        manifest = Manifest.createV4Manifest(
            name: "pkg",
            products: [],
            targets: [
                try TargetDescription(name: "foo"),
                try TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { _ in }
            package.checkModule("exec") { _ in }
            package.checkProduct("exec") { product in
                product.check(type: .executable, targets: ["exec"])
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
                try TargetDescription(name: "foo"),
                try TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { _ in }
            package.checkModule("exec") { _ in }
            package.checkProduct("exec1") { product in
                product.check(type: .executable, targets: ["exec"])
            }
        }
    }

    func testExecutableTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec1/exec.swift",
            "/Sources/exec2/main.swift",
            "/Sources/lib/lib.swift"
        )
        
        // Check that an explicitly declared target without a main source file works.
        var manifest = Manifest.createV4Manifest(
            name: "pkg",
            toolsVersion: .v5_5,
            products: [
                ProductDescription(name: "exec1", type: .executable, targets: ["exec1", "lib"]),
            ],
            targets: [
                try TargetDescription(name: "exec1", type: .executable),
                try TargetDescription(name: "lib"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { _ in }
            package.checkModule("exec1") { _ in }
            package.checkProduct("exec1") { product in
                product.check(type: .executable, targets: ["exec1", "lib"])
            }
        }

        // Check that products are inferred for explicitly declared executable targets.
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            toolsVersion: .v5_5,
            products: [],
            targets: [
                try TargetDescription(name: "exec1", type: .executable),
                try TargetDescription(name: "lib"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { _ in }
            package.checkModule("exec1") { _ in }
            package.checkProduct("exec1") { product in
                product.check(type: .executable, targets: ["exec1"])
            }
        }

        // Check that products are not inferred if there is an explicit executable product.
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            toolsVersion: .v5_5,
            products: [
                ProductDescription(name: "exec1", type: .executable, targets: ["exec1"]),
            ],
            targets: [
                try TargetDescription(name: "lib"),
                try TargetDescription(name: "exec1", type: .executable),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { _ in }
            package.checkModule("exec1") { _ in }
            package.checkProduct("exec1") { product in
                product.check(type: .executable, targets: ["exec1"])
            }
        }

        // Check that an explicitly declared target with a main source file still works.
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            toolsVersion: .v5_5,
            products: [
                ProductDescription(name: "exec1", type: .executable, targets: ["exec1"]),
            ],
            targets: [
                try TargetDescription(name: "lib"),
                try TargetDescription(name: "exec1", type: .executable),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { _ in }
            package.checkModule("exec1") { _ in }
            package.checkProduct("exec1") { product in
                product.check(type: .executable, targets: ["exec1"])
            }
        }

        // Check that a inferred target with a main source file still works but yields a warning.
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            toolsVersion: .v5_5,
            products: [
                ProductDescription(name: "exec2", type: .executable, targets: ["exec2"]),
            ],
            targets: [
                try TargetDescription(name: "lib"),
                try TargetDescription(name: "exec2"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            diagnostics.check(diagnostic: "'exec2' was identified as an executable target given the presence of a 'main.swift' file. Starting with tools version 5.4.0 executable targets should be declared as 'executableTarget()'", behavior: .warning)
            package.checkModule("lib") { _ in }
            package.checkModule("exec2") { _ in }
            package.checkProduct("exec2") { product in
                product.check(type: .executable, targets: ["exec2"])
            }
        }
    }
    
    func testTestManifestFound() throws {
        try SwiftTarget.testManifestNames.forEach { name in
            let fs = InMemoryFileSystem(emptyFiles:
                "/swift/exe/foo.swift",
                "/\(name)",
                "/swift/tests/footests.swift"
            )

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "exe", path: "swift/exe"),
                    try TargetDescription(name: "tests", path: "swift/tests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { package, _ in
                package.checkModule("exe") { module in
                    module.check(c99name: "exe", type: .library)
                    module.checkSources(root: "/swift/exe", paths: "foo.swift")
                }

                package.checkModule("tests") { module in
                    module.check(c99name: "tests", type: .test)
                    module.checkSources(root: "/swift/tests", paths: "footests.swift")
                }

                package.checkProduct("pkgPackageTests") { product in
                    product.check(type: .test, targets: ["tests"])
                    product.check(testManifestPath: "/\(name)")
                }
            }
        }
    }

    func testTestManifestSearch() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/foo.swift",
            "/pkg/footests.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(
                    name: "exe",
                    path: "./",
                    sources: ["foo.swift"]
                ),
                try TargetDescription(
                    name: "tests",
                    path: "./",
                    sources: ["footests.swift"],
                    type: .test
                ),
            ]
        )
        PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { package, _ in
            package.checkModule("exe") { _ in }
            package.checkModule("tests") { _ in }

            package.checkProduct("pkgPackageTests") { product in
                product.check(type: .test, targets: ["tests"])
                product.check(testManifestPath: nil)
            }
        }
    }

    func testMultipleTestManifestError() throws {
        let name = SwiftTarget.testManifestNames.first!
        let fs = InMemoryFileSystem(emptyFiles:
            "/\(name)",
            "/swift/\(name)",
            "/swift/tests/footests.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(
                    name: "tests",
                    path: "swift/tests",
                    type: .test
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "package 'pkg' has multiple test manifest files: /\(name), /swift/\(name)", behavior: .error)
        }
    }

    func testCustomTargetPaths() throws {
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
                try TargetDescription(
                    name: "exe",
                    path: "mah/target/exe",
                    sources: ["swift"]),
                try TargetDescription(
                    name: "clib",
                    path: "mah/target/exe",
                    sources: ["foo.c"]),
                try TargetDescription(
                    name: "foo"),
                try TargetDescription(
                    name: "bar",
                    path: "bar",
                    exclude: ["bar/excluded.swift", "bar/fixture"],
                    sources: ["bar"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            package.checkModule("exe") { module in
                module.check(c99name: "exe", type: .executable)
                module.checkSources(root: "/mah/target/exe",
                    paths: "swift/exe/main.swift", "swift/exe/foo.swift", "swift/bar.swift")
            }

            package.checkModule("clib") { module in
                module.check(c99name: "clib", type: .library)
                module.checkSources(root: "/mah/target/exe", paths: "foo.c")
            }

            package.checkModule("foo") { module in
                module.check(c99name: "foo", type: .library)
                module.checkSources(root: "/Sources/foo", paths: "foo.swift")
            }

            package.checkModule("bar") { module in
                module.check(c99name: "bar", type: .library)
                module.checkSources(root: "/bar", paths: "bar/foo.swift")
            }

            package.checkProduct("exe") { _ in }
        }
    }

    func testCustomTargetPathsOverlap() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/target/bar/bar.swift",
            "/target/bar/Tests/barTests.swift"
        )

        var manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(
                    name: "bar",
                    path: "target/bar"),
                try TargetDescription(
                    name: "barTests",
                    path: "target/bar/Tests",
                    type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnotics in
            diagnotics.check(diagnostic: "target 'barTests' has sources overlapping sources: /target/bar/Tests/barTests.swift", behavior: .error)
        }

        manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(
                    name: "bar",
                    path: "target/bar",
                    exclude: ["Tests"]),
                try TargetDescription(
                    name: "barTests",
                    path: "target/bar/Tests",
                    type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            package.checkModule("bar") { module in
                module.check(c99name: "bar", type: .library)
                module.checkSources(root: "/target/bar", paths: "bar.swift")
            }

            package.checkModule("barTests") { module in
                module.check(c99name: "barTests", type: .test)
                module.checkSources(root: "/target/bar/Tests", paths: "barTests.swift")
            }

            package.checkProduct("pkgPackageTests")
        }
    }

    func testPublicHeadersPath() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/inc/module.modulemap",
            "/Sources/Foo/inc/Foo.h",
            "/Sources/Foo/Foo_private.h",
            "/Sources/Foo/Foo.c",
            "/Sources/Bar/include/module.modulemap",
            "/Sources/Bar/include/Bar.h",
            "/Sources/Bar/Bar.c"
        )

        let manifest = Manifest.createV4Manifest(
            name: "Foo",
            targets: [
                try TargetDescription(
                    name: "Foo",
                    publicHeadersPath: "inc"),
                try TargetDescription(
                    name: "Bar"),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            package.checkModule("Foo") { module in
                let clangTarget = module.target as? ClangTarget
                XCTAssertEqual(clangTarget?.headers.map{ $0.pathString }, ["/Sources/Foo/Foo_private.h", "/Sources/Foo/inc/Foo.h"])
                module.check(c99name: "Foo", type: .library)
                module.checkSources(root: "/Sources/Foo", paths: "Foo.c")
                module.check(includeDir: "/Sources/Foo/inc")
                module.check(moduleMapType: .custom(AbsolutePath("/Sources/Foo/inc/module.modulemap")))
            }

            package.checkModule("Bar") { module in
                module.check(c99name: "Bar", type: .library)
                module.checkSources(root: "/Sources/Bar", paths: "Bar.c")
                module.check(includeDir: "/Sources/Bar/include")
                module.check(moduleMapType: .custom(AbsolutePath("/Sources/Bar/include/module.modulemap")))
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
                try TargetDescription(
                    name: "Foo",
                    publicHeadersPath: "/inc"),
                try TargetDescription(
                    name: "Bar"),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "invalid relative path \'/inc\'; relative path should not begin with \'/\' or \'~\'", behavior: .error)
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
                try TargetDescription(name: "A"),
                try TargetDescription(name: "TheTestOfA", dependencies: ["A"], type: .test),
                try TargetDescription(name: "ATests", type: .test),
                try TargetDescription(name: "B", type: .test),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            package.checkModule("A") { module in
                module.check(c99name: "A", type: .executable)
                module.checkSources(root: "/Sources/A", paths: "main.swift")
            }

            package.checkModule("TheTestOfA") { module in
                module.check(c99name: "TheTestOfA", type: .test)
                module.checkSources(root: "/Tests/TheTestOfA", paths: "Foo.swift")
                module.check(targetDependencies: ["A"])
            }

            package.checkModule("B") { module in
                module.check(c99name: "B", type: .test)
                module.checkSources(root: "/Tests/B", paths: "Foo.swift")
                module.check(targetDependencies: [])
            }

            package.checkModule("ATests") { module in
                module.check(c99name: "ATests", type: .test)
                module.checkSources(root: "/Tests/ATests", paths: "Foo.swift")
                module.check(targetDependencies: [])
            }

            package.checkProduct("FooPackageTests") { _ in }
            package.checkProduct("A") { _ in }
        }
    }

    func testMultipleTestProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/foo.swift",
            "/Tests/fooTests/foo.swift",
            "/Tests/barTests/bar.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(name: "foo"),
                try TargetDescription(name: "fooTests", type: .test),
                try TargetDescription(name: "barTests", type: .test),
            ]
        )

        PackageBuilderTester(manifest, shouldCreateMultipleTestProducts: true, in: fs) { package, _ in
            package.checkModule("foo") { _ in }
            package.checkModule("fooTests") { _ in }
            package.checkModule("barTests") { _ in }
            package.checkProduct("fooTests") { product in
                product.check(type: .test, targets: ["fooTests"])
            }
            package.checkProduct("barTests") { product in
                product.check(type: .test, targets: ["barTests"])
            }
        }

        PackageBuilderTester(manifest, shouldCreateMultipleTestProducts: false, in: fs) { package, _ in
            package.checkModule("foo") { _ in }
            package.checkModule("fooTests") { _ in }
            package.checkModule("barTests") { _ in }
            package.checkProduct("pkgPackageTests") { product in
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
                try TargetDescription(name: "Foo", dependencies: ["Bar"]),
                try TargetDescription(name: "Bar"),
                try TargetDescription(name: "Baz"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("Foo") { module in
                module.check(c99name: "Foo", type: .library)
                module.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                module.check(targetDependencies: ["Bar"])
            }

            for target in ["Bar", "Baz"] {
                package.checkModule(target) { module in
                    module.check(c99name: target, type: .library)
                    module.checkSources(root: "/Sources/\(target)", paths: "\(target).swift")
                }
            }
        }

        // Transitive.
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(name: "Foo", dependencies: ["Bar"]),
                try TargetDescription(name: "Bar", dependencies: ["Baz"]),
                try TargetDescription(name: "Baz"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("Foo") { module in
                module.check(c99name: "Foo", type: .library)
                module.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                module.check(targetDependencies: ["Bar"])
            }

            package.checkModule("Bar") { module in
                module.check(c99name: "Bar", type: .library)
                module.checkSources(root: "/Sources/Bar", paths: "Bar.swift")
                module.check(targetDependencies: ["Baz"])
            }

            package.checkModule("Baz") { module in
                module.check(c99name: "Baz", type: .library)
                module.checkSources(root: "/Sources/Baz", paths: "Baz.swift")
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
                try TargetDescription(name: "Bar"),
                try TargetDescription(name: "Baz"),
                try TargetDescription(
                    name: "Foo",
                    dependencies: ["Bar", "Baz", "Bam"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in

            package.checkPredefinedPaths(target: "/Sources", testTarget: "/Tests")

            package.checkModule("Foo") { module in
                module.check(c99name: "Foo", type: .library)
                module.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                module.check(targetDependencies: ["Bar", "Baz"])
                module.check(productDependencies: [.init(name: "Bam", package: nil)])
            }

            for target in ["Bar", "Baz"] {
                package.checkModule(target) { module in
                    module.check(c99name: target, type: .library)
                    module.checkSources(root: "/Sources/\(target)", paths: "\(target).swift")
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
                    try TargetDescription(name: "Random"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: .contains("Source files for target Random should be located under 'Sources/Random'"), behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/src/pkg/Foo.swift")
            // Reference an invalid dependency.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "pkg", dependencies: [.target(name: "Foo")]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: .contains("Source files for target Foo should be located under 'Sources/Foo'"), behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Sources/pkg/Foo.swift")
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "pkg", dependencies: []),
                    try TargetDescription(name: "pkgTests", dependencies: [], type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: .contains("Source files for target pkgTests should be located under 'Tests/pkgTests'"), behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference self in dependencies.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "pkg", dependencies: [.target(name: "pkg")]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "cyclic dependency declaration found: pkg -> pkg", behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/pkg/Foo.swift")
            // Reference invalid target.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "foo"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnotics in
                diagnotics.check(diagnostic: .contains("Source files for target foo should be located under 'Sources/foo'"), behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem()
            // Binary target.
            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "foo", url: "https://foo.com/foo.zip", type: .binary, checksum: "checksum"),
                ]
            )

            let binaryArtifacts = [BinaryArtifact(kind: .xcframework, originURL: "https://foo.com/foo.zip", path: AbsolutePath("/foo.xcframework"))]
            PackageBuilderTester(manifest, binaryArtifacts: binaryArtifacts, in: fs) { package, _ in
                package.checkModule("foo")
            }
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
                    try TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    try TargetDescription(name: "pkg2", dependencies: ["pkg3"]),
                    try TargetDescription(name: "pkg3", dependencies: ["pkg1"]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg1", behavior: .error)
            }

            manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    try TargetDescription(name: "pkg2", dependencies: ["pkg3"]),
                    try TargetDescription(name: "pkg3", dependencies: ["pkg2"]),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "cyclic dependency declaration found: pkg1 -> pkg2 -> pkg3 -> pkg2", behavior: .error)
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
                    try TargetDescription(name: "pkg1", dependencies: ["pkg2"]),
                    try TargetDescription(name: "pkg2"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { package, diagnostics in
                diagnostics.check(diagnostic: "Source files for target pkg2 should be located under /Sources/pkg2", behavior: .warning)
                package.checkModule("pkg1") { module in
                    module.check(c99name: "pkg1", type: .library)
                    module.checkSources(root: "/Sources/pkg1", paths: "Foo.swift")
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
                    try TargetDescription(name: "Foo", publicHeadersPath: "../inc"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "public headers directory path for 'Foo' is invalid or not contained in the target", behavior: .error)
            }

            manifest = Manifest.createV4Manifest(
                name: "Foo",
                targets: [
                    try TargetDescription(name: "Bar", publicHeadersPath: "inc/../../../foo"),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "public headers directory path for 'Bar' is invalid or not contained in the target", behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest.createV4Manifest(
                name: "Foo",
                targets: [
                    try TargetDescription(name: "Foo", path: "../foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "target 'Foo' in package 'Foo' is outside the package root", behavior: .error)
            }
        }
        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest.createV4Manifest(
                name: "Foo",
                targets: [
                    try TargetDescription(name: "Foo", path: "/foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "target path \'/foo\' is not supported; it should be relative to package root", behavior: .error)
            }
        }

        do {
            let fs = InMemoryFileSystem(emptyFiles:
                "/pkg/Sources/Foo/Foo.c",
                "/foo/Bar.c")

            let manifest = Manifest.createV4Manifest(
                name: "Foo",
                targets: [
                    try TargetDescription(name: "Foo", path: "~/foo"),
                ]
            )
            PackageBuilderTester(manifest, path: AbsolutePath("/pkg"), in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: "target path \'~/foo\' is not supported; it should be relative to package root", behavior: .error)
            }
        }
    }

    func testExecutableAsADep() throws {
        // Executable as dependency.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/lib/lib.swift")

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(name: "lib", dependencies: ["exec"]),
                try TargetDescription(name: "exec"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("exec") { module in
                module.check(c99name: "exec", type: .executable)
                module.checkSources(root: "/Sources/exec", paths: "main.swift")
            }

            package.checkModule("lib") { module in
                module.check(c99name: "lib", type: .library)
                module.checkSources(root: "/Sources/lib", paths: "lib.swift")
            }

            package.checkProduct("exec")
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

        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(
                diagnostic: "configuration of package 'pkg' is invalid; the 'pkgConfig' property can only be used with a System Module Package",
                behavior: .error)
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        manifest = Manifest.createV4Manifest(
            name: "pkg",
            providers: [.brew(["foo"])]
        )

        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(
                diagnostic: "configuration of package 'pkg' is invalid; the 'providers' property can only be used with a System Module Package",
                behavior: .error)
        }
    }

    func testResolvesSystemModulePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap")

        let manifest = Manifest.createV4Manifest(name: "SystemModulePackage")
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("SystemModulePackage") { module in
                module.check(c99name: "SystemModulePackage", type: .systemModule)
                module.checkSources(root: "/")
            }
        }
    }

    func testCompatibleSwiftVersions() throws {
        // Single swift executable target.
        let fs = InMemoryFileSystem(emptyFiles:
            "/foo/main.swift"
        )

        func createManifest(swiftVersions: [SwiftLanguageVersion]?) throws -> Manifest {
            return Manifest.createV4Manifest(
                name: "pkg",
                swiftLanguageVersions: swiftVersions,
                targets: [
                    try TargetDescription(name: "foo", path: "foo"),
                ]
            )
        }

        var manifest = try createManifest(swiftVersions: [.v3, .v4])

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(swiftVersion: "4")
            }
            package.checkProduct("foo") { _ in }
        }

        manifest = try createManifest(swiftVersions: [.v3])
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(swiftVersion: "3")
            }
            package.checkProduct("foo") { _ in }
        }

        manifest = try createManifest(swiftVersions: [.v4])
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(swiftVersion: "4")
            }
            package.checkProduct("foo") { _ in }
        }

        manifest = try createManifest(swiftVersions: nil)
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(swiftVersion: "4")
            }
            package.checkProduct("foo") { _ in }
        }

        manifest = try createManifest(swiftVersions: [])
        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "package 'pkg' supported Swift language versions is empty", behavior: .error)
        }

        manifest = try createManifest(
            swiftVersions: [SwiftLanguageVersion(string: "6")!, SwiftLanguageVersion(string: "7")!])
        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "package 'pkg' requires minimum Swift language version 6 which is not supported by the current tools version (\(ToolsVersion.currentToolsVersion))", behavior: .error)
        }
    }

    func testPredefinedTargetSearchError() throws {

        do {
            // We should look only in one of the predefined search paths.
            let fs = InMemoryFileSystem(emptyFiles:
                "/Source/Foo/Foo.swift",
                "/src/Bar/Bar.swift")

            let manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "Foo", dependencies: ["Bar"]),
                    try TargetDescription(name: "Bar"),
                ]
            )

            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: .contains("Source files for target Bar should be located under 'Sources/Bar'"), behavior: .error)
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
                    try TargetDescription(name: "BarTests", type: .test),
                    try TargetDescription(name: "FooTests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { _, diagnostics in
                diagnostics.check(diagnostic: .contains("Source files for target BarTests should be located under 'Tests/BarTests'"), behavior: .error)
            }

            // We should be able to fix this by using custom paths.
            manifest = Manifest.createV4Manifest(
                name: "pkg",
                targets: [
                    try TargetDescription(name: "BarTests", path: "Source/BarTests", type: .test),
                    try TargetDescription(name: "FooTests", type: .test),
                ]
            )
            PackageBuilderTester(manifest, in: fs) { package, _ in
                package.checkModule("BarTests") { module in
                    module.check(c99name: "BarTests", type: .test)
                }
                package.checkModule("FooTests") { module in
                    module.check(c99name: "FooTests", type: .test)
                }
                package.checkProduct("pkgPackageTests") { _ in }
            }
        }
    }

    func testSpecifiedCustomPathDoesNotExist() throws {
        let fs = InMemoryFileSystem(emptyFiles: "/Foo.swift")

        let manifest = Manifest.createV4Manifest(
            name: "Foo",
            targets: [
                try TargetDescription(name: "Foo", path: "./NotExist")
            ]
        )

        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "invalid custom path './NotExist' for target 'Foo'", behavior: .error)
        }
    }

    func testSpecialTargetDir() throws {
        // Special directory should be src because both target and test target are under it.
        let fs = InMemoryFileSystem(emptyFiles:
            "/src/A/Foo.swift",
            "/src/ATests/Foo.swift")

        let manifest = Manifest.createV4Manifest(
            name: "Foo",
            targets: [
                try TargetDescription(name: "A"),
                try TargetDescription(name: "ATests", type: .test),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkPredefinedPaths(target: "/src", testTarget: "/src")

            package.checkModule("A") { module in
                module.check(c99name: "A", type: .library)
            }
            package.checkModule("ATests") { module in
                module.check(c99name: "ATests", type: .test)
            }

            package.checkProduct("FooPackageTests") { _ in }
        }
    }

    func testExcludes() throws {
        // The exclude should win if a file is in exclude as well as sources.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/bar/barExcluded.swift",
            "/Sources/bar/bar.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "pkg",
            targets: [
                try TargetDescription(
                    name: "bar",
                    exclude: ["barExcluded.swift",],
                    sources: ["bar.swift", "barExcluded.swift"]
                ),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("bar") { module in
                module.check(c99name: "bar", type: .library)
                module.checkSources(root: "/Sources/bar", paths: "bar.swift")
            }
        }
    }

    func testDuplicateProducts() throws {
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
                try TargetDescription(name: "foo"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("foo") { _ in }
            package.checkProduct("foo") { product in
                product.check(type: .library(.automatic), targets: ["foo"])
            }
            package.checkProduct("foo-dy") { product in
                product.check(type: .library(.dynamic), targets: ["foo"])
            }
            diagnostics.check(
                diagnostic: "ignoring duplicate product 'foo' (static)",
                behavior: .warning,
                location: "'pkg' /")
            diagnostics.check(
                diagnostic: "ignoring duplicate product 'foo' (dynamic)",
                behavior: .warning,
                location: "'pkg' /")
        }
    }

    func testSystemPackageDeclaresTargetsDiagnostic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap",
            "/Sources/foo/main.swift",
            "/Sources/bar/main.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "SystemModulePackage",
            targets: [
                try TargetDescription(name: "foo"),
                try TargetDescription(name: "bar"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("SystemModulePackage") { module in
                module.check(c99name: "SystemModulePackage", type: .systemModule)
                module.checkSources(root: "/")
            }
            diagnostics.check(
                diagnostic: "ignoring declared target(s) 'foo, bar' in the system package",
                behavior: .warning,
                location: "'SystemModulePackage' /")
        }
    }

    func testSystemLibraryTarget() throws {
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
                try TargetDescription(name: "foo", type: .system),
                try TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { module in
                module.check(c99name: "foo", type: .systemModule)
                module.checkSources(root: "/Sources/foo")
            }
            package.checkModule("bar") { module in
                module.check(c99name: "bar", type: .library)
                module.checkSources(root: "/Sources/bar", paths: "bar.swift")
                module.check(targetDependencies: ["foo"])
            }
            package.checkProduct("foo") { product in
                product.check(type: .library(.automatic), targets: ["foo"])
            }
        }
    }

    func testSystemLibraryTargetDiagnostics() throws {
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
                try TargetDescription(name: "foo", type: .system),
                try TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("foo") { _ in }
            package.checkModule("bar") { _ in }
            diagnostics.check(
                diagnostic: "system library product foo shouldn't have a type and contain only one target",
                behavior: .error,
                location: "'SystemModulePackage' /")
        }

        manifest = Manifest.createV4Manifest(
            name: "SystemModulePackage",
            products: [
                ProductDescription(name: "foo", type: .library(.static), targets: ["foo"]),
            ],
            targets: [
                try TargetDescription(name: "foo", type: .system),
                try TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("foo") { _ in }
            package.checkModule("bar") { _ in }
            diagnostics.check(
                diagnostic: "system library product foo shouldn't have a type and contain only one target",
                behavior: .error,
                location: "'SystemModulePackage' /")
        }
        
        manifest = Manifest.createV4Manifest(
            name: "bar",
            products: [
                ProductDescription(name: "bar", type: .library(.automatic), targets: ["bar"])
            ],
            targets: [
                try TargetDescription(name: "bar", type: .system)
            ]
        )
        PackageBuilderTester(manifest, in: fs) { _, diagnostics in
            diagnostics.check(
                diagnostic: "package has unsupported layout; missing system target module map at '/Sources/bar/module.modulemap'",
                behavior: .error
            )
        }
    }

    func testBadExecutableProductDecl() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo1/main.swift",
            "/Sources/foo2/main.swift",
            "/Sources/FooLib1/lib.swift",
            "/Sources/FooLib2/lib.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "MyPackage",
            products: [
                ProductDescription(name: "foo1", type: .executable, targets: ["FooLib1"]),
                ProductDescription(name: "foo2", type: .executable, targets: ["FooLib1", "FooLib2"]),
                ProductDescription(name: "foo3", type: .executable, targets: ["foo1", "foo2"]),
            ],
            targets: [
                try TargetDescription(name: "foo1"),
                try TargetDescription(name: "foo2"),
                try TargetDescription(name: "FooLib1"),
                try TargetDescription(name: "FooLib2"),
            ]
        )
        PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            package.checkModule("foo1") { _ in }
            package.checkModule("foo2") { _ in }
            package.checkModule("FooLib1") { _ in }
            package.checkModule("FooLib2") { _ in }
            diagnostics.check(
                diagnostic: """
                    executable product 'foo1' expects target 'FooLib1' to be executable; an executable target requires \
                    a 'main.swift' file
                    """,
                behavior: .error,
                location: "'MyPackage' /")
            diagnostics.check(
                diagnostic: """
                    executable product 'foo2' should have one executable target; an executable target requires a \
                    'main.swift' file
                    """,
                behavior: .error,
                location: "'MyPackage' /")
            diagnostics.check(
                diagnostic: "executable product 'foo3' should not have more than one executable target",
                behavior: .error,
                location: "'MyPackage' /")
        }
    }

    func testBadREPLPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exe/main.swift"
        )

        let manifest = Manifest.createV4Manifest(
            name: "Pkg",
            targets: [
                try TargetDescription(name: "exe"),
            ]
        )

        PackageBuilderTester(manifest, createREPLProduct: true, in: fs) { package, diagnostics in
            package.checkModule("exe") { _ in }
            package.checkProduct("exe") { _ in }
            diagnostics.check(
                diagnostic: "unable to synthesize a REPL product as there are no library targets in the package",
                behavior: .error,
                location: "'Pkg' /")
        }
    }

    func testPlatforms() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/module.modulemap",
            "/Sources/bar/bar.swift",
            "/Sources/cbar/bar.c",
            "/Sources/cbar/include/bar.h",
            "/Tests/test/test.swift"
        )

        // One platform with an override.
        var manifest = Manifest.createManifest(
            name: "pkg",
            platforms: [
                PlatformDescription(name: "macos", version: "10.12", options: ["option1"]),
            ],
            v: .v5,
            targets: [
                try TargetDescription(name: "foo", type: .system),
                try TargetDescription(name: "cbar"),
                try TargetDescription(name: "bar", dependencies: ["foo"]),
                try TargetDescription(name: "test", type: .test)
            ]
        )

        var expectedPlatforms = [
            "linux": "0.0",
            "macos": "10.12",
            "maccatalyst": "13.0",
            "ios": "9.0",
            "tvos": "9.0",
            "driverkit": "19.0",
            "watchos": "2.0",
            "android": "0.0",
            "windows": "0.0",
            "wasi": "0.0",
        ]

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { t in
                t.checkPlatforms(expectedPlatforms)
                t.checkPlatformOptions(.macOS, options: ["option1"])
                t.checkPlatformOptions(.iOS, options: [])

            }
            package.checkModule("bar") { t in
                t.checkPlatforms(expectedPlatforms)
                t.checkPlatformOptions(.macOS, options: ["option1"])
                t.checkPlatformOptions(.iOS, options: [])

            }
            package.checkModule("cbar") { t in
                t.checkPlatforms(expectedPlatforms)
                t.checkPlatformOptions(.macOS, options: ["option1"])
                t.checkPlatformOptions(.iOS, options: [])
            }
            package.checkModule("test") { t in
                var expected = expectedPlatforms
                [PackageModel.Platform.macOS, .iOS, .tvOS, .watchOS].forEach {
                    expected[$0.name] = PackageBuilderTester.xcTestMinimumDeploymentTargets[$0]?.versionString
                }
                t.checkPlatforms(expected)
                t.checkPlatformOptions(.macOS, options: ["option1"])
                t.checkPlatformOptions(.iOS, options: [])
            }
            package.checkProduct("pkgPackageTests") { _ in }
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
                try TargetDescription(name: "foo", type: .system),
                try TargetDescription(name: "cbar"),
                try TargetDescription(name: "bar", dependencies: ["foo"]),
            ]
        )

        expectedPlatforms = [
            "macos": "10.12",
            "maccatalyst": "13.0",
            "tvos": "10.0",
            "linux": "0.0",
            "ios": "9.0",
            "watchos": "2.0",
            "driverkit": "19.0",
            "android": "0.0",
            "windows": "0.0",
            "wasi": "0.0",
        ]

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("foo") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            package.checkModule("bar") { t in
                t.checkPlatforms(expectedPlatforms)
            }
            package.checkModule("cbar") { t in
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
                try TargetDescription(name: "lib", dependencies: []),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { module in
                module.checkSources(root: "/Sources/lib", paths: "lib.c")
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
                try TargetDescription(name: "lib", dependencies: []),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { module in
                module.checkSources(root: "/Sources/lib", paths: "lib.c", "lib.s", "lib2.S")
            }
        }
    }

    func testUnknownSourceFilesUnderDeclaredSourcesIgnoredInV5_2Manifest() throws {
        // Files with unknown suffixes under declared sources are not considered valid sources in 5.2 manifest.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/movie.mkv",
            "/Sources/lib/lib.c",
            "/Sources/lib/include/lib.h"
        )

        let manifest = Manifest.createManifest(
            name: "pkg",
            v: .v5_2,
            targets: [
                try TargetDescription(name: "lib", dependencies: [], path: "./Sources/lib", sources: ["."]),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { module in
                module.checkSources(root: "/Sources/lib", paths: "lib.c")
                module.check(includeDir: "/Sources/lib/include")
                module.check(moduleMapType: .umbrellaHeader(AbsolutePath("/Sources/lib/include/lib.h")))
            }
        }
    }

    func testUnknownSourceFilesUnderDeclaredSourcesCompiledInV5_3Manifest() throws {
        // Files with unknown suffixes under declared sources are treated as compilable in 5.3 manifest.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/movie.mkv",
            "/Sources/lib/lib.c",
            "/Sources/lib/include/lib.h"
        )

        let manifest = Manifest.createManifest(
            name: "pkg",
            v: .v5_3,
            targets: [
                try TargetDescription(name: "lib", dependencies: [], path: "./Sources/lib", sources: ["."]),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("lib") { module in
                module.checkSources(root: "/Sources/lib", paths: "movie.mkv", "lib.c")
                module.check(includeDir: "/Sources/lib/include")
                module.check(moduleMapType: .umbrellaHeader(AbsolutePath("/Sources/lib/include/lib.h")))
            }
        }
    }

    func testBuildSettings() throws {
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
                try TargetDescription(
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
                try TargetDescription(
                    name: "bar", dependencies: ["foo"],
                    settings: [
                        .init(tool: .swift, name: .define, value: ["SOMETHING"]),
                        .init(tool: .swift, name: .define, value: ["LINUX"], condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, name: .define, value: ["RLINUX"], condition: .init(platformNames: ["linux"], config: "release")),
                        .init(tool: .swift, name: .define, value: ["DMACOS"], condition: .init(platformNames: ["macos"], config: "debug")),
                        .init(tool: .swift, name: .unsafeFlags, value: ["-Isfoo", "-L", "sbar"]),
                    ]
                ),
                try TargetDescription(
                    name: "exe", dependencies: ["bar"],
                    settings: [
                        .init(tool: .linker, name: .linkedLibrary, value: ["sqlite3"]),
                        .init(tool: .linker, name: .linkedFramework, value: ["CoreData"], condition: .init(platformNames: ["ios"])),
                        .init(tool: .linker, name: .unsafeFlags, value: ["-Ilfoo", "-L", "lbar"]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkModule("cbar") { package in
                let scope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                XCTAssertEqual(scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS), ["CCC=2", "CXX"])
                XCTAssertEqual(scope.evaluate(.HEADER_SEARCH_PATHS), ["Sources/headers", "Sources/cppheaders"])
                XCTAssertEqual(scope.evaluate(.OTHER_CFLAGS), ["-Icfoo", "-L", "cbar"])
                XCTAssertEqual(scope.evaluate(.OTHER_CPLUSPLUSFLAGS), ["-Icxxfoo", "-L", "cxxbar"])

                let releaseScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .release)
                )
                XCTAssertEqual(releaseScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS), ["CCC=2", "CXX", "RCXX"])
            }

            package.checkModule("bar") { package in
                let scope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .linux, configuration: .debug)
                )
                XCTAssertEqual(scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "LINUX"])
                XCTAssertEqual(scope.evaluate(.OTHER_SWIFT_FLAGS), ["-Isfoo", "-L", "sbar"])

                let rscope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .linux, configuration: .release)
                )
                XCTAssertEqual(rscope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "LINUX", "RLINUX"])

                let mscope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                XCTAssertEqual(mscope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS), ["SOMETHING", "DMACOS"])
            }

            package.checkModule("exe") { package in
                let scope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .linux, configuration: .debug)
                )
                XCTAssertEqual(scope.evaluate(.LINK_LIBRARIES), ["sqlite3"])
                XCTAssertEqual(scope.evaluate(.OTHER_LDFLAGS), ["-Ilfoo", "-L", "lbar"])
                XCTAssertEqual(scope.evaluate(.LINK_FRAMEWORKS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_SWIFT_FLAGS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_CFLAGS), [])
                XCTAssertEqual(scope.evaluate(.OTHER_CPLUSPLUSFLAGS), [])

                let mscope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .iOS, configuration: .debug)
                )
                XCTAssertEqual(mscope.evaluate(.LINK_LIBRARIES), ["sqlite3"])
                XCTAssertEqual(mscope.evaluate(.LINK_FRAMEWORKS), ["CoreData"])

            }

            package.checkProduct("exe")
        }
    }

    func testInvalidHeaderSearchPath() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Sources/exe/main.swift"
        )

        let manifest1 = Manifest.createManifest(
            name: "pkg",
            v: .v5,
            targets: [
                try TargetDescription(
                    name: "exe",
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, value: ["/Sources/headers"]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest1, path: AbsolutePath("/pkg"), in: fs) { package, diagnostics in
            diagnostics.check(diagnostic: "invalid relative path '/Sources/headers'; relative path should not begin with '/' or '~'", behavior: .error)
        }

        let manifest2 = Manifest.createManifest(
            name: "pkg",
            v: .v5,
            targets: [
                try TargetDescription(
                    name: "exe",
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, value: ["../../.."]),
                    ]
                ),
            ]
        )

        PackageBuilderTester(manifest2, path: AbsolutePath("/pkg"), in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "invalid header search path '../../..'; header search path should not be outside the package root", behavior: .error)
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
                .scm(location: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            ],
            targets: [
                try TargetDescription(
                    name: "Foo",
                    dependencies: [
                        "Bar",
                        "Bar",
                        "Foo2",
                        "Foo2",
                    ]),
                try TargetDescription(name: "Foo2"),
            ]
        )

        PackageBuilderTester(manifest1, path: AbsolutePath("/Foo"), in: fs) { package, diagnostics in
            package.checkModule("Foo")
            package.checkModule("Foo2")
            diagnostics.checkUnordered(diagnostic: "invalid duplicate target dependency declaration 'Bar' in target 'Foo' from package 'Foo'", behavior: .warning)
            diagnostics.checkUnordered(diagnostic: "invalid duplicate target dependency declaration 'Foo2' in target 'Foo' from package 'Foo'", behavior: .warning)
        }
    }

    func testConditionalDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.swift",
            "/Sources/Bar/bar.swift",
            "/Sources/Baz/baz.swift"
        )

        let manifest = Manifest.createManifest(
            name: "Foo",
            v: .v5,
            dependencies: [
                .local(path: "/Biz"),
            ],
            targets: [
                try TargetDescription(
                    name: "Foo",
                    dependencies: [
                        .target(name: "Bar", condition: PackageConditionDescription(
                            platformNames: ["macos"],
                            config: nil
                        )),
                        .byName(name: "Baz", condition: PackageConditionDescription(
                            platformNames: [],
                            config: "debug"
                        )),
                        .product(name: "Biz", package: "Biz", condition: PackageConditionDescription(
                            platformNames: ["watchos", "ios"],
                            config: "release"
                        )),
                    ]
                ),
                try TargetDescription(name: "Bar"),
                try TargetDescription(name: "Baz"),
            ]
        )

        PackageBuilderTester(manifest, in: fs) { package, _ in
            package.checkProduct("Foo")
            package.checkModule("Bar")
            package.checkModule("Baz")
            package.checkModule("Foo") { target in
                target.check(dependencies: ["Bar", "Baz", "Biz"])

                target.checkDependency("Bar") { result in
                    result.checkConditions(satisfy: .init(platform: .macOS, configuration: .debug))
                    result.checkConditions(satisfy: .init(platform: .macOS, configuration: .release))
                    result.checkConditions(dontSatisfy: .init(platform: .watchOS, configuration: .release))
                }

                target.checkDependency("Baz") { result in
                    result.checkConditions(satisfy: .init(platform: .macOS, configuration: .debug))
                    result.checkConditions(satisfy: .init(platform: .linux, configuration: .debug))
                    result.checkConditions(dontSatisfy: .init(platform: .linux, configuration: .release))
                }

                target.checkDependency("Biz") { result in
                    result.checkConditions(satisfy: .init(platform: .watchOS, configuration: .release))
                    result.checkConditions(satisfy: .init(platform: .iOS, configuration: .release))
                    result.checkConditions(dontSatisfy: .init(platform: .linux, configuration: .release))
                    result.checkConditions(dontSatisfy: .init(platform: .iOS, configuration: .debug))
                }
            }
        }
    }

    func testMissingDefaultLocalization() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Foo/Sources/Foo/Resources/en.lproj/Localizable.strings"
        )

        let manifest = Manifest.createManifest(
            name: "Foo",
            v: .v5_3,
            targets: [
                try TargetDescription(name: "Foo", resources: [
                    .init(rule: .process, path: "Resources")
                ]),
            ]
        )

        PackageBuilderTester(manifest, path: AbsolutePath("/Foo"), in: fs) { _, diagnostics in
            diagnostics.check(diagnostic: "manifest property 'defaultLocalization' not set; it is required in the presence of localized resources", behavior: .error)
        }
    }

    func testXcodeResources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Foo/Sources/Foo/Foo.xcassets",
            "/Foo/Sources/Foo/Foo.xib",
            "/Foo/Sources/Foo/Foo.xcdatamodel",
            "/Foo/Sources/Foo/Foo.metal"
        )

        let manifest = Manifest.createManifest(
            name: "Foo",
            v: .v5_3,
            targets: [
                try TargetDescription(name: "Foo"),
            ]
        )

        PackageBuilderTester(manifest, path: AbsolutePath("/Foo"), in: fs) { result, diagnostics in
            result.checkModule("Foo") { result in
                result.checkSources(sources: ["foo.swift"])
                result.checkResources(resources: [
                    "/Foo/Sources/Foo/Foo.xib",
                    "/Foo/Sources/Foo/Foo.xcdatamodel",
                    "/Foo/Sources/Foo/Foo.xcassets",
                    "/Foo/Sources/Foo/Foo.metal"
                ])
            }
        }
    }

    func testExtensionTargetsAreGuardededByFeatureFlag() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/MyPlugin/plugin.swift",
            "/Foo/Sources/MyLibrary/library.swift"
        )

        let manifest = Manifest.createManifest(
            name: "Foo",
            v: .v5_5,
            targets: [
                try TargetDescription(
                    name: "MyPlugin",
                    dependencies: [
                        .target(name: "MyLibrary"),
                    ],
                    type: .plugin,
                    pluginCapability: .buildTool
                ),
                try TargetDescription(
                    name: "MyLibrary",
                    type: .regular
                ),
            ]
        )

        // Check that plugin targets are set up correctly when the feature flag is set.
        PackageBuilderTester(manifest, path: AbsolutePath("/Foo"), allowPluginTargets: true, in: fs) { package, diagnostics in
            package.checkModule("MyPlugin") { target in
                target.check(pluginCapability: .buildTool)
                target.check(dependencies: ["MyLibrary"])
            }
            package.checkModule("MyLibrary")
        }
        
        // Check that the right diagnostics are emitted when the feature flag isn't set.
        PackageBuilderTester(manifest, path: AbsolutePath("/Foo"), allowPluginTargets: false, in: fs) { package, diagnostics in
            diagnostics.check(diagnostic: "plugin target 'MyPlugin' cannot be used because the feature isn't enabled (set SWIFTPM_ENABLE_PLUGINS=1 in environment)", behavior: .error)
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

    /// Contains the targets which have not been checked yet.
    private var uncheckedModules: Set<PackageModel.Target> = []

    /// Contains the products which have not been checked yet.
    private var uncheckedProducts: Set<PackageModel.Product> = []

    fileprivate static let xcTestMinimumDeploymentTargets = [
        PackageModel.Platform.macOS: PlatformVersion("10.15"),
        PackageModel.Platform.iOS: PlatformVersion("9.0"),
        PackageModel.Platform.tvOS: PlatformVersion("9.0"),
        PackageModel.Platform.watchOS: PlatformVersion("2.0"),
    ]

    @discardableResult
    init(
        _ manifest: Manifest,
        path: AbsolutePath = .root,
        binaryArtifacts: [BinaryArtifact] = [],
        shouldCreateMultipleTestProducts: Bool = false,
        allowPluginTargets: Bool = false,
        createREPLProduct: Bool = false,
        in fs: FileSystem,
        file: StaticString = #file,
        line: UInt = #line,
        _ body: (PackageBuilderTester, DiagnosticsEngineResult) -> Void
    ) {
        let diagnostics = DiagnosticsEngine()
        do {
            // FIXME: We should allow customizing root package boolean.
            let builder = PackageBuilder(
                identity: PackageIdentity(url: manifest.packageLocation), // FIXME
                manifest: manifest,
                productFilter: .everything,
                path: path,
                binaryArtifacts: binaryArtifacts,
                xcTestMinimumDeploymentTargets: Self.xcTestMinimumDeploymentTargets,
                fileSystem: fs,
                diagnostics: diagnostics,
                shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
                warnAboutImplicitExecutableTargets: true,
                allowPluginTargets: allowPluginTargets,
                createREPLProduct: createREPLProduct)
            let loadedPackage = try builder.construct()
            result = .package(loadedPackage)
            uncheckedModules = Set(loadedPackage.targets)
            uncheckedProducts = Set(loadedPackage.products)
        } catch {
            let errorString = String(describing: error)
            result = .error(errorString)
            diagnostics.emit(error: errorString)
        }

        DiagnosticsEngineTester(diagnostics) { diagnostics in
            body(self, diagnostics)
        }

        validateCheckedModules(file: file, line: line)
    }

    private func validateCheckedModules(file: StaticString, line: UInt) {
        if !uncheckedModules.isEmpty {
            XCTFail("Unchecked targets: \(uncheckedModules)", file: file, line: line)
        }

        if !uncheckedProducts.isEmpty {
            XCTFail("Unchecked products: \(uncheckedProducts)", file: file, line: line)
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

        func check(testManifestPath: String?, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(product.testManifest, testManifestPath.map({ AbsolutePath($0) }), file: file, line: line)
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

        func check(moduleMapType: ModuleMapType, file: StaticString = #file, line: UInt = #line) {
            guard case let target as ClangTarget = target else {
                return XCTFail("Module map type is being checked on a non-Clang target", file: file, line: line)
            }
            XCTAssertEqual(target.moduleMapType, moduleMapType, file: file, line: line)
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

        func checkResources(resources: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(Set(resources), Set(self.target.resources.map{ $0.path.pathString }), "unexpected resource files in \(target.name)", file: file, line: line)
        }

        func check(targetDependencies depsToCheck: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(Set(depsToCheck), Set(target.dependencies.compactMap { $0.target?.name }), "unexpected dependencies in \(target.name)", file: file, line: line)
        }

        func check(
            productDependencies depsToCheck: [Target.ProductReference],
            file: StaticString = #file,
            line: UInt = #line
        ) {
            let productDependencies = target.dependencies.compactMap { $0.product }
            guard depsToCheck.count == productDependencies.count else {
                return XCTFail("Incorrect product dependencies", file: file, line: line)
            }
            for (idx, element) in depsToCheck.enumerated() {
                let rhs = productDependencies[idx]
                guard element.name == rhs.name && element.package == rhs.package else {
                    return XCTFail("Incorrect product dependencies", file: file, line: line)
                }
            }
        }

        func check(dependencies: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(
                Set(dependencies),
                Set(target.dependencies.map({ $0.name })),
                "unexpected dependencies in \(target.name)",
                file: file,
                line: line
            )
        }

        func checkDependency(
            _ name: String,
            file: StaticString = #file,
            line: UInt = #line,
            _ body: (ModuleDependencyResult) -> Void
        ) {
            guard let dependency = target.dependencies.first(where: { $0.name == name }) else {
                return XCTFail("Module: \(name) not found", file: file, line: line)
            }
            body(ModuleDependencyResult(dependency))
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

        func checkPlatformOptions(_ platform: PackageModel.Platform, options: [String], file: StaticString = #file, line: UInt = #line) {
            let platform = target.getSupportedPlatform(for: platform)
            XCTAssertEqual(platform?.options, options, file: file, line: line)
        }
        
        func check(pluginCapability: PluginCapability, file: StaticString = #file, line: UInt = #line) {
            guard case let target as PluginTarget = target else {
                return XCTFail("Plugin capability is being checked on a target", file: file, line: line)
            }
            XCTAssertEqual(target.capability, pluginCapability, file: file, line: line)
        }
    }

    final class ModuleDependencyResult {
        let dependency: PackageModel.Target.Dependency

        fileprivate init(_ dependency: PackageModel.Target.Dependency) {
            self.dependency = dependency
        }

        func checkConditions(satisfy environment: BuildEnvironment, file: StaticString = #file, line: UInt = #line) {
            XCTAssert(dependency.conditions.allSatisfy { $0.satisfies(environment) }, file: file, line: line)
        }

        func checkConditions(
            dontSatisfy environment: BuildEnvironment,
            file: StaticString = #file,
            line: UInt = #line
        ) {
            XCTAssert(!dependency.conditions.allSatisfy { $0.satisfies(environment) }, file: file, line: line)
        }
    }
}
