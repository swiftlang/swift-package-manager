/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCUtility
import PackageModel
import PackageGraph
import Build
import XCBuildSupport
import SPMTestSupport

@testable import PackageLoading

class PIFBuilderTests: XCTestCase {
    let inputsDir = AbsolutePath(#file).parentDirectory.appending(components: "Inputs")

  #if os(macOS)
    func testOrdering() {
        // Repeat multiple times to detect non-deterministic shuffling due to sets.
        for _ in 0..<10 {
            let fs = InMemoryFileSystem(emptyFiles:
                "/A/Sources/A1/main.swift",
                "/A/Sources/A2/lib.swift",
                "/A/Sources/A3/lib.swift",
                "/B/Sources/B1/main.swift",
                "/B/Sources/B2/lib.swift"
            )

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                fs: fs,
                diagnostics: diagnostics,
                manifests: [
                    Manifest.createManifest(
                        name: "B",
                        path: "/B",
                        url: "/B",
                        v: .v5_2,
                        packageKind: .remote,
                        products: [
                            .init(name: "bexe", type: .executable, targets: ["B1"]),
                            .init(name: "blib", type: .library(.static), targets: ["B2"]),
                        ],
                        targets: [
                            .init(name: "B2", dependencies: []),
                            .init(name: "B1", dependencies: ["B2"]),
                        ]),
                    Manifest.createManifest(
                        name: "A",
                        path: "/A",
                        url: "/A",
                        v: .v5_2,
                        packageKind: .root,
                        dependencies: [
                            .init(name: "B", url: "/B", requirement: .branch("master")),
                        ],
                        products: [
                            .init(name: "alib", type: .library(.static), targets: ["A2"]),
                            .init(name: "aexe", type: .executable, targets: ["A1"]),
                        ],
                        targets: [
                            .init(name: "A1", dependencies: ["A3", "A2", .product(name: "blib", package: "B")]),
                            .init(name: "A2", dependencies: []),
                            .init(name: "A3", dependencies: []),
                        ]),
                ]
            )

            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            let pif = builder.construct()

            XCTAssertNoDiagnostics(diagnostics)

            let projectNames = pif.workspace.projects.map({ $0.name })
            XCTAssertEqual(projectNames, ["A", "B", "Aggregate"])
            let projectATargetNames = pif.workspace.projects[0].targets.map({ $0.name })
            XCTAssertEqual(projectATargetNames, ["aexe", "alib", "A2", "A3"])
            let targetAExeDependencies = pif.workspace.projects[0].targets[0].dependencies
            XCTAssertEqual(targetAExeDependencies.map{ $0.targetGUID }, ["PACKAGE-PRODUCT:blib", "PACKAGE-TARGET:A2", "PACKAGE-TARGET:A3"])
            let projectBTargetNames = pif.workspace.projects[1].targets.map({ $0.name })
            XCTAssertEqual(projectBTargetNames, ["blib", "B2"])
        }
    }

    func testProject() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Tests/FooTests/tests.swift",
            "/Bar/Sources/BarLib/lib.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    defaultLocalization: "fr",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    dependencies: [
                        .init(name: "Bar", url: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        .init(name: "foo", dependencies: [.product(name: "BarLib", package: "Bar")]),
                        .init(name: "FooTests", type: .test),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14"),
                        PlatformDescription(name: "ios", version: "12"),
                        PlatformDescription(name: "tvos", version: "11"),
                        PlatformDescription(name: "watchos", version: "6"),
                    ],
                    path: "/Bar",
                    url: "/Bar",
                    v: .v5_2,
                    packageKind: .remote,
                    products: [
                        .init(name: "BarLib", targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "BarLib"),
                        .init(name: "BarTests", type: .test),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
        let pif = builder.construct()

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                XCTAssertEqual(project.path.pathString, "/Foo")
                XCTAssertEqual(project.projectDirectory.pathString, "/Foo")
                XCTAssertEqual(project.name, "Foo")
                XCTAssertEqual(project.developmentRegion, "fr")

                project.checkTarget("PACKAGE-PRODUCT:foo")
                project.checkTarget("PACKAGE-PRODUCT:FooTests")

                project.checkBuildConfiguration("Debug") { configuration in
                    XCTAssertEqual(configuration.guid, "PACKAGE:/Foo::BUILDCONFIG_Debug")
                    XCTAssertEqual(configuration.name, "Debug")

                    configuration.checkAllBuildSettings { settings in
                        XCTAssertEqual(settings[.CLANG_ENABLE_OBJC_ARC], "YES")
                        XCTAssertEqual(settings[.CODE_SIGN_IDENTITY], "")
                        XCTAssertEqual(settings[.CODE_SIGNING_REQUIRED], "NO")
                        XCTAssertEqual(settings[.COPY_PHASE_STRIP], "NO")
                        XCTAssertEqual(settings[.DEBUG_INFORMATION_FORMAT], "dwarf")
                        XCTAssertEqual(settings[.DYLIB_INSTALL_NAME_BASE], "@rpath")
                        XCTAssertEqual(settings[.ENABLE_NS_ASSERTIONS], "YES")
                        XCTAssertEqual(settings[.ENABLE_TESTABILITY], "YES")
                        XCTAssertEqual(settings[.ENABLE_TESTING_SEARCH_PATHS], "YES")
                        XCTAssertEqual(settings[.ENTITLEMENTS_REQUIRED], "NO")
                        XCTAssertEqual(settings[.GCC_OPTIMIZATION_LEVEL], "0")
                        XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "SWIFT_PACKAGE", "DEBUG=1"])
                        XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], "9.0")
                        XCTAssertEqual(settings[.KEEP_PRIVATE_EXTERNS], "NO")
                        XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], "10.10")
                        XCTAssertEqual(settings[.ONLY_ACTIVE_ARCH], "YES")
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.PRODUCT_NAME], "$(TARGET_NAME)")
                        XCTAssertEqual(settings[.SDK_VARIANT], "auto")
                        XCTAssertEqual(settings[.SDKROOT], "auto")
                        XCTAssertEqual(settings[.SKIP_INSTALL], "YES")
                        XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["$(AVAILABLE_PLATFORMS)"])
                        XCTAssertEqual(settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS], ["$(inherited)", "SWIFT_PACKAGE", "DEBUG"])
                        XCTAssertEqual(settings[.SWIFT_INSTALL_OBJC_HEADER], "NO")
                        XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "")
                        XCTAssertEqual(settings[.SWIFT_OPTIMIZATION_LEVEL], "-Onone")
                        XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], "9.0")
                        XCTAssertEqual(settings[.USE_HEADERMAP], "NO")
                        XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], "2.0")

                        let frameworksSearchPaths = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]
                        for platform in [PIF.BuildSettings.Platform.macOS, .iOS, .tvOS] {
                            XCTAssertEqual(settings[.FRAMEWORK_SEARCH_PATHS, for: platform], frameworksSearchPaths)
                        }

                        for platform in PIF.BuildSettings.Platform.allCases {
                            XCTAssertEqual(settings[.SPECIALIZATION_SDK_OPTIONS, for: platform], nil)
                        }
                    }
                }

                project.checkBuildConfiguration("Release") { configuration in
                    XCTAssertEqual(configuration.guid, "PACKAGE:/Foo::BUILDCONFIG_Release")
                    XCTAssertEqual(configuration.name, "Release")

                    configuration.checkAllBuildSettings { settings in
                        XCTAssertEqual(settings[.CLANG_ENABLE_OBJC_ARC], "YES")
                        XCTAssertEqual(settings[.CODE_SIGN_IDENTITY], "")
                        XCTAssertEqual(settings[.CODE_SIGNING_REQUIRED], "NO")
                        XCTAssertEqual(settings[.COPY_PHASE_STRIP], "YES")
                        XCTAssertEqual(settings[.DEBUG_INFORMATION_FORMAT], "dwarf-with-dsym")
                        XCTAssertEqual(settings[.DYLIB_INSTALL_NAME_BASE], "@rpath")
                        XCTAssertEqual(settings[.ENABLE_TESTING_SEARCH_PATHS], "YES")
                        XCTAssertEqual(settings[.ENTITLEMENTS_REQUIRED], "NO")
                        XCTAssertEqual(settings[.GCC_OPTIMIZATION_LEVEL], "s")
                        XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "SWIFT_PACKAGE"])
                        XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], "9.0")
                        XCTAssertEqual(settings[.KEEP_PRIVATE_EXTERNS], "NO")
                        XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], "10.10")
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.PRODUCT_NAME], "$(TARGET_NAME)")
                        XCTAssertEqual(settings[.SDK_VARIANT], "auto")
                        XCTAssertEqual(settings[.SDKROOT], "auto")
                        XCTAssertEqual(settings[.SKIP_INSTALL], "YES")
                        XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["$(AVAILABLE_PLATFORMS)"])
                        XCTAssertEqual(settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS], ["$(inherited)", "SWIFT_PACKAGE"])
                        XCTAssertEqual(settings[.SWIFT_INSTALL_OBJC_HEADER], "NO")
                        XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "")
                        XCTAssertEqual(settings[.SWIFT_OPTIMIZATION_LEVEL], "-Owholemodule")
                        XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], "9.0")
                        XCTAssertEqual(settings[.USE_HEADERMAP], "NO")
                        XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], "2.0")

                        let frameworksSearchPaths = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]
                        for platform in [PIF.BuildSettings.Platform.macOS, .iOS, .tvOS] {
                            XCTAssertEqual(settings[.FRAMEWORK_SEARCH_PATHS, for: platform], frameworksSearchPaths)
                        }

                        for platform in PIF.BuildSettings.Platform.allCases {
                            XCTAssertEqual(settings[.SPECIALIZATION_SDK_OPTIONS, for: platform], nil)
                        }
                    }
                }
            }

            workspace.checkProject("PACKAGE:/Bar") { project in
                XCTAssertEqual(project.path.pathString, "/Bar")
                XCTAssertEqual(project.projectDirectory.pathString, "/Bar")
                XCTAssertEqual(project.name, "Bar")
                XCTAssertEqual(project.developmentRegion, "en")

                project.checkTarget("PACKAGE-PRODUCT:BarLib")

                project.checkBuildConfiguration("Debug") { configuration in
                    XCTAssertEqual(configuration.guid, "PACKAGE:/Bar::BUILDCONFIG_Debug")
                    XCTAssertEqual(configuration.name, "Debug")

                    configuration.checkAllBuildSettings { settings in
                        XCTAssertEqual(settings[.CLANG_ENABLE_OBJC_ARC], "YES")
                        XCTAssertEqual(settings[.CODE_SIGN_IDENTITY], "")
                        XCTAssertEqual(settings[.CODE_SIGNING_REQUIRED], "NO")
                        XCTAssertEqual(settings[.COPY_PHASE_STRIP], "NO")
                        XCTAssertEqual(settings[.DEBUG_INFORMATION_FORMAT], "dwarf")
                        XCTAssertEqual(settings[.DYLIB_INSTALL_NAME_BASE], "@rpath")
                        XCTAssertEqual(settings[.ENABLE_NS_ASSERTIONS], "YES")
                        XCTAssertEqual(settings[.ENABLE_TESTABILITY], "YES")
                        XCTAssertEqual(settings[.ENABLE_TESTING_SEARCH_PATHS], "YES")
                        XCTAssertEqual(settings[.ENTITLEMENTS_REQUIRED], "NO")
                        XCTAssertEqual(settings[.GCC_OPTIMIZATION_LEVEL], "0")
                        XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "SWIFT_PACKAGE", "DEBUG=1"])
                        XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], "12.0")
                        XCTAssertEqual(settings[.KEEP_PRIVATE_EXTERNS], "NO")
                        XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], "10.14")
                        XCTAssertEqual(settings[.ONLY_ACTIVE_ARCH], "YES")
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.PRODUCT_NAME], "$(TARGET_NAME)")
                        XCTAssertEqual(settings[.SDK_VARIANT], "auto")
                        XCTAssertEqual(settings[.SDKROOT], "auto")
                        XCTAssertEqual(settings[.SKIP_INSTALL], "YES")
                        XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["$(AVAILABLE_PLATFORMS)"])
                        XCTAssertEqual(settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS], ["$(inherited)", "SWIFT_PACKAGE", "DEBUG"])
                        XCTAssertEqual(settings[.SWIFT_INSTALL_OBJC_HEADER], "NO")
                        XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "")
                        XCTAssertEqual(settings[.SWIFT_OPTIMIZATION_LEVEL], "-Onone")
                        XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], "11.0")
                        XCTAssertEqual(settings[.USE_HEADERMAP], "NO")
                        XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], "6.0")

                        let frameworksSearchPaths = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]
                        for platform in [PIF.BuildSettings.Platform.macOS, .iOS, .tvOS] {
                            XCTAssertEqual(settings[.FRAMEWORK_SEARCH_PATHS, for: platform], frameworksSearchPaths)
                        }

                        for platform in PIF.BuildSettings.Platform.allCases {
                            XCTAssertEqual(settings[.SPECIALIZATION_SDK_OPTIONS, for: platform], nil)
                        }
                    }
                }

                project.checkBuildConfiguration("Release") { configuration in
                    XCTAssertEqual(configuration.guid, "PACKAGE:/Bar::BUILDCONFIG_Release")
                    XCTAssertEqual(configuration.name, "Release")

                    configuration.checkAllBuildSettings { settings in
                        XCTAssertEqual(settings[.CLANG_ENABLE_OBJC_ARC], "YES")
                        XCTAssertEqual(settings[.CODE_SIGN_IDENTITY], "")
                        XCTAssertEqual(settings[.CODE_SIGNING_REQUIRED], "NO")
                        XCTAssertEqual(settings[.COPY_PHASE_STRIP], "YES")
                        XCTAssertEqual(settings[.DEBUG_INFORMATION_FORMAT], "dwarf-with-dsym")
                        XCTAssertEqual(settings[.DYLIB_INSTALL_NAME_BASE], "@rpath")
                        XCTAssertEqual(settings[.ENABLE_TESTING_SEARCH_PATHS], "YES")
                        XCTAssertEqual(settings[.ENTITLEMENTS_REQUIRED], "NO")
                        XCTAssertEqual(settings[.GCC_OPTIMIZATION_LEVEL], "s")
                        XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "SWIFT_PACKAGE"])
                        XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], "12.0")
                        XCTAssertEqual(settings[.KEEP_PRIVATE_EXTERNS], "NO")
                        XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], "10.14")
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.PRODUCT_NAME], "$(TARGET_NAME)")
                        XCTAssertEqual(settings[.SDK_VARIANT], "auto")
                        XCTAssertEqual(settings[.SDKROOT], "auto")
                        XCTAssertEqual(settings[.SKIP_INSTALL], "YES")
                        XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["$(AVAILABLE_PLATFORMS)"])
                        XCTAssertEqual(settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS], ["$(inherited)", "SWIFT_PACKAGE"])
                        XCTAssertEqual(settings[.SWIFT_INSTALL_OBJC_HEADER], "NO")
                        XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "")
                        XCTAssertEqual(settings[.SWIFT_OPTIMIZATION_LEVEL], "-Owholemodule")
                        XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], "11.0")
                        XCTAssertEqual(settings[.USE_HEADERMAP], "NO")
                        XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], "6.0")

                        let frameworksSearchPaths = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]
                        for platform in [PIF.BuildSettings.Platform.macOS, .iOS, .tvOS] {
                            XCTAssertEqual(settings[.FRAMEWORK_SEARCH_PATHS, for: platform], frameworksSearchPaths)
                        }

                        for platform in PIF.BuildSettings.Platform.allCases {
                            XCTAssertEqual(settings[.SPECIALIZATION_SDK_OPTIONS, for: platform], nil)
                        }
                    }
                }
            }

            workspace.checkProject("AGGREGATE") { project in
                project.checkAggregateTarget("ALL-EXCLUDING-TESTS") { target in
                    XCTAssertEqual(target.name, PIFBuilder.allExcludingTestsTargetName)
                    XCTAssertEqual(target.dependencies, ["PACKAGE-PRODUCT:foo"])
                }

                project.checkAggregateTarget("ALL-INCLUDING-TESTS") { target in
                    XCTAssertEqual(target.name, PIFBuilder.allIncludingTestsTargetName)
                    XCTAssertEqual(target.dependencies, ["PACKAGE-PRODUCT:foo", "PACKAGE-PRODUCT:FooTests"])
                }
            }
        }
    }

    func testExecutableProducts() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/cfoo/main.c",
            "/Foo/Sources/FooLib/lib.swift",
            "/Foo/Sources/SystemLib/module.modulemap",
            "/Bar/Sources/bar/main.swift",
            "/Bar/Sources/cbar/main.c",
            "/Bar/Sources/BarLib/lib.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    swiftLanguageVersions: [.v4_2, .v5],
                    dependencies: [
                        .init(name: "Bar", url: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        .init(name: "foo", dependencies: [
                            "FooLib",
                            "SystemLib",
                            "cfoo",
                            .product(name: "bar", package: "Bar"),
                            .product(name: "cbar", package: "Bar")
                        ]),
                        .init(name: "cfoo"),
                        .init(name: "SystemLib", type: .system, pkgConfig: "Foo"),
                        .init(name: "FooLib", dependencies: [
                            .product(name: "BarLib", package: "Bar"),
                        ])
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    v: .v4_2,
                    packageKind: .remote,
                    cLanguageStandard: "c11",
                    cxxLanguageStandard: "c++14",
                    swiftLanguageVersions: [.v4_2],
                    products: [
                        .init(name: "bar", type: .executable, targets: ["bar"]),
                        .init(name: "cbar", type: .executable, targets: ["cbar"]),
                        .init(name: "BarLib", type: .library(.static), targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "bar", dependencies: ["BarLib"]),
                        .init(name: "cbar"),
                        .init(name: "BarLib"),
                    ]),
            ]
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in

                // Root Swift executable target

                project.checkTarget("PACKAGE-PRODUCT:foo") { target in
                    XCTAssertEqual(target.name, "foo")
                    XCTAssertEqual(target.productType, .executable)
                    XCTAssertEqual(target.productName, "foo")
                    XCTAssertEqual(target.dependencies, [
                        "PACKAGE-PRODUCT:cfoo",
                        "PACKAGE-PRODUCT:bar",
                        "PACKAGE-PRODUCT:BarLib",
                        "PACKAGE-PRODUCT:cbar",
                        "PACKAGE-TARGET:FooLib",
                        "PACKAGE-TARGET:SystemLib"
                    ])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/foo/main.swift"])
                    XCTAssertEqual(target.frameworks, [
                        "PACKAGE-TARGET:FooLib",
                        "PACKAGE-PRODUCT:BarLib",
                        "PACKAGE-PRODUCT:cbar",
                        "PACKAGE-PRODUCT:bar",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:foo::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "foo")
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/bin")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], ["$(inherited)", "@executable_path/../lib"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "foo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "foo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "foo")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "foo")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:foo::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "foo")
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/bin")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], ["$(inherited)", "@executable_path/../lib"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "foo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "foo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "foo")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "foo")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }

                // Root Clang executable target

                project.checkTarget("PACKAGE-PRODUCT:cfoo") { target in
                    XCTAssertEqual(target.name, "cfoo")
                    XCTAssertEqual(target.productType, .executable)
                    XCTAssertEqual(target.productName, "cfoo")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/cfoo/main.c"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:cfoo::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "cfoo")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Foo/Sources/cfoo/include"])
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/bin")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], ["$(inherited)", "@executable_path/../lib"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "cfoo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "cfoo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "cfoo")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "cfoo")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:cfoo::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "cfoo")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Foo/Sources/cfoo/include"])
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/bin")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], ["$(inherited)", "@executable_path/../lib"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "cfoo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "cfoo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "cfoo")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "cfoo")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }
            }

            workspace.checkProject("PACKAGE:/Bar") { project in

                // Non-root Swift executable target

                project.checkTarget("PACKAGE-PRODUCT:bar") { target in
                    XCTAssertEqual(target.name, "bar")
                    XCTAssertEqual(target.productType, .executable)
                    XCTAssertEqual(target.productName, "bar")
                    XCTAssertEqual(target.dependencies, ["PACKAGE-TARGET:BarLib"])
                    XCTAssertEqual(target.sources, ["/Bar/Sources/bar/main.swift"])
                    XCTAssertEqual(target.frameworks, ["PACKAGE-TARGET:BarLib"])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:bar::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "bar")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "bar")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "bar")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "bar")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "4.2")
                            XCTAssertEqual(settings[.TARGET_NAME], "bar")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:bar::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "bar")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "bar")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "bar")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "bar")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "4.2")
                            XCTAssertEqual(settings[.TARGET_NAME], "bar")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }

                // Non-root Clang executable target

                project.checkTarget("PACKAGE-PRODUCT:cbar") { target in
                    XCTAssertEqual(target.name, "cbar")
                    XCTAssertEqual(target.productType, .executable)
                    XCTAssertEqual(target.productName, "cbar")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, ["/Bar/Sources/cbar/main.c"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:cbar::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_CXX_LANGUAGE_STANDARD], "c++14")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "cbar")
                            XCTAssertEqual(settings[.GCC_C_LANGUAGE_STANDARD], "c11")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Bar/Sources/cbar/include"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "cbar")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "cbar")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "cbar")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "cbar")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:cbar::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_CXX_LANGUAGE_STANDARD], "c++14")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "cbar")
                            XCTAssertEqual(settings[.GCC_C_LANGUAGE_STANDARD], "c11")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Bar/Sources/cbar/include"])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "cbar")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "cbar")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "cbar")
                            XCTAssertEqual(settings[.SDKROOT], "macosx")
                            XCTAssertEqual(settings[.SUPPORTED_PLATFORMS], ["macosx", "linux"])
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "cbar")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }
            }
        }
    }

    func testTestProducts() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooTests/FooTests.swift",
            "/Foo/Sources/CFooTests/CFooTests.m",
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/FooLib/lib.swift",
            "/Foo/Sources/SystemLib/module.modulemap",
            "/Bar/Sources/bar/main.swift",
            "/Bar/Sources/BarTests/BarTests.swift",
            "/Bar/Sources/CBarTests/CBarTests.m",
            "/Bar/Sources/BarLib/lib.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    swiftLanguageVersions: [.v4_2, .v5],
                    dependencies: [
                        .init(name: "Bar", url: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        .init(name: "FooTests", dependencies: [
                            "foo",
                            "FooLib",
                            .product(name: "bar", package: "Bar"),
                            "SystemLib",
                        ], type: .test),
                        .init(name: "CFooTests", type: .test),
                        .init(name: "foo"),
                        .init(name: "SystemLib", type: .system, pkgConfig: "Foo"),
                        .init(name: "FooLib", dependencies: [
                            .product(name: "BarLib", package: "Bar"),
                        ])
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    v: .v4_2,
                    packageKind: .remote,
                    cLanguageStandard: "c11",
                    cxxLanguageStandard: "c++14",
                    swiftLanguageVersions: [.v4_2],
                    products: [
                        .init(name: "bar", type: .executable, targets: ["bar"]),
                        .init(name: "BarLib", type: .library(.static), targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "bar", dependencies: ["BarLib"]),
                        .init(name: "BarTests", dependencies: ["BarLib"], type: .test),
                        .init(name: "CBarTests", type: .test),
                        .init(name: "BarLib"),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:FooTests") { target in
                    XCTAssertEqual(target.name, "FooTests")
                    XCTAssertEqual(target.productType, .unitTest)
                    XCTAssertEqual(target.productName, "FooTests")
                    XCTAssertEqual(target.dependencies, [
                        "PACKAGE-PRODUCT:foo",
                        "PACKAGE-PRODUCT:bar",
                        "PACKAGE-PRODUCT:BarLib",
                        "PACKAGE-TARGET:FooLib",
                        "PACKAGE-TARGET:SystemLib"
                    ])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/FooTests/FooTests.swift"])
                    XCTAssertEqual(target.frameworks, [
                        "PACKAGE-PRODUCT:bar",
                        "PACKAGE-TARGET:FooLib",
                        "PACKAGE-PRODUCT:BarLib",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooTests::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooTests")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], [
                                "$(inherited)",
                                "@loader_path/Frameworks",
                                "@loader_path/../Frameworks"
                            ])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooTests")
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooTests")
                            XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .watchOS).versionString)
                            XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .iOS).versionString)
                            XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .tvOS).versionString)
                            XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooTests::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooTests")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], [
                                "$(inherited)",
                                "@loader_path/Frameworks",
                                "@loader_path/../Frameworks"
                            ])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooTests")
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooTests")
                            XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .watchOS).versionString)
                            XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .iOS).versionString)
                            XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .tvOS).versionString)
                            XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString)
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }

                project.checkTarget("PACKAGE-PRODUCT:CFooTests") { target in
                    XCTAssertEqual(target.name, "CFooTests")
                    XCTAssertEqual(target.productType, .unitTest)
                    XCTAssertEqual(target.productName, "CFooTests")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/CFooTests/CFooTests.m"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:CFooTests::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "CFooTests")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], [
                                "$(inherited)",
                                "/Foo/Sources/CFooTests/include"
                            ])
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], [
                                "$(inherited)",
                                "@loader_path/Frameworks",
                                "@loader_path/../Frameworks"
                            ])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "CFooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "CFooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "CFooTests")
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "CFooTests")
                            XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .watchOS).versionString)
                            XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .iOS).versionString)
                            XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .tvOS).versionString)
                            XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:CFooTests::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "CFooTests")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], [
                                "$(inherited)",
                                "/Foo/Sources/CFooTests/include"
                            ])
                            XCTAssertEqual(settings[.LD_RUNPATH_SEARCH_PATHS], [
                                "$(inherited)",
                                "@loader_path/Frameworks",
                                "@loader_path/../Frameworks"
                            ])
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "CFooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "CFooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "CFooTests")
                            XCTAssertEqual(settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB], "YES")
                            XCTAssertEqual(settings[.SWIFT_FORCE_STATIC_LINK_STDLIB], "NO")
                            XCTAssertEqual(settings[.TARGET_NAME], "CFooTests")
                            XCTAssertEqual(settings[.WATCHOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .watchOS).versionString)
                            XCTAssertEqual(settings[.IPHONEOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .iOS).versionString)
                            XCTAssertEqual(settings[.TVOS_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .tvOS).versionString)
                            XCTAssertEqual(settings[.MACOSX_DEPLOYMENT_TARGET], MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString)
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }
            }

            workspace.checkProject("PACKAGE:/Bar") { project in
                project.checkNoTarget("PACKAGE-PRODUCT:BarTests")
                project.checkNoTarget("PACKAGE-PRODUCT:CBarTests")
            }
        }
    }

    func testLibraryProducts() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooLib1/lib.swift",
            "/Foo/Sources/FooLib2/lib.swift",
            "/Foo/Sources/SystemLib/module.modulemap",
            "/Bar/Sources/BarLib/lib.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    swiftLanguageVersions: [.v4_2, .v5],
                    dependencies: [
                        .init(name: "Bar", url: "/Bar", requirement: .branch("master")),
                    ],
                    products: [
                        .init(name: "FooLib1", type: .library(.static), targets: ["FooLib1"]),
                        .init(name: "FooLib2", type: .library(.automatic), targets: ["FooLib2"]),
                    ],
                    targets: [
                        .init(name: "FooLib1", dependencies: ["SystemLib", "FooLib2"]),
                        .init(name: "FooLib2", dependencies: [
                            .product(name: "BarLib", package: "Bar"),
                        ]),
                        .init(name: "SystemLib", type: .system, pkgConfig: "Foo"),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    v: .v4_2,
                    packageKind: .remote,
                    cLanguageStandard: "c11",
                    cxxLanguageStandard: "c++14",
                    swiftLanguageVersions: [.v4_2],
                    products: [
                        .init(name: "BarLib", type: .library(.dynamic), targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "BarLib"),
                    ]),
            ]
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:FooLib1") { target in
                    XCTAssertEqual(target.name, "FooLib1")
                    XCTAssertEqual(target.productType, .packageProduct)
                    XCTAssertEqual(target.productName, "libFooLib1.a")
                    XCTAssertEqual(target.dependencies, [
                        "PACKAGE-TARGET:FooLib1",
                        "PACKAGE-TARGET:FooLib2",
                        "PACKAGE-PRODUCT:BarLib",
                    ])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [
                        "PACKAGE-TARGET:FooLib1",
                        "PACKAGE-TARGET:FooLib2",
                        "PACKAGE-PRODUCT:BarLib",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooLib1::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooLib1::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                        }
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        // No imparted build settings.
                    }
                }

                project.checkTarget("PACKAGE-PRODUCT:FooLib2") { target in
                    XCTAssertEqual(target.name, "FooLib2")
                    XCTAssertEqual(target.productType, .packageProduct)
                    XCTAssertEqual(target.productName, "libFooLib2.a")
                    XCTAssertEqual(target.dependencies, [
                        "PACKAGE-TARGET:FooLib2",
                        "PACKAGE-PRODUCT:BarLib",
                    ])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [
                        "PACKAGE-TARGET:FooLib2",
                        "PACKAGE-PRODUCT:BarLib",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooLib2::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                            XCTAssertEqual(settings[.APPLICATION_EXTENSION_API_ONLY], "YES")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:FooLib2::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                            XCTAssertEqual(settings[.APPLICATION_EXTENSION_API_ONLY], "YES")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }
            }

            workspace.checkProject("PACKAGE:/Bar") { project in
                project.checkTarget("PACKAGE-PRODUCT:BarLib") { target in
                    XCTAssertEqual(target.name, "BarLib")
                    XCTAssertEqual(target.productType, .framework)
                    XCTAssertEqual(target.productName, "BarLib.framework")
                    XCTAssertEqual(target.dependencies, ["PACKAGE-TARGET:BarLib"])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, ["PACKAGE-TARGET:BarLib"])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:BarLib::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                        XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                        XCTAssertEqual(settings[.APPLICATION_EXTENSION_API_ONLY], "YES")
                            XCTAssertEqual(settings[.BUILT_PRODUCTS_DIR], "$(BUILT_PRODUCTS_DIR)/PackageFrameworks")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.CURRENT_PROJECT_VERSION], "1")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "BarLib")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/lib")
                            XCTAssertEqual(settings[.MARKETING_VERSION], "1.0")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "BarLib")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.TARGET_BUILD_DIR], "$(TARGET_BUILD_DIR)/PackageFrameworks")
                            XCTAssertEqual(settings[.TARGET_NAME], "BarLib")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-PRODUCT:BarLib::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.APPLICATION_EXTENSION_API_ONLY], "YES")
                            XCTAssertEqual(settings[.BUILT_PRODUCTS_DIR], "$(BUILT_PRODUCTS_DIR)/PackageFrameworks")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.CURRENT_PROJECT_VERSION], "1")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "BarLib")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.INSTALL_PATH], "/usr/local/lib")
                            XCTAssertEqual(settings[.MARKETING_VERSION], "1.0")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "BarLib")
                            XCTAssertEqual(settings[.SKIP_INSTALL], "NO")
                            XCTAssertEqual(settings[.TARGET_BUILD_DIR], "$(TARGET_BUILD_DIR)/PackageFrameworks")
                            XCTAssertEqual(settings[.TARGET_NAME], "BarLib")
                            XCTAssertEqual(settings[.USES_SWIFTPM_UNSAFE_FLAGS], "NO")
                        }
                    }

                    target.checkNoImpartedBuildSettings()
                }
            }
        }
    }

    func testLibraryTargets() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/FooLib1/lib.swift",
            "/Foo/Sources/FooLib2/lib.cpp",
            "/Foo/Sources/SystemLib/module.modulemap",
            "/Bar/Sources/BarLib/lib.c"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    cxxLanguageStandard: "c++14",
                    swiftLanguageVersions: [.v4_2, .v5],
                    dependencies: [
                        .init(name: "Bar", url: "/Bar", requirement: .branch("master")),
                    ],
                    targets: [
                        .init(name: "FooLib1", dependencies: ["SystemLib", "FooLib2"]),
                        .init(name: "FooLib2", dependencies: [
                            .product(name: "BarLib", package: "Bar"),
                        ]),
                        .init(name: "SystemLib", type: .system, pkgConfig: "Foo"),
                    ]),
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    v: .v4_2,
                    packageKind: .remote,
                    cLanguageStandard: "c11",
                    swiftLanguageVersions: [.v4_2],
                    products: [
                        .init(name: "BarLib", type: .library(.dynamic), targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "BarLib"),
                    ]),
            ]
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-TARGET:FooLib1") { target in
                    XCTAssertEqual(target.name, "FooLib1")
                    XCTAssertEqual(target.productType, .objectFile)
                    XCTAssertEqual(target.productName, "FooLib1.o")
                    XCTAssertEqual(target.dependencies, [
                        "PACKAGE-TARGET:FooLib2",
                        "PACKAGE-TARGET:SystemLib",
                        "PACKAGE-PRODUCT:BarLib",
                    ])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/FooLib1/lib.swift"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:FooLib1::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooLib1.o")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module FooLib1 {
                                    header "FooLib1-Swift.h"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib1.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooLib1")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooLib1")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooLib1.o")
                            XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_DIR], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)")
                            XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "FooLib1-Swift.h")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooLib1")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:FooLib1::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooLib1.o")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module FooLib1 {
                                    header "FooLib1-Swift.h"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib1.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooLib1")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooLib1")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooLib1.o")
                            XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_DIR], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)")
                            XCTAssertEqual(settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME], "FooLib1-Swift.h")
                            XCTAssertEqual(settings[.SWIFT_VERSION], "5")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooLib1")
                        }
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.OTHER_CFLAGS], [
                            "$(inherited)",
                            "-fmodule-map-file=$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib1.modulemap"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                    }
                }

                project.checkTarget("PACKAGE-TARGET:FooLib2") { target in
                    XCTAssertEqual(target.name, "FooLib2")
                    XCTAssertEqual(target.productType, .objectFile)
                    XCTAssertEqual(target.productName, "FooLib2.o")
                    XCTAssertEqual(target.dependencies, ["PACKAGE-PRODUCT:BarLib"])
                    XCTAssertEqual(target.sources, ["/Foo/Sources/FooLib2/lib.cpp"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:FooLib2::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.CLANG_CXX_LANGUAGE_STANDARD], "c++14")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooLib2.o")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Foo/Sources/FooLib2/include"])
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module FooLib2 {
                                    umbrella "/Foo/Sources/FooLib2/include"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib2.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooLib2")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooLib2")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooLib2.o")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooLib2")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:FooLib2::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.CLANG_CXX_LANGUAGE_STANDARD], "c++14")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "FooLib2.o")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Foo/Sources/FooLib2/include"])
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module FooLib2 {
                                    umbrella "/Foo/Sources/FooLib2/include"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib2.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "FooLib2")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "FooLib2")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "FooLib2.o")
                            XCTAssertEqual(settings[.TARGET_NAME], "FooLib2")
                        }
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Foo/Sources/FooLib2/include"])
                        XCTAssertEqual(settings[.OTHER_CFLAGS], [
                            "$(inherited)",
                            "-fmodule-map-file=$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib2.modulemap"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.OTHER_LDFLAGS], ["$(inherited)", "-lc++"])
                        XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], [
                            "$(inherited)",
                            "-Xcc", "-fmodule-map-file=$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/FooLib2.modulemap"
                        ])
                    }
                }
            }

            workspace.checkProject("PACKAGE:/Bar") { project in
                project.checkTarget("PACKAGE-TARGET:BarLib") { target in
                    XCTAssertEqual(target.name, "BarLib")
                    XCTAssertEqual(target.productType, .objectFile)
                    XCTAssertEqual(target.productName, "BarLib.o")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, ["/Bar/Sources/BarLib/lib.c"])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:BarLib::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "BarLib.o")
                            XCTAssertEqual(settings[.GCC_C_LANGUAGE_STANDARD], "c11")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Bar/Sources/BarLib/include"])
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module BarLib {
                                    umbrella "/Bar/Sources/BarLib/include"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/BarLib.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "BarLib.o")
                            XCTAssertEqual(settings[.TARGET_NAME], "BarLib")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:BarLib::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS], "NO")
                            XCTAssertEqual(settings[.CLANG_ENABLE_MODULES], "YES")
                            XCTAssertEqual(settings[.DEFINES_MODULE], "YES")
                            XCTAssertEqual(settings[.EXECUTABLE_NAME], "BarLib.o")
                            XCTAssertEqual(settings[.GCC_C_LANGUAGE_STANDARD], "c11")
                            XCTAssertEqual(settings[.GENERATE_MASTER_OBJECT_FILE], "NO")
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Bar/Sources/BarLib/include"])
                            XCTAssertEqual(settings[.MACH_O_TYPE], "mh_object")
                            XCTAssertEqual(settings[.MODULEMAP_FILE_CONTENTS], """
                                module BarLib {
                                    umbrella "/Bar/Sources/BarLib/include"
                                    export *
                                }
                                """)
                            XCTAssertEqual(settings[.MODULEMAP_PATH], "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/BarLib.modulemap")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "regular")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "BarLib")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "BarLib.o")
                            XCTAssertEqual(settings[.TARGET_NAME], "BarLib")
                        }
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], ["$(inherited)", "/Bar/Sources/BarLib/include"])
                        XCTAssertEqual(settings[.OTHER_CFLAGS], [
                            "$(inherited)",
                            "-fmodule-map-file=$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/BarLib.modulemap"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], [
                            "$(inherited)",
                            "-Xcc", "-fmodule-map-file=$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)/BarLib.modulemap"
                        ])
                    }
                }
            }
        }
    }

    func testLibraryTargetsAsDylib() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Bar/Sources/BarLib/lib.c"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    v: .v4_2,
                    packageKind: .root,
                    cLanguageStandard: "c11",
                    swiftLanguageVersions: [.v4_2],
                    products: [
                        .init(name: "BarLib", type: .library(.dynamic), targets: ["BarLib"]),
                    ],
                    targets: [
                        .init(name: "BarLib"),
                    ]),
            ]
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(shouldCreateDylibForDynamicProducts: true), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Bar") { project in
                project.checkTarget("PACKAGE-PRODUCT:BarLib") { target in
                    XCTAssertEqual(target.name, "BarLib")
                    XCTAssertEqual(target.productType, .dynamicLibrary)
                    XCTAssertEqual(target.productName, "libBarLib.dylib")
                }
            }
        }
    }

    func testSystemLibraryTargets() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/SystemLib1/module.modulemap",
            "/Foo/Sources/SystemLib2/module.modulemap"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_2,
                    packageKind: .root,
                    cxxLanguageStandard: "c++14",
                    swiftLanguageVersions: [.v4_2, .v5],
                    targets: [
                        .init(name: "SystemLib1", type: .system),
                        .init(name: "SystemLib2", type: .system, pkgConfig: "Foo"),
                    ]),
            ]
        )

        var pif: PIF.TopLevelObject!
        try! withCustomEnv(["PKG_CONFIG_PATH": inputsDir.pathString]) {
            let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
            pif = builder.construct()
        }

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkAggregateTarget("PACKAGE-TARGET:SystemLib1") { target in
                    XCTAssertEqual(target.name, "SystemLib1")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:SystemLib1::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkNoBuildSettings()
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:SystemLib1::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkNoBuildSettings()
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.OTHER_CFLAGS], [
                            "$(inherited)",
                            "-fmodule-map-file=/Foo/Sources/SystemLib1/module.modulemap"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], [
                            "$(inherited)",
                            "-Xcc", "-fmodule-map-file=/Foo/Sources/SystemLib1/module.modulemap"
                        ])
                    }
                }

                project.checkAggregateTarget("PACKAGE-TARGET:SystemLib2") { target in
                    XCTAssertEqual(target.name, "SystemLib2")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:SystemLib2::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkNoBuildSettings()
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-TARGET:SystemLib2::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkNoBuildSettings()
                    }

                    target.checkAllImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.OTHER_CFLAGS], [
                            "$(inherited)",
                            "-fmodule-map-file=/Foo/Sources/SystemLib2/module.modulemap",
                            "-I/path/to/inc",
                            "-I\(self.inputsDir)"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDFLAGS], [
                            "$(inherited)",
                            "-L/usr/da/lib",
                            "-lSystemModule",
                            "-lok"
                        ])
                        XCTAssertEqual(settings[.OTHER_LDRFLAGS], [])
                        XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], [
                            "$(inherited)",
                            "-Xcc", "-fmodule-map-file=/Foo/Sources/SystemLib2/module.modulemap",
                            "-I/path/to/inc",
                            "-I\(self.inputsDir)"
                        ])
                    }
                }
            }
        }
    }

    func testBinaryTargets() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/FooLib/lib.swift",
            "/Foo/Sources/FooTests/FooTests.swift",
            "/Foo/BinaryLibrary.xcframework/Info.plist"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_3,
                    packageKind: .root,
                    products: [
                        .init(name: "FooLib", type: .library(.automatic), targets: ["FooLib"]),
                    ],
                    targets: [
                        .init(name: "foo", dependencies: ["BinaryLibrary"]),
                        .init(name: "FooLib", dependencies: ["BinaryLibrary"]),
                        .init(name: "FooTests", dependencies: ["BinaryLibrary"], type: .test),
                        .init(name: "BinaryLibrary", path: "BinaryLibrary.xcframework", type: .binary)
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
        let pif = builder.construct()

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:foo") { target in
                    XCTAssert(target.frameworks.contains("/Foo/BinaryLibrary.xcframework"))
                }

                project.checkTarget("PACKAGE-PRODUCT:FooLib") { target in
                    XCTAssert(target.frameworks.contains("/Foo/BinaryLibrary.xcframework"))
                }

                project.checkTarget("PACKAGE-PRODUCT:FooTests") { target in
                    XCTAssert(target.frameworks.contains("/Foo/BinaryLibrary.xcframework"))
                }

                project.checkTarget("PACKAGE-TARGET:FooLib") { target in
                    XCTAssert(target.frameworks.contains("/Foo/BinaryLibrary.xcframework"))
                }
            }
        }
    }

    func testResources() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/foo/Resources/Data.plist",
            "/Foo/Sources/foo/Resources/Database.xcdatamodel",
            "/Foo/Sources/FooLib/lib.swift",
            "/Foo/Sources/FooLib/Resources/Data.plist",
            "/Foo/Sources/FooLib/Resources/Database.xcdatamodel",
            "/Foo/Sources/FooTests/FooTests.swift",
            "/Foo/Sources/FooTests/Resources/Data.plist",
            "/Foo/Sources/FooTests/Resources/Database.xcdatamodel"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_3,
                    packageKind: .root,
                    products: [
                        .init(name: "FooLib", type: .library(.automatic), targets: ["FooLib"]),
                    ],
                    targets: [
                        .init(name: "foo", resources: [
                            .init(rule: .process, path: "Resources")
                        ]),
                        .init(name: "FooLib", resources: [
                            .init(rule: .process, path: "Resources")
                        ]),
                        .init(name: "FooTests", resources: [
                            .init(rule: .process, path: "Resources")
                        ], type: .test),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
        let pif = builder.construct()

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:foo") { target in
                    XCTAssertEqual(target.dependencies, ["PACKAGE-RESOURCE:foo"])
                    XCTAssert(target.sources.contains("/Foo/Sources/foo/Resources/Database.xcdatamodel"))

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_foo")
                        }
                    }

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_foo")
                        }
                    }

                    target.checkImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES], nil)
                    }
                }

                project.checkTarget("PACKAGE-RESOURCE:foo") { target in
                    XCTAssertEqual(target.name, "Foo_foo")
                    XCTAssertEqual(target.productType, .bundle)
                    XCTAssertEqual(target.productName, "Foo_foo")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [])
                    XCTAssertEqual(target.resources, [
                        "/Foo/Sources/foo/Resources/Data.plist",
                        "/Foo/Sources/foo/Resources/Database.xcdatamodel",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-RESOURCE:foo::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.TARGET_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "Foo.foo.resources")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "resource")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-RESOURCE:foo::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.TARGET_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "Foo_foo")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "Foo.foo.resources")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "resource")
                        }
                    }
                }

                project.checkTarget("PACKAGE-PRODUCT:FooLib") { target in
                    XCTAssert(!target.dependencies.contains("PACKAGE-RESOURCE:FooLib"))
                    XCTAssert(!target.sources.contains("/Foo/Sources/FooLib/Resources/Database.xcdatamodel"))

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], nil)
                        }
                    }

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], nil)
                        }
                    }

                    target.checkImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES], nil)
                    }
                }

                project.checkTarget("PACKAGE-TARGET:FooLib") { target in
                    XCTAssertEqual(target.dependencies, ["PACKAGE-RESOURCE:FooLib"])
                    XCTAssert(target.sources.contains("/Foo/Sources/FooLib/Resources/Database.xcdatamodel"))

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_FooLib")
                        }
                    }

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_FooLib")
                        }
                    }

                    target.checkImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES], ["$(inherited)", "Foo_FooLib"])
                    }
                }

                project.checkTarget("PACKAGE-PRODUCT:FooTests") { target in
                    XCTAssertEqual(target.dependencies, ["PACKAGE-RESOURCE:FooTests"])
                    XCTAssert(target.sources.contains("/Foo/Sources/FooTests/Resources/Database.xcdatamodel"))

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_FooTests")
                        }
                    }

                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_BUNDLE_NAME], "Foo_FooTests")
                        }
                    }

                    target.checkImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES], nil)
                    }
                }

                project.checkTarget("PACKAGE-RESOURCE:FooTests") { target in
                    XCTAssertEqual(target.name, "Foo_FooTests")
                    XCTAssertEqual(target.productType, .bundle)
                    XCTAssertEqual(target.productName, "Foo_FooTests")
                    XCTAssertEqual(target.dependencies, [])
                    XCTAssertEqual(target.sources, [])
                    XCTAssertEqual(target.frameworks, [])
                    XCTAssertEqual(target.resources, [
                        "/Foo/Sources/FooTests/Resources/Data.plist",
                        "/Foo/Sources/FooTests/Resources/Database.xcdatamodel",
                    ])

                    target.checkBuildConfiguration("Debug") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-RESOURCE:FooTests::BUILDCONFIG_Debug")
                        XCTAssertEqual(configuration.name, "Debug")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.TARGET_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "Foo.FooTests.resources")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "resource")
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        XCTAssertEqual(configuration.guid, "PACKAGE-RESOURCE:FooTests::BUILDCONFIG_Release")
                        XCTAssertEqual(configuration.name, "Release")
                        configuration.checkAllBuildSettings { settings in
                            XCTAssertEqual(settings[.TARGET_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_MODULE_NAME], "Foo_FooTests")
                            XCTAssertEqual(settings[.PRODUCT_BUNDLE_IDENTIFIER], "Foo.FooTests.resources")
                            XCTAssertEqual(settings[.GENERATE_INFOPLIST_FILE], "YES")
                            XCTAssertEqual(settings[.PACKAGE_RESOURCE_TARGET_KIND], "resource")
                        }
                    }
                }
            }
        }
    }

    func testBuildSettings() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/FooLib/lib.swift",
            "/Foo/Sources/FooTests/FooTests.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5,
                    packageKind: .root,
                    products: [
                        .init(name: "FooLib", type: .library(.automatic), targets: ["FooLib"]),
                    ],
                    targets: [
                        .init(name: "foo", settings: [
                            .init(
                                tool: .c,
                                name: .define,
                                value: ["ENABLE_BEST_MODE"]),
                            .init(
                                tool: .cxx,
                                name: .headerSearchPath,
                                value: ["some/path"],
                                condition: .init(platformNames: ["macos"])),
                            .init(
                                tool: .linker,
                                name: .linkedLibrary,
                                value: ["z"],
                                condition: .init(config: "debug")),
                            .init(
                                tool: .swift,
                                name: .unsafeFlags,
                                value: ["-secret", "value"],
                                condition: .init(platformNames: ["macos", "linux"], config: "release")),
                        ]),
                        .init(name: "FooLib", settings: [
                            .init(
                                tool: .c,
                                name: .define,
                                value: ["ENABLE_BEST_MODE"]),
                            .init(
                                tool: .cxx,
                                name: .headerSearchPath,
                                value: ["some/path"],
                                condition: .init(platformNames: ["macos"])),
                            .init(
                                tool: .linker,
                                name: .linkedLibrary,
                                value: ["z"],
                                condition: .init(config: "debug")),
                            .init(
                                tool: .swift,
                                name: .unsafeFlags,
                                value: ["-secret", "value"],
                                condition: .init(platformNames: ["macos", "linux"], config: "release")),
                        ]),
                        .init(name: "FooTests", type: .test, settings: [
                            .init(
                                tool: .c,
                                name: .define,
                                value: ["ENABLE_BEST_MODE"]),
                            .init(
                                tool: .cxx,
                                name: .headerSearchPath,
                                value: ["some/path"],
                                condition: .init(platformNames: ["macos"])),
                            .init(
                                tool: .linker,
                                name: .linkedLibrary,
                                value: ["z"],
                                condition: .init(config: "debug")),
                            .init(
                                tool: .swift,
                                name: .unsafeFlags,
                                value: ["-secret", "value"],
                                condition: .init(platformNames: ["macos", "linux"], config: "release")),
                        ]),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
        let pif = builder.construct()

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:foo") { target in
                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/foo/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], ["$(inherited)", "-lz"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/foo/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .macOS], ["$(inherited)", "-secret", "value"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .linux], ["$(inherited)", "-secret", "value"])
                        }
                    }
                }

                project.checkTarget("PACKAGE-PRODUCT:FooLib") { target in
                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], nil)
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], nil)
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                        }
                    }
                }

                project.checkTarget("PACKAGE-TARGET:FooLib") { target in
                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/FooLib/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], ["$(inherited)", "-lz"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/FooLib/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .macOS], ["$(inherited)", "-secret", "value"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .linux], ["$(inherited)", "-secret", "value"])
                        }
                    }

                    target.checkImpartedBuildSettings { settings in
                        XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], nil)
                        XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                        XCTAssertEqual(settings[.OTHER_LDFLAGS], ["$(inherited)", "-lz"])
                        XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                    }
                }

                project.checkTarget("PACKAGE-PRODUCT:FooTests") { target in
                    target.checkBuildConfiguration("Debug") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/FooTests/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], ["$(inherited)", "-lz"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                        }
                    }

                    target.checkBuildConfiguration("Release") { configuration in
                        configuration.checkBuildSettings { settings in
                            XCTAssertEqual(settings[.GCC_PREPROCESSOR_DEFINITIONS], ["$(inherited)", "ENABLE_BEST_MODE"])
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS], nil)
                            XCTAssertEqual(settings[.HEADER_SEARCH_PATHS, for: .macOS], [
                                "$(inherited)",
                                "/Foo/Sources/FooTests/some/path"
                            ])
                            XCTAssertEqual(settings[.OTHER_LDFLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS], nil)
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .macOS], ["$(inherited)", "-secret", "value"])
                            XCTAssertEqual(settings[.OTHER_SWIFT_FLAGS, for: .linux], ["$(inherited)", "-secret", "value"])
                        }
                    }
                }
            }
        }
    }

    func testConditionalDependencies() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift",
            "/Foo/Sources/FooLib1/lib.swift",
            "/Foo/Sources/FooLib2/lib.swift",
            "/Foo/Sources/FooTests/FooTests.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_3,
                    packageKind: .root,
                    targets: [
                        .init(name: "foo", dependencies: [
                            .target(name: "FooLib1", condition: .init(platformNames: ["macos"])),
                            .target(name: "FooLib2", condition: .init(platformNames: ["ios"])),
                        ]),
                        .init(name: "FooLib1"),
                        .init(name: "FooLib2"),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        XCTAssertNoDiagnostics(diagnostics)

        let builder = PIFBuilder(
            graph: graph,
            parameters: .mock(),
            diagnostics: diagnostics)
        let pif = builder.construct()

        let expectedFilters: [PIF.GUID: [PIF.PlatformFilter]] = [
            "PACKAGE-TARGET:FooLib1": PIF.PlatformFilter.macOSFilters,
            "PACKAGE-TARGET:FooLib2": PIF.PlatformFilter.iOSFilters,
        ]

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkTarget("PACKAGE-PRODUCT:foo") { target in
                    XCTAssertEqual(target.dependencies, ["PACKAGE-TARGET:FooLib1", "PACKAGE-TARGET:FooLib2"])
                    XCTAssertEqual(target.frameworks, ["PACKAGE-TARGET:FooLib1", "PACKAGE-TARGET:FooLib2"])

                    let dependencyMap = Dictionary(uniqueKeysWithValues: target.baseTarget.dependencies.map{ ($0.targetGUID, $0.platformFilters) })
                    XCTAssertEqual(dependencyMap, expectedFilters)

                    let frameworksBuildFiles = target.baseTarget.buildPhases.first{ $0 is PIF.FrameworksBuildPhase }?.buildFiles ?? []
                    let frameworksBuildFilesMap = Dictionary(uniqueKeysWithValues: frameworksBuildFiles.compactMap{ file -> (PIF.GUID, [PIF.PlatformFilter])? in
                        switch file.reference {
                        case .target(let guid):
                            return (guid, file.platformFilters)
                        case .file:
                            return nil
                        }
                    })
                    XCTAssertEqual(dependencyMap, frameworksBuildFilesMap)
                }
            }
        }
    }

    func testSDKOptions() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/foo/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(
            fs: fs,
            diagnostics: diagnostics,
            manifests: [
                Manifest.createManifest(
                    name: "Foo",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14", options: ["best"]),
                    ],
                    path: "/Foo",
                    url: "/Foo",
                    v: .v5_3,
                    packageKind: .root,
                    targets: [
                        .init(name: "foo", dependencies: []),
                    ]),
            ],
            shouldCreateMultipleTestProducts: true
        )

        let builder = PIFBuilder(graph: graph, parameters: .mock(), diagnostics: diagnostics)
        let pif = builder.construct()

        XCTAssertNoDiagnostics(diagnostics)

        PIFTester(pif) { workspace in
            workspace.checkProject("PACKAGE:/Foo") { project in
                project.checkBuildConfiguration("Debug") { configuration in
                    configuration.checkBuildSettings { settings in
                        XCTAssertEqual(settings[.SPECIALIZATION_SDK_OPTIONS, for: .macOS], ["best"])
                    }
                }
            }
        }
    }
  #endif
}

extension PIFBuilderParameters {
    static func mock(
        shouldCreateDylibForDynamicProducts: Bool = false
    ) -> Self {
        PIFBuilderParameters(
            enableTestDiscovery: false,
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
        )
    }
}
