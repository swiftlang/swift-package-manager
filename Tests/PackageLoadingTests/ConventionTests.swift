/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageDescription
import PackageModel
import Utility

@testable import PackageLoading

/// Tests for the handling of source layout conventions.
class ConventionTests: XCTestCase {
    
    // MARK:- Valid Layouts Tests

    func testDotFilesAreIgnored() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/.Bar.swift",
            "/Foo.swift")

        let name = "DotFilesAreIgnored"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/", paths: "Foo.swift")
            }
        }
    }

    func testResolvesSingleSwiftLibraryModule() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.swift")

        let name = "SingleSwiftModule"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/", paths: "Foo.swift")
            }
        }

        // Single swift module inside Sources.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo.swift",
            "/Sources/Bar.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "Foo.swift", "Bar.swift")
            }
        }

        // Single swift module inside its own directory.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/Foo.swift",
            "/Sources/lib/Bar.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule("lib") { moduleResult in
                moduleResult.check(c99name: "lib", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/lib", paths: "Foo.swift", "Bar.swift")
            }
        }
    }

    func testResolvesSystemModulePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/module.modulemap")

        let name = "SystemModulePackage"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .systemModule, isTest: false)
                moduleResult.checkSources(root: "/", paths: "module.modulemap")
            }
        }
    }

    func testResolvesSingleClangLibraryModule() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.h",
            "/Foo.c")

        let name = "SingleClangModule"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/", paths: "Foo.c")
            }
        }

        // Single clang module inside Sources.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo.h",
            "/Sources/Foo.c")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "Foo.c")
            }
        }

        // Single clang module inside its own directory.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/lib/Foo.h",
            "/Sources/lib/Foo.c")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule("lib") { moduleResult in
                moduleResult.check(c99name: "lib", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/lib", paths: "Foo.c")
            }
        }
    }

    func testSingleExecutableSwiftModule() throws {
        // Single swift executable module.
        var fs = InMemoryFileSystem(emptyFiles:
            "/main.swift",
            "/Bar.swift")

        let name = "SingleExecutable"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/", paths: "main.swift", "Bar.swift")
            }
        }

        // Single swift executable module inside Sources.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "main.swift")
            }
        }

        // Single swift executable module inside its own directory.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule("exec") { moduleResult in
                moduleResult.check(c99name: "exec", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/exec", paths: "main.swift")
            }
        }
    }

    func testSingleExecutableClangModule() throws {
        // Single swift executable module.
        var fs = InMemoryFileSystem(emptyFiles:
            "/main.c",
            "/Bar.c")

        let name = "SingleExecutable"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/", paths: "main.c", "Bar.c")
            }
        }

        // Single swift executable module inside Sources.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.cpp")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "main.cpp")
            }
        }

        // Single swift executable module inside its own directory.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/c/main.c")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule("c") { moduleResult in
                moduleResult.check(c99name: "c", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/c", paths: "main.c")
            }
        }
    }

    func testDotSwiftSuffixDirectory() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/hello.swift/dummy",
            "/main.swift",
            "/Bar.swift")

        let name = "pkg"
        // FIXME: This fails currently, it is a bug.
        #if false
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/", paths: "main.swift", "Bar.swift")
            }
        }
        #endif

        fs = InMemoryFileSystem(emptyFiles:
            "/hello.swift/dummy",
            "/Sources/main.swift",
            "/Sources/Bar.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "main.swift", "Bar.swift")
            }
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exe/hello.swift/dummy",
            "/Sources/exe/main.swift",
            "/Sources/exe/Bar.swift")

        PackageBuilderTester(name, in: fs) { result in
            result.checkModule("exe") { moduleResult in
                moduleResult.check(c99name: "exe", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/exe", paths: "main.swift", "Bar.swift")
            }
        }
    }

    func testMultipleSwiftModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Sources/A/foo.swift",
            "/Sources/B/main.swift",
            "/Sources/C/Foo.swift")

        PackageBuilderTester("MultipleModules", in: fs) { result in
            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.swift", "foo.swift")
            }

            result.checkModule("B") { moduleResult in
                moduleResult.check(c99name: "B", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/B", paths: "main.swift")
            }

            result.checkModule("C") { moduleResult in
                moduleResult.check(c99name: "C", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/C", paths: "Foo.swift")
            }
        }
    }

    func testMultipleClangModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.c",
            "/Sources/A/foo.h",
            "/Sources/A/foo.c",
            "/Sources/B/include/foo.h",
            "/Sources/B/foo.c",
            "/Sources/B/bar.c",
            "/Sources/C/main.cpp")

        PackageBuilderTester("MultipleModules", in: fs) { result in
            result.checkModule("A") { moduleResult in
                moduleResult.check(c99name: "A", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.c", "foo.c")
            }

            result.checkModule("B") { moduleResult in
                moduleResult.check(c99name: "B", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/B", paths: "foo.c", "bar.c")
            }

            result.checkModule("C") { moduleResult in
                moduleResult.check(c99name: "C", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/C", paths: "main.cpp")
            }
        }
    }

    func testTestsLayouts() throws {
        // Single module layout.
        for singleModuleSource in ["/", "/Sources/", "/Sources/Foo/"].lazy.map(AbsolutePath.init) {
            let fs = InMemoryFileSystem(emptyFiles:
                singleModuleSource.appending(component: "Foo.swift").asString,
                "/Tests/FooTests/FooTests.swift",
                "/Tests/FooTests/BarTests.swift",
                "/Tests/BarTests/BazTests.swift")

            PackageBuilderTester("Foo", in: fs) { result in
                result.checkModule("Foo") { moduleResult in
                    moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                    moduleResult.checkSources(root: singleModuleSource.asString, paths: "Foo.swift")
                }

                result.checkModule("FooTests") { moduleResult in
                    moduleResult.check(c99name: "FooTests", type: .library, isTest: true)
                    moduleResult.checkSources(root: "/Tests/FooTests", paths: "FooTests.swift", "BarTests.swift")
                    moduleResult.check(dependencies: ["Foo"])
                    moduleResult.check(recursiveDependencies: ["Foo"])
                }

                result.checkModule("BarTests") { moduleResult in
                    moduleResult.check(c99name: "BarTests", type: .library, isTest: true)
                    moduleResult.checkSources(root: "/Tests/BarTests", paths: "BazTests.swift")
                    moduleResult.check(dependencies: [])
                    moduleResult.check(recursiveDependencies: [])
                }
            }
        }

        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift", // Swift exec
            "/Sources/B/Foo.swift",  // Swift lib
            "/Sources/D/Foo.c",      // Clang lib
            "/Sources/E/main.c",     // Clang exec
            "/Tests/ATests/Foo.swift",
            "/Tests/BTests/Foo.swift",
            "/Tests/DTests/Foo.swift",
            "/Tests/ETests/Foo.swift")

       PackageBuilderTester("Foo", in: fs) { result in
           result.checkModule("A") { moduleResult in
               moduleResult.check(c99name: "A", type: .executable, isTest: false)
               moduleResult.checkSources(root: "/Sources/A", paths: "main.swift")
           }

           result.checkModule("B") { moduleResult in
               moduleResult.check(c99name: "B", type: .library, isTest: false)
               moduleResult.checkSources(root: "/Sources/B", paths: "Foo.swift")
           }

           result.checkModule("D") { moduleResult in
               moduleResult.check(c99name: "D", type: .library, isTest: false)
               moduleResult.checkSources(root: "/Sources/D", paths: "Foo.c")
           }

           result.checkModule("E") { moduleResult in
               moduleResult.check(c99name: "E", type: .executable, isTest: false)
               moduleResult.checkSources(root: "/Sources/E", paths: "main.c")
           }

           result.checkModule("ATests") { moduleResult in
               moduleResult.check(c99name: "ATests", type: .library, isTest: true)
               moduleResult.checkSources(root: "/Tests/ATests", paths: "Foo.swift")
               moduleResult.check(dependencies: ["A"])
               moduleResult.check(recursiveDependencies: ["A"])
           }

           result.checkModule("BTests") { moduleResult in
               moduleResult.check(c99name: "BTests", type: .library, isTest: true)
               moduleResult.checkSources(root: "/Tests/BTests", paths: "Foo.swift")
               moduleResult.check(dependencies: ["B"])
               moduleResult.check(recursiveDependencies: ["B"])
           }

           result.checkModule("DTests") { moduleResult in
               moduleResult.check(c99name: "DTests", type: .library, isTest: true)
               moduleResult.checkSources(root: "/Tests/DTests", paths: "Foo.swift")
               moduleResult.check(dependencies: ["D"])
               moduleResult.check(recursiveDependencies: ["D"])
           }

           result.checkModule("ETests") { moduleResult in
               moduleResult.check(c99name: "ETests", type: .library, isTest: true)
               moduleResult.checkSources(root: "/Tests/ETests", paths: "Foo.swift")
               moduleResult.check(dependencies: ["E"])
               moduleResult.check(recursiveDependencies: ["E"])
           }
       }
    }

    func testNoSources() throws {
        PackageBuilderTester("MixedSources", in: InMemoryFileSystem()) { _ in }
    }

    func testMixedSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift",
            "/Sources/main.c")
        PackageBuilderTester("MixedSources", in: fs) { result in
            result.checkDiagnostic("the module at /Sources contains mixed language source files fix: use only a single language within a module")
        }
    }

    func testTwoModulesMixedLanguage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/ModuleA/main.swift",
            "/Sources/ModuleB/main.c",
            "/Sources/ModuleB/foo.c")

        PackageBuilderTester("MixedLanguage", in: fs) { result in
            result.checkModule("ModuleA") { moduleResult in
                moduleResult.check(c99name: "ModuleA", type: .executable)
                moduleResult.check(isTest: false)
                moduleResult.checkSources(root: "/Sources/ModuleA", paths: "main.swift")
            }

            result.checkModule("ModuleB") { moduleResult in
                moduleResult.check(c99name: "ModuleB", type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/ModuleB", paths: "main.c", "foo.c")
            }
        }
    }

    func testCInTests() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift",
            "/Tests/MyPackageTests/abc.c")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkModule("MyPackage") { moduleResult in
                moduleResult.check(type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "main.swift")
            }

            result.checkModule("MyPackageTests") { moduleResult in
                moduleResult.check(type: .library, isTest: true)
                moduleResult.checkSources(root: "/Tests/MyPackageTests", paths: "abc.c")
            }

          #if os(Linux)
            result.checkDiagnostic("warning: Ignoring MyPackageTests as C language in tests is not yet supported on Linux.")
          #endif
        }
    }

    func testValidSources() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/main.swift",
            "/noExtension",
            "/Package.swift",
            "/.git/anchor",
            "/.xcodeproj/anchor",
            "/.playground/anchor",
            "/Package.swift",
            "/Packages/MyPackage/main.c")
        let name = "pkg"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(type: .executable, isTest: false)
                moduleResult.checkSources(root: "/", paths: "main.swift")
            }
        }
    }

    func testCustomTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Sources/Baz/Baz.swift")

        // Direct.
        var package = PackageDescription.Package(name: "pkg", targets: [Target(name: "Foo", dependencies: ["Bar"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                moduleResult.check(dependencies: ["Bar"])
                moduleResult.check(recursiveDependencies: ["Bar"])
            }

            for module in ["Bar", "Baz"] {
                result.checkModule(module) { moduleResult in
                    moduleResult.check(c99name: module, type: .library, isTest: false)
                    moduleResult.checkSources(root: "/Sources/\(module)", paths: "\(module).swift")
                }
            }
        }

        // Transitive.
        package = PackageDescription.Package(name: "pkg",
                                                 targets: [Target(name: "Foo", dependencies: ["Bar"]),
                                                           Target(name: "Bar", dependencies: ["Baz"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
                moduleResult.check(dependencies: ["Bar"])
                moduleResult.check(recursiveDependencies: ["Baz", "Bar"])
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "Bar.swift")
                moduleResult.check(dependencies: ["Baz"])
                moduleResult.check(recursiveDependencies: ["Baz"])
            }

            result.checkModule("Baz") { moduleResult in
                moduleResult.check(c99name: "Baz", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Baz", paths: "Baz.swift")
            }
        }
    }

    func testTestTargetDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/source.swift",
            "/Sources/Bar/source.swift",
            "/Tests/FooTests/source.swift"
        )

        let package = PackageDescription.Package(name: "pkg", targets: [Target(name: "FooTests", dependencies: ["Bar"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "source.swift")
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "source.swift")
            }

            result.checkModule("FooTests") { moduleResult in
                moduleResult.check(c99name: "FooTests", type: .library, isTest: true)
                moduleResult.checkSources(root: "/Tests/FooTests", paths: "source.swift")
                moduleResult.check(dependencies: ["Bar"])
                moduleResult.check(recursiveDependencies: ["Bar"])
            }
        }
    }

    func testInvalidTestTargets() throws {
        // Test module in Sources/
        var fs = InMemoryFileSystem(emptyFiles:
            "/Sources/FooTests/source.swift")
        PackageBuilderTester("TestsInSources", in: fs) { result in
            result.checkDiagnostic("the module at Sources/FooTests has an invalid name (\'FooTests\'): the name of a non-test module has a ‘Tests’ suffix fix: rename the module at ‘Sources/FooTests’ to not have a ‘Tests’ suffix")
        }

        // Normal module in Tests/
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift",
            "/Tests/Foo/source.swift")
        PackageBuilderTester("TestsInSources", in: fs) { result in
            result.checkDiagnostic("the module at Tests/Foo has an invalid name (\'Foo\'): the name of a test module has no ‘Tests’ suffix fix: rename the module at ‘Tests/Foo’ to have a ‘Tests’ suffix")
        }
    }

    func testLooseSourceFileInTestsDir() throws {
        // Loose source file in Tests/
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift",
            "/Tests/source.swift")
        PackageBuilderTester("LooseSourceFileInTestsDir", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /Tests/source.swift fix: move the file(s) inside a module")
        }
    }
    
    func testManifestTargetDeclErrors() throws {
        // Reference a target which doesn't exist.
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.swift")
        var package = PackageDescription.Package(name: "pkg", targets: [Target(name: "Random")])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("these referenced modules could not be found: Random fix: reference only valid modules")
        }

        // Reference an invalid dependency.
        package = PackageDescription.Package(name: "pkg", targets: [Target(name: "pkg", dependencies: ["Foo"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("these referenced modules could not be found: Foo fix: reference only valid modules")
        }

        // Executable as dependency.
        // FIXME: maybe should support this and condiser it as build order dependency.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/exec/main.swift",
            "/Sources/lib/lib.swift")
        package = PackageDescription.Package(name: "pkg", targets: [Target(name: "lib", dependencies: ["exec"])])
        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("the target lib cannot have the executable exec as a dependency fix: move the shared logic inside a library, which can be referenced from both the target and the executable")
        }
    }

    func testProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift")
        let products = [Product(name: "libpm", type: .Library(.Dynamic), modules: ["Foo", "Bar"])]

        PackageBuilderTester("pkg", in: fs, products: products) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "Bar.swift")
            }

            result.checkProduct("libpm") { productResult in
                productResult.check(type: .Library(.Dynamic), modules: ["Bar", "Foo"])
            }
        }
    }

    func testTestsProduct() throws {
        // Make sure product name and test module name are different in single module package.
        var fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo.swift",
            "/Tests/FooTests/Bar.swift")

        PackageBuilderTester("Foo", in: fs, products: products) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "Foo.swift")
            }

            result.checkModule("FooTests") { moduleResult in
                moduleResult.check(c99name: "FooTests", type: .library, isTest: true)
                moduleResult.checkSources(root: "/Tests/FooTests", paths: "Bar.swift")
            }

            result.checkProduct("FooPackageTests") { productResult in
                productResult.check(type: .Test, modules: ["FooTests"])
            }
        }

        // Multi module tests package.
        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/Foo.swift",
            "/Sources/Bar/Bar.swift",
            "/Tests/FooTests/Foo.swift",
            "/Tests/BarTests/Bar.swift")

        PackageBuilderTester("Foo", in: fs, products: products) { result in
            result.checkModule("Foo") { moduleResult in
                moduleResult.check(c99name: "Foo", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Foo", paths: "Foo.swift")
            }

            result.checkModule("Bar") { moduleResult in
                moduleResult.check(c99name: "Bar", type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources/Bar", paths: "Bar.swift")
            }

            result.checkModule("FooTests") { moduleResult in
                moduleResult.check(c99name: "FooTests", type: .library, isTest: true)
                moduleResult.checkSources(root: "/Tests/FooTests", paths: "Foo.swift")
            }

            result.checkModule("BarTests") { moduleResult in
                moduleResult.check(c99name: "BarTests", type: .library, isTest: true)
                moduleResult.checkSources(root: "/Tests/BarTests", paths: "Bar.swift")
            }

            result.checkProduct("FooPackageTests") { productResult in
                productResult.check(type: .Test, modules: ["BarTests", "FooTests"])
            }
        }
    }

    func testBadProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo.swift")
        var products = [Product(name: "libpm", type: .Library(.Dynamic), modules: ["Foo", "Bar"])]
        PackageBuilderTester("Foo", in: fs, products: products) { result in
            result.checkDiagnostic("the product named libpm references a module that could not be found: Bar fix: reference only valid modules from the product")
        }

        products = [Product(name: "libpm", type: .Library(.Dynamic), modules: [])]
        PackageBuilderTester("Foo", in: fs, products: products) { result in
            result.checkDiagnostic("the product named libpm doesn\'t reference any modules fix: reference one or more modules from the product")
        }
    }

    func testVersionSpecificManifests() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Package.swift",
            "/Package@swift-999.swift",
            "/Sources/Package.swift",
            "/Sources/Package@swift-1.swift")

        let name = "Foo"
        PackageBuilderTester(name, in: fs) { result in
            result.checkModule(name) { moduleResult in
                moduleResult.check(c99name: name, type: .library, isTest: false)
                moduleResult.checkSources(root: "/Sources", paths: "Package.swift", "Package@swift-1.swift")
            }
        }
    }

    // MARK:- Invalid Layouts Tests

    func testMultipleRoots() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.swift",
            "/main.swift",
            "/src/FooBarLib/FooBar.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /Foo.swift, /main.swift fix: move the file(s) inside a module")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/BarExec/main.swift",
            "/Sources/BarExec/Bar.swift",
            "/src/FooBarLib/FooBar.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, multiple source roots found: /Sources, /src fix: remove the extra source roots, or add them to the source root exclude list")
        }
    }

    func testInvalidLayout1() throws {
        /*
         Package
         ├── main.swift   <-- invalid
         └── Sources
             └── File2.swift
        */
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Files2.swift",
            "/main.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /main.swift fix: move the file(s) inside a module")
        }
    }

    func testInvalidLayout2() throws {
        /*
         Package
         ├── main.swift  <-- invalid
         └── Bar
             └── Sources
                 └── File2.swift
        */
        // FIXME: We should allow this by not making modules at root and only inside Sources/.
        let fs = InMemoryFileSystem(emptyFiles:
            "/Bar/Sources/Files2.swift",
            "/main.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /main.swift fix: move the file(s) inside a module")
        }
    }

    func testInvalidLayout3() throws {
        /*
         Package
         └── Sources
             ├── main.swift  <-- Invalid
             └── Bar
                 └── File2.swift
        */
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift",
            "/Sources/Bar/File2.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /Sources/main.swift fix: move the file(s) inside a module")
        }
    }

    func testInvalidLayout4() throws {
        /*
         Package
         ├── main.swift  <-- Invalid
         └── Sources
             └── Bar
                 └── File2.swift
        */
        let fs = InMemoryFileSystem(emptyFiles:
            "/main.swift",
            "/Sources/Bar/File2.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /main.swift fix: move the file(s) inside a module")
        }
    }

    func testInvalidLayout5() throws {
        /*
         Package
         ├── File1.swift
         └── Foo
             └── Foo.swift  <-- Invalid
        */
        // for the simplest layout it is invalid to have any
        // subdirectories. It is the compromise you make.
        // the reason for this is mostly performance in
        // determineTargets() but also we are saying: this
        // layout is only for *very* simple projects.
        let fs = InMemoryFileSystem(emptyFiles:
            "/File1.swift",
            "/Foo/Foo.swift")

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the package has an unsupported layout, unexpected source file(s) found: /File1.swift fix: move the file(s) inside a module")
        }
    }

    func testNoSourcesInModule() throws {
        let fs = InMemoryFileSystem()
        try fs.createDirectory(AbsolutePath("/Sources/Module"), recursive: true)

        PackageBuilderTester("MyPackage", in: fs) { result in
            result.checkDiagnostic("the module at /Sources/Module does not contain any source files fix: either remove the module folder, or add a source file to the module")
        }
    }

    func testExcludes() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/main.swift",
            "/Sources/A/foo.swift", // File will be excluded.
            "/Sources/B/main.swift" // Dir will be excluded.
        )

        // Excluding everything.
        var package = PackageDescription.Package(name: "pkg", exclude: ["."])
        PackageBuilderTester(package, in: fs) { _ in }

        // Test excluding a file and a directory.
        package = PackageDescription.Package(name: "pkg", exclude: ["Sources/A/foo.swift", "Sources/B"])
        PackageBuilderTester(package, in: fs) { result in
            result.checkModule("A") { moduleResult in
                moduleResult.check(type: .executable, isTest: false)
                moduleResult.checkSources(root: "/Sources/A", paths: "main.swift")
            }
        }
    }

    func testInvalidManifestConfigForNonSystemModules() {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Sources/main.swift"
        )
        var package = PackageDescription.Package(name: "pkg", pkgConfig: "foo")

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("invalid configuration in 'pkg': pkgConfig should only be used with a System Module Package")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/Sources/Foo/main.c"
        )
        package = PackageDescription.Package(name: "pkg", providers: [.Brew("foo")])

        PackageBuilderTester(package, in: fs) { result in
            result.checkDiagnostic("invalid configuration in 'pkg': providers should only be used with a System Module Package")
        }
    }

    static var allTests = [
        ("testCInTests", testCInTests),
        ("testDotFilesAreIgnored", testDotFilesAreIgnored),
        ("testDotSwiftSuffixDirectory", testDotSwiftSuffixDirectory),
        ("testMixedSources", testMixedSources),
        ("testMultipleClangModules", testMultipleClangModules),
        ("testMultipleSwiftModules", testMultipleSwiftModules),
        ("testNoSources", testNoSources),
        ("testResolvesSingleClangLibraryModule", testResolvesSingleClangLibraryModule),
        ("testResolvesSingleSwiftLibraryModule", testResolvesSingleSwiftLibraryModule),
        ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
        ("testSingleExecutableClangModule", testSingleExecutableClangModule),
        ("testSingleExecutableSwiftModule", testSingleExecutableSwiftModule),
        ("testTestsLayouts", testTestsLayouts),
        ("testTwoModulesMixedLanguage", testTwoModulesMixedLanguage),
        ("testMultipleRoots", testMultipleRoots),
        ("testInvalidLayout1", testInvalidLayout1),
        ("testInvalidLayout2", testInvalidLayout2),
        ("testInvalidLayout3", testInvalidLayout3),
        ("testInvalidLayout4", testInvalidLayout4),
        ("testInvalidLayout5", testInvalidLayout5),
        ("testNoSourcesInModule", testNoSourcesInModule),
        ("testValidSources", testValidSources),
        ("testExcludes", testExcludes),
        ("testCustomTargetDependencies", testCustomTargetDependencies),
        ("testTestTargetDependencies", testTestTargetDependencies),
        ("testInvalidTestTargets", testInvalidTestTargets),
        ("testLooseSourceFileInTestsDir", testLooseSourceFileInTestsDir),
        ("testManifestTargetDeclErrors", testManifestTargetDeclErrors),
        ("testProducts", testProducts),
        ("testBadProducts", testBadProducts),
        ("testVersionSpecificManifests", testVersionSpecificManifests),
        ("testTestsProduct", testTestsProduct),
        ("testInvalidManifestConfigForNonSystemModules", testInvalidManifestConfigForNonSystemModules),
    ]
}

/// Loads a package using PackageBuilder at the given path.
///
/// - Parameters:
///     - package: PackageDescription instance to use for loading this package.
///     - path: Directory where the package is located.
///     - in: FileSystem in which the package should be loaded from.
///     - products: List of products in the package.
///     - warningStream: OutputByteStream to be passed to package builder.
///
/// - Throws: ModuleError, ProductError
private func loadPackage(_ package: PackageDescription.Package, path: AbsolutePath, in fs: FileSystem, products: [PackageDescription.Product], warningStream: OutputByteStream) throws -> PackageModel.Package {
    let manifest = Manifest(path: path.appending(component: Manifest.filename), url: "", package: package, products: products, version: nil)
    let builder = PackageBuilder(manifest: manifest, path: path, fileSystem: fs, warningStream: warningStream)
    return try builder.construct(includingTestModules: true)
}

extension PackageModel.Package {
    var allModules: [Module] {
        return modules + testModules
    }
}

final class PackageBuilderTester {
    private enum Result {
        case package(PackageModel.Package)
        case error(String)
    }

    /// Contains the result produced by PackageBuilder.
    private let result: Result

    /// Contains the diagnostics which have not been checked yet.
    private var uncheckedDiagnostics = Set<String>()

    /// Setting this to true will disable checking for any unchecked diagnostics prodcuted by PackageBuilder during loading process.
    var ignoreDiagnostics: Bool = false

    /// Contains the modules which have not been checked yet.
    private var uncheckedModules = Set<Module>()

    /// Setting this to true will disable checking for any unchecked module.
    var ignoreOtherModules: Bool = false

    @discardableResult
   convenience init(_ name: String, path: AbsolutePath = .root, in fs: FileSystem, products: [PackageDescription.Product] = [], file: StaticString = #file, line: UInt = #line, _ body: (PackageBuilderTester) -> Void) {
       let package = Package(name: name)
       self.init(package, path: path, in: fs, products: products, file: file, line: line, body)
    }

    @discardableResult
    init(_ package: PackageDescription.Package, path: AbsolutePath = .root, in fs: FileSystem, products: [PackageDescription.Product] = [], file: StaticString = #file, line: UInt = #line, _ body: (PackageBuilderTester) -> Void) {
        do {
            let warningStream = BufferedOutputByteStream()
            let loadedPackage = try loadPackage(package, path: path, in: fs, products: products, warningStream: warningStream)
            result = .package(loadedPackage)
            uncheckedModules = Set(loadedPackage.allModules)
            // FIXME: Find a better way. Maybe Package can keep array of warnings.
            uncheckedDiagnostics = Set(warningStream.bytes.asReadableString.characters.split(separator: "\n").map(String.init))
        } catch {
            let errorStr = String(describing: error)
            result = .error(errorStr)
            uncheckedDiagnostics.insert(errorStr)
        }
        body(self)
        validateDiagnostics(file: file, line: line)
        validateCheckedModules(file: file, line: line)
    }

    private func validateDiagnostics(file: StaticString, line: UInt) {
        guard !ignoreDiagnostics && !uncheckedDiagnostics.isEmpty else { return }
        XCTFail("Unchecked diagnostics: \(uncheckedDiagnostics)", file: file, line: line)
    }

    private func validateCheckedModules(file: StaticString, line: UInt) {
        guard !ignoreOtherModules && !uncheckedModules.isEmpty else { return }
        XCTFail("Unchecked modules: \(uncheckedModules)", file: file, line: line)
    }

    func checkDiagnostic(_ str: String, file: StaticString = #file, line: UInt = #line) {
        if uncheckedDiagnostics.contains(str) {
            uncheckedDiagnostics.remove(str)
        } else {
            XCTFail("\(result) did not have error: \(str) or is already checked", file: file, line: line)
        }
    }

    func checkModule(_ name: String, file: StaticString = #file, line: UInt = #line, _ body: ((ModuleResult) -> Void)? = nil) {
        guard case .package(let package) = result else {
            return XCTFail("Expected package did not load \(self)", file: file, line: line)
        }
        guard let module = package.allModules.first(where: {$0.name == name}) else {
            return XCTFail("Module: \(name) not found", file: file, line: line)
        }
        uncheckedModules.remove(module)
        body?(ModuleResult(module))
    }

    func checkProduct(_ name: String, file: StaticString = #file, line: UInt = #line, _ body: ((ProductResult) -> Void)? = nil) {
        guard case .package(let package) = result else {
            return XCTFail("Expected package did not load \(self)", file: file, line: line)
        }
        guard let product = package.products.first(where: {$0.name == name}) else {
            return XCTFail("Product: \(name) not found", file: file, line: line)
        }
        body?(ProductResult(product))
    }

    final class ProductResult {
        private let product: PackageModel.Product

        init(_ product: PackageModel.Product) {
            self.product = product
        }

        func check(type: PackageDescription.ProductType, modules: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(product.type, type, file: file, line: line)
            XCTAssertEqual(product.modules.map{$0.name}.sorted(), modules, file: file, line: line)
        }
    }

    final class ModuleResult {
        private let module: Module

        fileprivate init(_ module: Module) {
            self.module = module
        }

        func check(c99name: String? = nil, type: ModuleType? = nil, isTest: Bool? = nil, file: StaticString = #file, line: UInt = #line) {
            if let c99name = c99name {
                XCTAssertEqual(module.c99name, c99name, file: file, line: line)
            }
            if let type = type {
                XCTAssertEqual(module.type, type, file: file, line: line)
            }
            if let isTest = isTest {
                XCTAssertEqual(module.isTest, isTest, file: file, line: line)
            }
        }

        func checkSources(root: String? = nil, sources paths: [String], file: StaticString = #file, line: UInt = #line) {
            if let root = root {
                XCTAssertEqual(module.sources.root, AbsolutePath(root), file: file, line: line)
            }
            let sources = Set(self.module.sources.relativePaths.map{$0.asString})
            XCTAssertEqual(sources, Set(paths), "unexpected source files in \(module.name)", file: file, line: line)
        }

        func checkSources(root: String? = nil, paths: String..., file: StaticString = #file, line: UInt = #line) {
            checkSources(root: root, sources: paths, file: file, line: line)
        }

        func check(dependencies depsToCheck: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(Set(depsToCheck), Set(module.dependencies.map{$0.name}), "unexpected dependencies in \(module.name)")
        }

        func check(recursiveDependencies: [String], file: StaticString = #file, line: UInt = #line) {
            // We need to check in build order here.
            XCTAssertEqual(module.recursiveDependencies.map { $0.name }, recursiveDependencies, file: file, line: line)
        }
    }
}
