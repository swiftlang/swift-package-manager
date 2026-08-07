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
import PackageModel
import TSCUtility
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

extension ModulesGraphTests {

    @Suite(
        .tags(
            .TestSize.medium,
            .Feature.Deprecation,
        ),
    )
    struct ModulesGraphProductDeprecationTests {
        // MARK: - Deprecation warning text (per SE-NNNN)

        @Test
        func deprecation_emitsWarningWithRenamedReplacement() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Paper/source.swift",
                    "/Producer/Sources/PaperLegacy/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "PaperLegacy", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Paper",
                                type: .library(.automatic),
                                targets: ["Paper"],
                            ),
                            try ProductDescription(
                                name: "PaperLegacy",
                                type: .library(.automatic),
                                targets: ["PaperLegacy"],
                                deprecation: ProductDeprecation(
                                    message: "PaperLegacy is superseded by Paper.",
                                    replacement: .renamed(to: "Paper"),
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Paper"),
                            TargetDescription(name: "PaperLegacy", dependencies: ["Paper"]),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'PaperLegacy' from package 'producer' is unsupported: PaperLegacy is superseded by Paper. Use 'Paper' instead.",
                    severity: .warning,
                )
            }
        }

        @Test
        func deprecation_emitsWarningWithInPackageReplacement() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/paper-tool-old/main.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "paper-tool-old", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "paper-tool-old",
                                type: .executable,
                                targets: ["paper-tool-old"],
                                deprecation: ProductDeprecation(
                                    message: "Migrate to the standalone paper-tools package.",
                                    replacement: .inPackage(package: "paper-tools", product: "paper-tool"),
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "paper-tool-old", type: .executable),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'paper-tool-old' from package 'producer' is unsupported: Migrate to the standalone paper-tools package. Use 'paper-tool' from package 'paper-tools' instead.",
                    severity: .warning,
                )
            }
        }

        @Test
        func deprecation_emitsWarningWithoutReplacement() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/PaperExperimental/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "PaperExperimental", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "PaperExperimental",
                                type: .library(.automatic),
                                targets: ["PaperExperimental"],
                                deprecation: ProductDeprecation(
                                    message: "PaperExperimental is going away with no replacement.",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "PaperExperimental"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'PaperExperimental' from package 'producer' is unsupported: PaperExperimental is going away with no replacement.",
                    severity: .warning,
                )
            }
        }

        @Test
        func deprecation_emitsBareWarningWhenNoMessageAndNoReplacement() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Bare/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Bare", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Bare",
                                type: .library(.automatic),
                                targets: ["Bare"],
                                deprecation: ProductDeprecation(
                                    message: nil,
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Bare"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Bare' from package 'producer' is unsupported",
                    severity: .warning,
                )
            }
        }

        // MARK: - Non-consumer producer emits no diagnostic

        @Test
        func deprecation_producerAloneEmitsNoDiagnostic() throws {
            let fs = InMemoryFileSystem(
                emptyFiles: "/Producer/Sources/PaperLegacy/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "PaperLegacy",
                                type: .library(.automatic),
                                targets: ["PaperLegacy"],
                                deprecation: ProductDeprecation(
                                    message: "old",
                                    replacement: .renamed(to: "New"),
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "PaperLegacy"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )
            expectNoDiagnostics(observability.diagnostics)
        }

        // MARK: - Escalation via per-target treatAllWarnings(.error)

        @Test
        func deprecation_escalatesToErrorWhenConsumerHasTreatAllWarningsError() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .error,
                )
            }
        }

        // MARK: - Escalation via loadModulesGraph(treatWarningsAsErrors:)

        @Test
        func deprecation_escalatesToErrorWhenTreatWarningsAsErrorsGloballySet() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
                treatWarningsAsErrors: true,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .error,
                )
            }
        }

        // MARK: - Executable and plugin products

        @Test
        func deprecation_appliesToPluginProduct() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Plugins/OldPlugin/plugin.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "OldPlugin", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "OldPlugin",
                                type: .plugin,
                                targets: ["OldPlugin"],
                                deprecation: ProductDeprecation(
                                    message: nil,
                                    replacement: .renamed(to: "NewPlugin"),
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "OldPlugin",
                                type: .plugin,
                                pluginCapability: .buildTool,
                            ),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'OldPlugin' from package 'producer' is unsupported: Use 'NewPlugin' instead.",
                    severity: .warning,
                )
            }
        }

        // MARK: - Extended treat-warnings-as-error coverage

        /// `treatAllWarnings(.warning)` (explicit warning level) is a no-op for escalation:
        /// the deprecation stays a warning.
        @Test
        func deprecation_treatAllWarningsWarningLevelDoesNotEscalate() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatAllWarnings(.warning),
                                    ),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .warning,
                )
            }
        }

        /// C-family `treatAllWarnings(.error)` should not escalate SwiftPM's own
        /// deprecation diagnostic — the flag only applies to the Swift tool.
        @Test
        func deprecation_cTreatAllWarningsDoesNotEscalate() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .c,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                    .init(
                                        tool: .cxx,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .warning,
                )
            }
        }

        /// A per-warning escalation via `treatWarning(name:as:)` does not escalate
        /// the SwiftPM-emitted deprecation diagnostic. Only `treatAllWarnings(.error)`
        /// on the Swift tool (or the global `-warnings-as-errors`) does.
        @Test
        func deprecation_treatSpecificWarningDoesNotEscalate() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatWarning("DeprecatedDeclaration", .error),
                                    ),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .warning,
                )
            }
        }

        /// Per-target escalation is scoped to the target that opted in — a second
        /// consumer target without the setting keeps the plain warning severity.
        @Test
        func deprecation_perTargetEscalationDoesNotAffectOtherTargets() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/ConsumerStrict/source.swift",
                    "/Consumer/Sources/ConsumerLoose/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "ConsumerStrict",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                ],
                            ),
                            TargetDescription(
                                name: "ConsumerLoose",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            // One error (from ConsumerStrict) and one warning (from ConsumerLoose).
            try expectDiagnostics(observability.diagnostics) { result in
                result.checkUnordered(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .error,
                )
                result.checkUnordered(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .warning,
                )
            }
        }

        /// Two deprecated products in the producer, each consumed by a different
        /// consumer target. Only the strict consumer's product diagnostic escalates
        /// to an error; the loose consumer's stays a warning. Each product produces
        /// exactly one diagnostic (from its one consumer).
        @Test
        func deprecation_twoProductsWithPerTargetEscalationScopedIndependently() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/ConsumerStrict/source.swift",
                    "/Consumer/Sources/ConsumerLoose/source.swift",
                    "/Producer/Sources/OldA/source.swift",
                    "/Producer/Sources/OldB/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "ConsumerStrict",
                                dependencies: [
                                    .product(name: "OldA", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                ],
                            ),
                            TargetDescription(
                                name: "ConsumerLoose",
                                dependencies: [
                                    .product(name: "OldB", package: "Producer"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "OldA",
                                type: .library(.automatic),
                                targets: ["OldA"],
                                deprecation: ProductDeprecation(
                                    message: "OldA is gone.",
                                    replacement: .renamed(to: "NewA"),
                                ),
                            ),
                            try ProductDescription(
                                name: "OldB",
                                type: .library(.automatic),
                                targets: ["OldB"],
                                deprecation: ProductDeprecation(
                                    message: "OldB is gone.",
                                    replacement: .renamed(to: "NewB"),
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "OldA"),
                            TargetDescription(name: "OldB"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
            )

            // Each product is consumed by exactly one target, so we expect one
            // diagnostic per product with the severity determined by that target's
            // own escalation setting.
            try expectDiagnostics(observability.diagnostics) { result in
                result.checkUnordered(
                    diagnostic: "product 'OldA' from package 'producer' is unsupported: OldA is gone. Use 'NewA' instead.",
                    severity: .error,
                )
                result.checkUnordered(
                    diagnostic: "product 'OldB' from package 'producer' is unsupported: OldB is gone. Use 'NewB' instead.",
                    severity: .warning,
                )
            }
        }

        /// When both per-target `treatAllWarnings(.error)` and the global
        /// `treatWarningsAsErrors: true` are set, the diagnostic is still an error
        /// (idempotence).
        @Test
        func deprecation_bothPerTargetAndGlobalEscalationCombine() throws {
            let fs = InMemoryFileSystem(
                emptyFiles:
                    "/Consumer/Sources/Consumer/source.swift",
                    "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "Consumer",
                                dependencies: [
                                    .product(name: "Old", package: "Producer"),
                                ],
                                settings: [
                                    .init(
                                        tool: .swift,
                                        kind: .treatAllWarnings(.error),
                                    ),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
                treatWarningsAsErrors: true,
            )

            try expectDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: "product 'Old' from package 'producer' is unsupported: gone",
                    severity: .error,
                )
            }
        }

        /// Global escalation via `treatWarningsAsErrors: true` still emits **no**
        /// diagnostic when no consumer references the deprecated product.
        @Test
        func deprecation_globalEscalationWithNoConsumerEmitsNothing() throws {
            let fs = InMemoryFileSystem(
                emptyFiles: "/Producer/Sources/Old/source.swift",
            )
            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(
                                    message: "gone",
                                    replacement: nil,
                                ),
                            ),
                        ],
                        targets: [
                            TargetDescription(name: "Old"),
                        ],
                    ),
                ],
                observabilityScope: observability.topScope,
                treatWarningsAsErrors: true,
            )
            expectNoDiagnostics(observability.diagnostics)
        }
    }
}

