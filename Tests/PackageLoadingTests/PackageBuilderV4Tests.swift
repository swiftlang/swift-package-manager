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

        var package = Package(
            name: "pkg",
            products: [
                .executable(name: "exec", targets: ["exec", "foo"]),
            ]
        )
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec", "foo"])
            }
        }

        package = Package(name: "pkg")
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("foo") { _ in }
            result.checkModule("exec") { _ in }
            result.checkProduct("exec") { productResult in
                productResult.check(type: .executable, targets: ["exec"])
            }
        }
    }

    func testTestsLayoutsv4() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Tests/ATests/Foo.swift")

        var package = Package(name: "Foo")
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .executable)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.swift")
            }

            result.checkModule("ATests") { moduleResult in
                moduleResult.check(c99name: "ATests", type: .test)
                moduleResult.checkSources(root: "/Tests/ATests", paths: "Foo.swift")
                moduleResult.check(dependencies: [])
            }
        }

        package = Package(
            name: "Foo",
            targets: [
                .target(name: "ATests", dependencies: ["A"]),
            ]
        )

        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .executable)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.swift")
            }

            result.checkModule("ATests") { moduleResult in
                moduleResult.check(c99name: "ATests", type: .test)
                moduleResult.checkSources(root: "/Tests/ATests", paths: "Foo.swift")
                moduleResult.check(dependencies: ["A"])
            }
        }
    }

    func testMultipleTestProducts() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/foo/foo.swift",
            "/Tests/fooTests/foo.swift",
            "/Tests/barTests/bar.swift"
        )
        let package = Package(name: "pkg")
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
        var package = Package(name: "pkg", targets: [.target(name: "Foo", dependencies: ["Bar"])])
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
                .target(name: "Bar", dependencies: ["Baz"])
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

    func testTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        // We create a manifest which uses byName target dependencies.
        let package = Package(
            name: "pkg",
            targets: [
                .target(
                    name: "Foo",
                    dependencies: ["Bar", "Baz", "Bam"]),
            ])

        PackageBuilderTester(package, in: fs) { result in
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
        // Reference a target which doesn't exist.
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.swift")
        var package = Package(name: "pkg", targets: [.target(name: "Random")])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("these referenced targets could not be found: Random fix: reference only valid targets")
        }

        // Reference an invalid dependency.
        package = Package(name: "pkg", targets: [.target(name: "pkg", dependencies: [.target(name: "Foo")])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("these referenced targets could not be found: Foo fix: reference only valid targets")
        }

        // Reference self in dependencies.
        package = Package(name: "pkg", targets: [.target(name: "pkg", dependencies: ["pkg"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("found cyclic dependency declaration: pkg -> pkg")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/pkg1/Foo.swift",
            "/Sources/pkg2/Foo.swift",
            "/Sources/pkg3/Foo.swift"
        )
        // Cyclic dependency.
        package = Package(name: "pkg", targets: [
            .target(name: "pkg1", dependencies: ["pkg2"]),
            .target(name: "pkg2", dependencies: ["pkg3"]),
            .target(name: "pkg3", dependencies: ["pkg1"]),
        ])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("found cyclic dependency declaration: pkg1 -> pkg2 -> pkg3 -> pkg1")
        }

        package = Package(name: "pkg", targets: [
            .target(name: "pkg1", dependencies: ["pkg2"]),
            .target(name: "pkg2", dependencies: ["pkg3"]),
            .target(name: "pkg3", dependencies: ["pkg2"]),
        ])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("found cyclic dependency declaration: pkg1 -> pkg2 -> pkg3 -> pkg2")
        }

        // Executable as dependency.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/lib/lib.swift")
        package = Package(name: "pkg", targets: [.target(name: "lib", dependencies: ["exec"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("exec") { moduleResult in
                moduleResult.check(c99name: "exec", type: .executable)
                moduleResult.checkSources(root: "/Sources/exec", paths: "main.swift")
            }

            result.checkModule("lib") { moduleResult in
                moduleResult.check(c99name: "lib", type: .library)
                moduleResult.checkSources(root: "/Sources/lib", paths: "lib.swift")
            }
        }

        // Reference a target which doesn't have sources.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/pkg1/Foo.swift",
            "/Sources/pkg2/readme.txt")
        package = Package(name: "pkg", targets: [.target(name: "pkg1", dependencies: ["pkg2"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("The target pkg2 in package pkg does not contain any valid source files.")
            result.checkModule("pkg1") { moduleResult in
                moduleResult.check(c99name: "pkg1", type: .library)
                moduleResult.checkSources(root: "/Sources/pkg1", paths: "Foo.swift")
            }
        }
    }

    func testInvalidManifestConfigForNonSystemModules() {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift"
        )
        var package = Package(name: "pkg", pkgConfig: "foo")

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("invalid configuration in 'pkg': pkgConfig should only be used with a System Module Package")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        package = Package(name: "pkg", providers: [.brew(["foo"])])

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("invalid configuration in 'pkg': providers should only be used with a System Module Package")
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

    static var allTests = [
        ("testCustomTargetDependencies", testCustomTargetDependencies),
        ("testDeclaredExecutableProducts", testDeclaredExecutableProducts),
        ("testInvalidManifestConfigForNonSystemModules", testInvalidManifestConfigForNonSystemModules),
        ("testManifestTargetDeclErrors", testManifestTargetDeclErrors),
        ("testMultipleTestProducts", testMultipleTestProducts),
        ("testTargetDependencies", testTargetDependencies),
        ("testTestsLayoutsv4", testTestsLayoutsv4),
        ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
    ]
}
