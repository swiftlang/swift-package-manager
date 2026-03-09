//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SourceControl
import _InternalTestSupport
import XCTest

final class ParsingLoaderTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_2
    }

    override var environment: [String : String]? {
        ["SWIFT_TARGET_NAME": "MyTarget"]
    }

    func testPoundIf() async throws {
        let content =  """
            import PackageDescription
            #if os(macOS)
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "MacTarget")
                ],
            )
            #else
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "OtherTarget")
                ],
            )
            #endif
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.targets.count, 1)
            #if os(macOS)
            XCTAssertEqual(manifest.targets[0].name, "MacTarget")
            #else
            XCTAssertEqual(manifest.targets[0].name, "OtherTarget")
            #endif
            return manifest
        }
    }

    func testPoundIfErrors() async throws {
        let content =  """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "MyTarget")
                ],
            )

            #if compiler(>=5.3) && BAD_CODE
            this is bad
            #endif
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.targets.count, 1)
            XCTAssertEqual(manifest.targets[0].name, "MyTarget")
            return manifest
        }
    }

    func testBuildSettingDefineWithEscapedQuotes() async throws {
        // C preprocessor defines can have values with embedded quotes, e.g.:
        //   .define("VERSION", to: "\"1.0.0\"")
        // The value "\"1.0.0\"" is the Swift string literal for "1.0.0" (with
        // actual double quotes). The parsing loader must interpret the escape
        // sequences in the string literal rather than returning the raw source text.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        cSettings: [
                            .define("PLAIN"),
                            .define("WITH_VALUE", to: "42"),
                            .define("QUOTED_VALUE", to: "\\"hello\\""),
                            .define("QUOTED_WITH_SPACES", to: "\\"hello world\\""),
                        ]
                    ),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let settings = manifest.targets[0].settings
            XCTAssertEqual(settings[0], .init(tool: .c, kind: .define("PLAIN")))
            XCTAssertEqual(settings[1], .init(tool: .c, kind: .define("WITH_VALUE=42")))
            XCTAssertEqual(settings[2], .init(tool: .c, kind: .define("QUOTED_VALUE=\"hello\"")))
            XCTAssertEqual(settings[3], .init(tool: .c, kind: .define("QUOTED_WITH_SPACES=\"hello world\"")))
            return manifest
        }
    }

    func testBuildSettingCustomPlatformCondition() async throws {
        // Platform conditions can include custom platform names via .custom("name"),
        // e.g. .linkedLibrary("pthread", .when(platforms: [.linux, .custom("freebsd")])).
        // The parsing loader must recognise .custom("name") and include its name in the
        // condition, rather than silently dropping it.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        linkerSettings: [
                            .linkedLibrary("dl", .when(platforms: [.linux])),
                            .linkedLibrary("pthread", .when(platforms: [.linux, .custom("freebsd")])),
                            .linkedLibrary("unconditional"),
                        ]
                    ),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let settings = manifest.targets[0].settings
            XCTAssertEqual(settings[0], .init(tool: .linker, kind: .linkedLibrary("dl"),
                                              condition: .init(platformNames: ["linux"])))
            XCTAssertEqual(settings[1], .init(tool: .linker, kind: .linkedLibrary("pthread"),
                                              condition: .init(platformNames: ["linux", "freebsd"])))
            XCTAssertEqual(settings[2], .init(tool: .linker, kind: .linkedLibrary("unconditional")))
            return manifest
        }
    }

    func testEnvironment() async throws {
        let content =  """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: Context.environment["SWIFT_TARGET_NAME"] ?? "OtherTarget")
                ],
            )
            """

        // NOTE: non-parsing manifest loader doesn't support testing the
        // environment.
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            customManifestLoader: self.parsingManifestLoader,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets.count, 1)
        XCTAssertEqual(manifest.targets[0].name, "MyTarget")
    }
}
