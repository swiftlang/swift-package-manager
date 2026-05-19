//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import Testing

struct DefaultLoadingTests {
    @Test(
        .tags(
            Tag.Feature.TargetSettings
        )
    )
    func defaultSettingsManifestLoading() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [],
                targets: [
                    .target(
                        name: "Foo",
                    ),
                    .target(
                        name: "Bar",
                        swiftSettings: [
                            .swiftLanguageMode(.v6),
                        ]
                    ),
                    .target(
                        name: "Baz",
                        cSettings: [
                            .inherited()
                        ],
                        cxxSettings: [
                            .inherited()
                        ],
                        swiftSettings: [
                            .inherited()
                        ],
                        linkerSettings: [
                            .inherited()
                        ],
                    ),
                ],
                defaultSwiftSettings: [
                    .swiftLanguageMode(.v5),
                ],
                defaultCSettings: [
                    .headerSearchPath("foo"),
                ],
                defaultCXXSettings: [
                    .headerSearchPath("bar"),
                ],
                defaultLinkerSettings: [
                    .linkedLibrary("mylib"),
                ],
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await PackageDescriptionLoadingTests
            .loadAndValidateManifest(
                content,
                toolsVersion: .v6_2,
                packageKind: .fileSystem(.root),
                manifestLoader: ManifestLoader(
                    toolchain: try! UserToolchain.default
                ),
                observabilityScope: observability.topScope
            )
        try expectDiagnostics(validationDiagnostics) { results in
            results.checkIsEmpty()
        }
        try expectDiagnostics(observability.diagnostics) { results in
            results.checkIsEmpty()
        }

        let expected: [TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, kind: .swiftLanguageMode(.v5)),
            .init(tool: .c, kind: .headerSearchPath("foo")),
            .init(tool: .cxx, kind: .headerSearchPath("bar")),
            .init(tool: .linker, kind: .linkedLibrary("mylib")),
        ]

        #expect(manifest.defaultSettings == expected)
    }

    @Test
    func swiftToolResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
            "/Sources/D/d.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .defaultIsolation(.MainActor))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    explicitSettings: .none
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                    explicitSettings: .all
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .defaultIsolation(.nonisolated))
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
                try TargetDescription(
                    name: "D",
                    settings: [
                        .init(tool: .swift, kind: .inherited),
                        .init(tool: .swift, kind: .defaultIsolation(.nonisolated))
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-default-isolation"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("MainActor"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-default-isolation") == false)
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("MainActor") == false)
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-default-isolation"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("nonisolated"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("MainActor") == false)
            }

            try package.checkModule("D") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-default-isolation"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("nonisolated"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("MainActor"))
            }
        }
    }

    @Test
    func cToolResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
            "/Sources/D/d.c",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .c, kind: .headerSearchPath("foo"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: ".",
                    explicitSettings: .none
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                    explicitSettings: .all
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .c, kind: .headerSearchPath("bar")),
                    ],
                    explicitSettings: .init(swift: false, c: true, cxx: false, linker: false)
                ),
                try TargetDescription(
                    name: "D",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .c, kind: .inherited),
                        .init(tool: .c, kind: .headerSearchPath("bar")),
                    ],
                    explicitSettings: .init(swift: false, c: true, cxx: false, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo") == false)
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo") == false)
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("bar"))
            }

            try package.checkModule("D") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo"))
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("bar"))
            }
        }
    }

    @Test
    func cxxToolResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
            "/Sources/D/d.c",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .cxx, kind: .headerSearchPath("foo"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: ".",
                    explicitSettings: .none
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                    explicitSettings: .all
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .cxx, kind: .headerSearchPath("bar")),
                    ],
                    explicitSettings: .init(swift: false, c: false, cxx: true, linker: false)
                ),
                try TargetDescription(
                    name: "D",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .cxx, kind: .inherited),
                        .init(tool: .cxx, kind: .headerSearchPath("bar")),
                    ],
                    explicitSettings: .init(swift: false, c: false, cxx: true, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo") == false)
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo") == false)
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("bar"))
            }

            try package.checkModule("D") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo"))
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("bar"))
            }
        }
    }

    @Test
    func linkerToolResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
            "/Sources/D/d.c",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .linker, kind: .linkedLibrary("mylib"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: ".",
                    explicitSettings: .none
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                    explicitSettings: .all
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .linker, kind: .linkedLibrary("yourlib")),
                    ],
                    explicitSettings: .init(swift: false, c: false, cxx: false, linker: true)
                ),
                try TargetDescription(
                    name: "D",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .linker, kind: .inherited),
                        .init(tool: .linker, kind: .linkedLibrary("yourlib")),
                    ],
                    explicitSettings: .init(swift: false, c: false, cxx: false, linker: true)
                ),

            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("mylib"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("mylib") == false)
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("mylib") == false)
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("yourlib"))
            }

            try package.checkModule("D") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("mylib"))
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("yourlib"))
            }
        }
    }

    @Test
    func defaultUnsafeFlagsAreRejected() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
            "/Sources/D/d.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .unsafeFlags(["anything"]))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: ".",
                    explicitSettings: .none
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                    explicitSettings: .all
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .swift, kind: .unsafeFlags(["another"]))
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
                try TargetDescription(
                    name: "D",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .swift, kind: .inherited),
                        .init(tool: .swift, kind: .unsafeFlags(["another"]))
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            diagnostics.check(
                diagnostic: "configuration of package '\(package.packageIdentity)' is invalid; default settings cannot contain unsafe flags",
                severity: .error
            )
        }
    }

    @Test
    func emptyDefaultsAreAccepted() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    settings: [
                        .init(tool: .swift, kind: .inherited)
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            try package.checkModule("A") { module in
            }
        }
    }

    @Test
    func inheritanceWithoutSwiftDefaultsIsRejected() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    settings: [
                        .init(tool: .swift, kind: .inherited)
                    ],
                    explicitSettings: .init(swift: true, c: false, cxx: false, linker: false)
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, diagnostics in
            diagnostics.check(
                diagnostic: "configuration of package '\(package.packageIdentity)' is invalid; inheritance cannot be used without default values",
                severity: .error
            )
        }
    }

}
