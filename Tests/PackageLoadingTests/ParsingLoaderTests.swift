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
import PackageLoading
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

    func testSupportedPlatformCustom() async throws {
        // SupportedPlatform.custom(_:versionString:) lets packages declare a minimum
        // deployment version for a platform not listed in the named-platform enum.
        // The parser must recognise the .custom("name", versionString: "x.y") form
        // in the Package's platforms: array.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                platforms: [
                    .macOS(.v13),
                    .custom("otheros", versionString: "1.0"),
                    .custom("embedded", versionString: "2.1"),
                ],
                targets: [
                    .target(name: "Foo"),
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

            XCTAssertEqual(manifest.platforms.count, 3)
            XCTAssertEqual(manifest.platforms[0], PlatformDescription(name: "macos", version: "13.0"))
            XCTAssertEqual(manifest.platforms[1], PlatformDescription(name: "otheros", version: "1.0"))
            XCTAssertEqual(manifest.platforms[2], PlatformDescription(name: "embedded", version: "2.1"))
            return manifest
        }
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

    func testDefaultIsolation() async throws {
        // .defaultIsolation takes MainActor.Type? — not a leading-dot enum.
        // The two valid call forms are:
        //   .defaultIsolation(MainActor.self)  → MainActor isolation
        //   .defaultIsolation(nil)             → nonisolated
        // Both forms may also carry an optional platform/configuration condition.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        swiftSettings: [
                            .defaultIsolation(MainActor.self),
                            .defaultIsolation(nil),
                            .defaultIsolation(MainActor.self, .when(platforms: [.macOS])),
                            .defaultIsolation(nil, .when(platforms: [.linux])),
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
            XCTAssertEqual(settings[0], .init(tool: .swift, kind: .defaultIsolation(.MainActor)))
            XCTAssertEqual(settings[1], .init(tool: .swift, kind: .defaultIsolation(.nonisolated)))
            XCTAssertEqual(settings[2], .init(tool: .swift, kind: .defaultIsolation(.MainActor),
                                              condition: .init(platformNames: ["macos"])))
            XCTAssertEqual(settings[3], .init(tool: .swift, kind: .defaultIsolation(.nonisolated),
                                              condition: .init(platformNames: ["linux"])))
            return manifest
        }
    }

    func testStrictMemorySafetyWithCondition() async throws {
        // .strictMemorySafety() is unusual among build settings: it has no required value
        // argument — its sole argument is the optional condition. The condition-parsing
        // logic must not skip it when scanning for the condition.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        swiftSettings: [
                            .strictMemorySafety(),
                            .strictMemorySafety(.when(platforms: [.linux])),
                            .strictMemorySafety(.when(platforms: [.macOS, .linux])),
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
            XCTAssertEqual(settings[0], .init(tool: .swift, kind: .strictMemorySafety))
            XCTAssertEqual(settings[1], .init(tool: .swift, kind: .strictMemorySafety,
                                              condition: .init(platformNames: ["linux"])))
            XCTAssertEqual(settings[2], .init(tool: .swift, kind: .strictMemorySafety,
                                              condition: .init(platformNames: ["macos", "linux"])))
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
        guard let parsingManifestLoader else {
            XCTSkip("Host compiler doesn't support the static build configurations")
            return
        }

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
            customManifestLoader: parsingManifestLoader,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets.count, 1)
        XCTAssertEqual(manifest.targets[0].name, "MyTarget")
    }

    func testUnknownTargetArgumentRecordsLimitation() async throws {
        guard let parsingManifestLoader else {
            XCTSkip("Host compiler doesn't support the static build configurations")
            return
        }

        // An unknown target argument must cause the parsing loader to record a
        // limitation. Before this fix, the argument was silently ignored, which
        // could produce a wrong manifest with no indication that something was
        // wrong. This manifest is syntactically valid Swift (the parser can read
        // it) but will not compile; we only need the parsing loader to see it.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        unknownFutureArgument: "value"
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        do {
            _ = try await loadAndValidateManifest(
                content,
                customManifestLoader: parsingManifestLoader,
                observabilityScope: observability.topScope
            )
            XCTFail("Expected a limitations error for the unknown target argument")
        } catch let error as ManifestParserError {
            guard case .limitations = error else {
                XCTFail("Expected .limitations error, got: \(error)")
                return
            }
            // The unknown argument was correctly reported as a limitation.
        }
    }
    
    // MARK: - Global Variable Tests
    
    func testGlobalVariableStringInPackageName() async throws {
        let content = """
            import PackageDescription
            let packageName = "MyAwesomePackage"
            let package = Package(
                name: packageName,
                targets: [
                    .target(name: "Foo"),
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

            XCTAssertEqual(manifest.displayName, "MyAwesomePackage")
            return manifest
        }
    }
    
    func testGlobalVariableWithTypeAnnotation() async throws {
        let content = """
            import PackageDescription
            let packageName: String = "TypedPackage"
            let package = Package(
                name: packageName,
                targets: [
                    .target(name: "Core"),
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

            XCTAssertEqual(manifest.displayName, "TypedPackage")
            return manifest
        }
    }
    
    func testGlobalVariableStringArrayInTargetExcludes() async throws {
        let content = """
            import PackageDescription
            let excludedFiles = ["Tests", "Documentation"]
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        exclude: excludedFiles
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

            XCTAssertEqual(manifest.targets[0].exclude, ["Tests", "Documentation"])
            return manifest
        }
    }
    
    func testGlobalVariableArrayConcatenation() async throws {
        let content = """
            import PackageDescription
            let commonSources = ["Common.swift", "Utilities.swift"]
            let platformSources = ["Platform.swift"]
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        sources: commonSources + platformSources
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

            XCTAssertEqual(manifest.targets[0].sources, ["Common.swift", "Utilities.swift", "Platform.swift"])
            return manifest
        }
    }
    
    func testGlobalVariableMultipleArrayConcatenation() async throws {
        let content = """
            import PackageDescription
            let coreFiles = ["Core.swift"]
            let utilFiles = ["Util.swift"]
            let platformFiles = ["Platform.swift"]
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        sources: coreFiles + utilFiles + platformFiles
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

            XCTAssertEqual(manifest.targets[0].sources, ["Core.swift", "Util.swift", "Platform.swift"])
            return manifest
        }
    }
    
    func testGlobalVariableMixedArrayConcatenation() async throws {
        let content = """
            import PackageDescription
            let baseExcludes = ["Tests", "Docs"]
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        exclude: baseExcludes + ["Build", "Cache"]
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

            XCTAssertEqual(manifest.targets[0].exclude, ["Tests", "Docs", "Build", "Cache"])
            return manifest
        }
    }
    
    func testGlobalVariableInTargetDependencies() async throws {
        let content = """
            import PackageDescription
            var metricsDep: Target.Dependency = "Metrics"
            let sharedDeps: [Target.Dependency] = ["Logging"] + [metricsDep]
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        dependencies: sharedDeps
                    ),
                    .target(name: "Logging"),
                    .target(name: "Metrics"),
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

            XCTAssertEqual(manifest.targets[0].dependencies.count, 2)
            return manifest
        }
    }
    
    func testGlobalVariableInProductTargets() async throws {
        let content = """
            import PackageDescription
            let libraryTargets = ["Core", "Utilities"]
            let coreTarget: Target = .target(name: "Core")
            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Foo", targets: libraryTargets),
                ],
                targets: [
                    coreTarget,
                    .target(name: "Utilities"),
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

            XCTAssertEqual(manifest.products[0].targets, ["Core", "Utilities"])
            return manifest
        }
    }
    
    func testGlobalVariableWithContextExpression() async throws {
        guard let parsingManifestLoader else {
            XCTSkip("Host compiler doesn't support the static build configurations")
            return
        }

        let content = """
            import PackageDescription
            let targetName = Context.environment["SWIFT_TARGET_NAME"] ?? "DefaultTarget"
            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: targetName),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            customManifestLoader: parsingManifestLoader,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets[0].name, "MyTarget")
    }
    
    func testGlobalVariableStringInterpolation() async throws {
        let content = """
            import PackageDescription
            let version = "1.0.0"
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        cSettings: [
                            .define("VERSION", to: "\\(version)")
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
            XCTAssertEqual(settings[0], .init(tool: .c, kind: .define("VERSION=1.0.0")))
            return manifest
        }
    }
    
    func testGlobalVariableInBuildSettingValues() async throws {
        let content = """
            import PackageDescription
            let headerPath = "include/mylib"
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        cSettings: [
                            .headerSearchPath(headerPath)
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
            XCTAssertEqual(settings[0], .init(tool: .c, kind: .headerSearchPath("include/mylib")))
            return manifest
        }
    }
    
    func testGlobalVariableInTraits() async throws {
        let content = """
            import PackageDescription
            let enabledTraits: Set<String> = ["Feature1", "Feature2"]
            let package = Package(
                name: "Foo",
                traits: [
                  .trait(name: "Feature1"),
                  .trait(name: "Feature2"),
                  .trait(name: "AllFeatures", enabledTraits: enabledTraits)
                ],
                targets: [
                    .target(name: "Foo"),
                ],
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

            // The manifest should contain the traits we explicitly declared
            let allFeaturesTrait = manifest.traits.first { $0.name == "AllFeatures" }
            XCTAssertNotNil(allFeaturesTrait)
            XCTAssertEqual(allFeaturesTrait?.enabledTraits.sorted(), ["Feature1", "Feature2"])
            return manifest
        }
    }
    
    func testGlobalVariableNestedReferences() async throws {
        let content = """
            import PackageDescription
            let baseName = "MyLibrary"
            let fullName = baseName
            let package = Package(
                name: fullName,
                targets: [
                    .target(name: "Foo"),
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

            XCTAssertEqual(manifest.displayName, "MyLibrary")
            return manifest
        }
    }
    
    func testMultipleGlobalVariablesInSingleManifest() async throws {
        let content = """
            import PackageDescription
            let packageName: String = "ComplexPackage"
            let mainTarget = "Core"
            let testTarget = "CoreTests"
            let excludedDirs: [String] = ["Docs", "Examples"]
            let commonDeps: [Target.Dependency] = ["Logging"]
            
            let package = Package(
                name: packageName,
                targets: [
                    .target(
                        name: mainTarget,
                        dependencies: commonDeps,
                        exclude: excludedDirs
                    ),
                    .testTarget(
                        name: testTarget,
                        dependencies: [.target(name: mainTarget)]
                    ),
                    .target(name: "Logging"),
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

            XCTAssertEqual(manifest.displayName, "ComplexPackage")
            XCTAssertEqual(manifest.targets[0].name, "Core")
            XCTAssertEqual(manifest.targets[0].exclude, ["Docs", "Examples"])
            XCTAssertEqual(manifest.targets[0].dependencies.count, 1)
            XCTAssertEqual(manifest.targets[1].name, "CoreTests")
            return manifest
        }
    }

    func testCanImportRecordsLimitation() async throws {
        guard let parsingManifestLoader else {
            XCTSkip("Host compiler doesn't support the static build configurations")
            return
        }

        // canImport() cannot be evaluated by the static build configuration,
        // so the parsing loader must record a limitation and fall back to the
        // executing loader rather than silently picking the wrong #if branch.
        let content = """
            import PackageDescription
            #if canImport(Darwin)
            let excludedFiles: [String] = []
            #else
            let excludedFiles = ["PrivacyInfo.xcprivacy"]
            #endif
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        exclude: excludedFiles
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        do {
            _ = try await loadAndValidateManifest(
                content,
                customManifestLoader: parsingManifestLoader,
                observabilityScope: observability.topScope
            )
            XCTFail("Expected a limitations error for canImport")
        } catch let error as ManifestParserError {
            guard case .limitations = error else {
                XCTFail("Expected .limitations error, got: \(error)")
                return
            }
            // The canImport check was correctly reported as a limitation.
        }
    }

    func testTernaryInDefineValueRecordsLimitation() async throws {
        guard let parsingManifestLoader else {
            XCTSkip("Host compiler doesn't support the static build configurations")
            return
        }

        // A ternary expression in the 'to:' argument of .define() cannot be
        // evaluated by the parsing loader. It must record a limitation rather
        // than silently dropping the value.
        let content = """
            import PackageDescription
            let useNeon = true
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        cSettings: [
                            .define("OPT", to: useNeon ? "2" : "0")
                        ]
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        do {
            _ = try await loadAndValidateManifest(
                content,
                customManifestLoader: parsingManifestLoader,
                observabilityScope: observability.topScope
            )
            XCTFail("Expected a limitations error for ternary in define value")
        } catch let error as ManifestParserError {
            guard case .limitations = error else {
                XCTFail("Expected .limitations error, got: \(error)")
                return
            }
            // The ternary expression was correctly reported as a limitation.
        }
    }

    func testSwiftVersionCheckMatchesToolsVersion() async throws {
        // The #if swift(...) condition should use the language mode implied
        // by the manifest's tools version, not the compiler's default. With
        // tools version >= 6.0 the language mode is Swift 6, so
        // #if swift(>=6) should be true and #if swift(<6) should be false.
        let content = """
            import PackageDescription
            #if swift(<6)
            let swiftSettings: [SwiftSetting] = [
                .enableExperimentalFeature("ExistentialAny"),
            ]
            #else
            let swiftSettings: [SwiftSetting] = [
                .enableUpcomingFeature("ExistentialAny"),
            ]
            #endif
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        swiftSettings: swiftSettings
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
            XCTAssertEqual(settings.count, 1)
            // With Swift 6 language mode, the #else branch should be taken
            XCTAssertEqual(settings[0], .init(tool: .swift, kind: .enableUpcomingFeature("ExistentialAny")))
            return manifest
        }
    }

    func testLanguageModeAdjustment() async throws {
        let content = """
            // swift-tools-version:5.5
            import PackageDescription

            #if swift(>=5.6)
            let package = Package(
                name: "UseDocC",
                products: [
                    .library(name: "A", targets: ["A"]),
                ],
                targets: [
                    // Product Targets
                    .target(
                        name: "A"
                    ),
                ]
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

            return manifest
        }
    }

    func testPackageAppend() async throws {
        let content = """
            // swift-tools-version:5.5
            import PackageDescription

            let package = Package(
                name: "MyPackage",
                products: [
                    .library(name: "A", targets: ["A"]),
                ],
                dependencies: [
                    .package(url: "https://github.com/vapor/vapor", from: "4.0.0"),
                ],
                targets: [
                    // Product Targets
                    .target(
                        name: "A",
                        dependencies: [
                            .product(name: "Vapor", package: "vapor"),
                        ]
                    ),
                ]
            )

            package.dependencies.append(
                .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
            )
            package.targets.append(contentsOf: [
                .target(name: "B"),
                .target(name: "C"),
            ])
            package.products += [
                .library(name: "B", targets: ["B"]),
            ]
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

            return manifest
        }
    }
}
