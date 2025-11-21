//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

@testable import SwiftBuildSupport
import SPMBuildCore


import var TSCBasic.stderrStream
import Basics
import Workspace
import PackageModel
import PackageGraph
import PackageLoading

@testable import SwiftBuild
import SWBBuildService

import _InternalTestSupport

func withInstantiatedSwiftBuildSystem(
    fromFixture fixtureName: String,
    buildParameters: BuildParameters? = nil,
    logLevel: Basics.Diagnostic.Severity = .warning,
    do doIt: @escaping (SwiftBuildSupport.SwiftBuildSystem, SWBBuildServiceSession, TestingObservability, BuildParameters,) async throws -> (),
) async throws {
    let fileSystem = Basics.localFileSystem

    try await fixture(name: fixtureName) { fixturePath  in
        try await withTemporaryDirectory  { tmpDir in
            let buildParameters = if let buildParameters {
                buildParameters
            } else {
                mockBuildParameters(destination: .host)
            }
            let observabilitySystem: TestingObservability = ObservabilitySystem.makeForTesting()
            let toolchain = try UserToolchain.default
            let workspace = try Workspace(
                fileSystem: fileSystem,
                forRootPackage: fixturePath,
                customManifestLoader: ManifestLoader(toolchain: toolchain),
            )
            let rootInput = PackageGraphRootInput(packages: [fixturePath], dependencies: [])
            let graphLoader = {
                try await workspace.loadPackageGraph(
                    rootInput: rootInput,
                    observabilityScope: observabilitySystem.topScope
                )
            }

            let pluginScriptRunner = try DefaultPluginScriptRunner(
                fileSystem: fileSystem,
                cacheDir: tmpDir.appending("plugin-script-cache"),
                toolchain: UserToolchain.default,
            )

            let swBuild = try SwiftBuildSystem(
                buildParameters: buildParameters,
                packageGraphLoader: graphLoader,
                packageManagerResourcesDirectory: nil,
                additionalFileRules: [],
                outputStream: TSCBasic.stderrStream,
                logLevel: logLevel,
                fileSystem: fileSystem,
                observabilityScope: observabilitySystem.topScope,
                pluginConfiguration: PluginConfiguration(
                    scriptRunner: pluginScriptRunner,
                    workDirectory: AbsolutePath("/tmp/plugin-script-working-dir"),
                    disableSandbox: true,
                ),
                delegate: nil,
            )

            try await SwiftBuildSupport.withService(
                connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint),
            ) { service in

                let result = await service.createSession(
                    name: "session",
                    cachePath: nil,
                    inferiorProductsPath: nil,
                    environment: nil,
                )

                let buildSession: SWBBuildServiceSession
                switch result {
                case (.success(let session), _):
                    buildSession = session
                case (.failure(let error), _):
                    throw StringError("\(error)")
                    // throw SessionFailedError(error: error, diagnostics: diagnostics)
                }

                do {
                    try await doIt(swBuild, buildSession, observabilitySystem, buildParameters)
                    try await buildSession.close()
                } catch {
                    try await buildSession.close()
                    throw error
                }
            }
        }
    }
}

extension PackageModel.Sanitizer {
    var hasSwiftBuildSupport: Bool {
        switch self {
            case .address, .thread, .undefined: true
            case .fuzzer, .scudo: false
        }
    }

    var swiftBuildSettingName: String? {
        switch self {
            case .address: "ENABLE_ADDRESS_SANITIZER"
            case .thread: "ENABLE_THREAD_SANITIZER"
            case .undefined: "ENABLE_UNDEFINED_BEHAVIOR_SANITIZER"
            case .fuzzer, .scudo: nil
        }

    }
}

@Suite(
    .tags(
        .TestSize.medium,
    ),
)
struct SwiftBuildSystemTests {

    @Suite(
        .tags(
            .FunctionalArea.Sanitizer,
        )
    )
    struct SanitizerTests {

        @Test(
            arguments: PackageModel.Sanitizer.allCases.filter { $0.hasSwiftBuildSupport },
        )
        func sanitizersSettingSetCorrectBuildRequest(
            sanitizer: Sanitizer,
        ) async throws {
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    sanitizers: [sanitizer],
                ),
            ) { swiftBuild, session, observabilityScope, buildParameters in
                let buildSettings: SWBBuildParameters = try await swiftBuild.makeBuildParameters(
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)

                let swbSettingName = try #require(sanitizer.swiftBuildSettingName)
                #expect(synthesizedArgs.table[swbSettingName] == "YES")
            }

        }

        @Test(
            arguments: PackageModel.Sanitizer.allCases.filter { !$0.hasSwiftBuildSupport },
        )
        func unsupportedSanitizersRaisesError(
            sanitizer: Sanitizer,
        ) async throws {
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    sanitizers: [sanitizer],
                ),
            ) { swiftBuild, session, observabilityScope, buildParameters in
                await #expect(throws: (any Error).self) {
                    try await swiftBuild.makeBuildParameters(
                        session: session,
                        symbolGraphOptions: nil,
                        setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
                    )
                }
            }
        }
    }

    @Suite(
        .tags(
            .FunctionalArea.LinkSwiftStaticStdlib,
        ),
    )
    struct SwiftStaticStdlibSettingTests {
        @Test
        func makingBuildParametersRaisesAWarningWhenRunOnDarwin() async throws {
            // GIVEN we have a Darwin triple
            let triple = try Triple("x86_64-apple-macosx")
            // AND we want to statically link Swift sdtlib
            let shouldLinkStaticSwiftStdlib = true
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
                    triple: triple,
                ),
            ) { swiftBuild, session, observabilityScope, buildParameters in
                // WHEN we make the build parameter
                let _: SWBBuildParameters = try await swiftBuild.makeBuildParameters(
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
                )

                // THEN we expect a warning to be emitted
                let warnings = observabilityScope.diagnostics.filter {
                    $0.severity == .warning
                }
                #expect(warnings.count == 1)

                let diagnostic = try #require(warnings.first)
                // AND we expect the diagnostic message, severity and description to be as expected
                #expect(diagnostic.message == Basics.Diagnostic.swiftBackDeployWarning.message)
                #expect(diagnostic.severity == Basics.Diagnostic.swiftBackDeployWarning.severity)
                #expect(diagnostic.description == Basics.Diagnostic.swiftBackDeployWarning.description)
            }
        }

        @Test(
            arguments: [
                (shouldLinkStaticSwiftStdlib: true, expectedValue: "YES"),
                (shouldLinkStaticSwiftStdlib: false, expectedValue: "NO"),
            ]
        )
        func swiftStaticStdLibSettingIsSetCorrectly(
            shouldLinkStaticSwiftStdlib: Bool,
            expectedValue: String
        ) async throws {
            // GIVEN we have a non-darwin triple AND we want statically link Swift sdtlib or not
            let nonDarwinTriple = try Triple("i686-pc-windows-cygnus")
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
                    triple: nonDarwinTriple,
                ),
            ) { swiftBuild, session, observabilityScope, buildParameters in
                // WHEN we make the build parameter
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
                )

                // THEN we don't expect any warnings to be emitted
                let warnings = observabilityScope.diagnostics.filter {
                    $0.severity == .warning
                }
                #expect(warnings.isEmpty)

                // AND we expect the build setting to be set correctly
                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
                #expect(synthesizedArgs.table["SWIFT_FORCE_STATIC_LINK_STDLIB"] == expectedValue)
            }
        }
    }

    @Test(
        arguments: BuildParameters.IndexStoreMode.allCases,
        // arguments: [BuildParameters.IndexStoreMode.on],
    )
    func indexModeSettingSetCorrectBuildRequest(
        indexStoreSettingUT: BuildParameters.IndexStoreMode
    ) async throws {
        try await withInstantiatedSwiftBuildSystem(
            fromFixture: "PIFBuilder/Simple",
            buildParameters: mockBuildParameters(
                destination: .host,
                indexStoreMode: indexStoreSettingUT,
            ),
        ) { swiftBuild, session, observabilityScope, buildParameters in
            let buildSettings = try await swiftBuild.makeBuildParameters(
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
            )

            let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
            let expectedSettingValue: String? = switch indexStoreSettingUT {
                case .on: "YES"
                case .off: "NO"
                case .auto: nil
            }
            let expectedPathValue: String? = switch indexStoreSettingUT {
                case .on: buildParameters.indexStore.pathString
                case .off: nil
                case .auto: nil
            }

            #expect(synthesizedArgs.table["SWIFT_INDEX_STORE_ENABLE"] == expectedSettingValue)
            #expect(synthesizedArgs.table["CLANG_INDEX_STORE_ENABLE"] == expectedSettingValue)
            #expect(synthesizedArgs.table["SWIFT_INDEX_STORE_PATH"] == expectedPathValue)
            #expect(synthesizedArgs.table["CLANG_INDEX_STORE_PATH"] == expectedPathValue)
        }
    }

    @Test(
        .serialized,
        arguments: [
            (linkerDeadStripUT: true, expectedValue: "YES"),
            (linkerDeadStripUT: false, expectedValue: nil),
        ]
    )
    func validateDeadStripSetting(
        linkerDeadStripUT: Bool,
        expectedValue: String?
    ) async throws {
        try await withInstantiatedSwiftBuildSystem(
            fromFixture: "PIFBuilder/Simple",
            buildParameters: mockBuildParameters(
                destination: .host,
                linkerDeadStrip: linkerDeadStripUT,
            ),
        ) { swiftBuild, session, observabilityScope, buildParameters in

            let buildSettings = try await swiftBuild.makeBuildParameters(
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false, // Set this to false as SwiftBuild checks the toolchain path
            )

            let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
            let actual = synthesizedArgs.table["DEAD_CODE_STRIPPING"]
            #expect(
                actual == expectedValue,
                "dead strip: \(linkerDeadStripUT) >>> Actual: '\(actual)' expected: '\(String(describing: expectedValue))'",
            )
       }
    }
}
