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

        print(manifest.targets[0].settings)
        print(manifest.targets[1].settings)
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
                print(package.target.buildSettings)
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
                print(package.target.buildSettings)
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

}
