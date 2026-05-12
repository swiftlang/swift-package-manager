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
                    )
                ],
                defaultSwiftSettings: [
                    .swiftLanguageMode(.v5),
                ],
                defaultCSettings: [
                    .headerSearchPath("foo"),
                ],
                defaultCXXSettings: [
                    .headerSearchPath("foo"),
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
            .init(tool: .swift, kind: .swiftLanguageMode(.v5))
        ]

        #expect(manifest.defaultSettings == expected)
    }

    @Test
    func defaultIsolationResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .defaultIsolation(.MainActor))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A"
                ),
                try TargetDescription(
                    name: "B",
                    settings: []
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .defaultIsolation(.nonisolated)),
                    ]
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
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-default-isolation"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("MainActor"))
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
        }
    }

    @Test
    func headerSearchPathResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
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
                    publicHeadersPath: "."
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .c, kind: .headerSearchPath("bar")),
                    ]
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
                #expect(macosDebugScope.evaluate(.HEADER_SEARCH_PATHS).contains("foo"))
            }

            try package.checkModule("C") { package in
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
    func defineResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .c, kind: .define("A=B"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: "."
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .c, kind: .define("A=C")),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS).contains("A=B"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS).contains("A=B"))
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS).contains("A=B") == false)
                #expect(macosDebugScope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS).contains("A=C"))
            }
        }
    }

    @Test
    func linkedLibraryResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
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
                    publicHeadersPath: "."
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .linker, kind: .linkedLibrary("yourlib")),
                    ]
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
                #expect(macosDebugScope.evaluate(.LINK_LIBRARIES).contains("mylib"))
            }

            try package.checkModule("C") { package in
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
    func linkedFrameworkResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.c",
            "/Sources/B/b.c",
            "/Sources/C/c.c",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .linker, kind: .linkedFramework("myframework"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                    publicHeadersPath: "."
                ),
                try TargetDescription(
                    name: "B",
                    publicHeadersPath: ".",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    publicHeadersPath: ".",
                    settings: [
                        .init(tool: .linker, kind: .linkedFramework("yourframework")),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_FRAMEWORKS).contains("myframework"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_FRAMEWORKS).contains("myframework"))
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.LINK_FRAMEWORKS).contains("myframework"))
                #expect(macosDebugScope.evaluate(.LINK_FRAMEWORKS).contains("yourframework"))
            }
        }
    }

    @Test
    func interoperabilityModeResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .interoperabilityMode(.C))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .interoperabilityMode(.Cxx)),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-cxx-interoperability-mode=default") == false)
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-cxx-interoperability-mode=default") == false)
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-cxx-interoperability-mode=default"))
            }
        }
    }

    @Test
    func enableUpcomingFeatureResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .enableUpcomingFeature("foo"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .enableUpcomingFeature("bar")),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-upcoming-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-upcoming-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-upcoming-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("bar"))
            }
        }
    }

    @Test
    func enableExperimentalFeatureResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .enableExperimentalFeature("foo"))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .enableExperimentalFeature("bar")),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-experimental-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-experimental-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-enable-experimental-feature"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("bar"))
            }
        }
    }

    @Test
    func strictMemorySafetyResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .strictMemorySafety)
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-strict-memory-safety"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("-strict-memory-safety"))
            }
        }
    }

    @Test
    func unsafeFlagsResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Sources/A/a.swift",
            "/Sources/B/b.swift",
            "/Sources/C/c.swift",
        )

        let manifest = Manifest.createRootManifest(
            displayName: "pkg",
            defaultSettings: [
                .init(tool: .swift, kind: .unsafeFlags(["foo"]))
            ],
            toolsVersion: .v6_2,
            targets: [
                try TargetDescription(
                    name: "A",
                ),
                try TargetDescription(
                    name: "B",
                    settings: [],
                ),
                try TargetDescription(
                    name: "C",
                    settings: [
                        .init(tool: .swift, kind: .unsafeFlags(["bar"])),
                    ]
                ),
            ]
        )

        try PackageBuilderTester(manifest, in: fs) { package, _ in
            try package.checkModule("A") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("B") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo"))
            }

            try package.checkModule("C") { package in
                let macosDebugScope = BuildSettings.Scope(
                    package.target.buildSettings,
                    environment: BuildEnvironment(platform: .macOS, configuration: .debug)
                )
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("foo") == false)
                #expect(macosDebugScope.evaluate(.OTHER_SWIFT_FLAGS).contains("bar"))
            }
        }
    }

}
