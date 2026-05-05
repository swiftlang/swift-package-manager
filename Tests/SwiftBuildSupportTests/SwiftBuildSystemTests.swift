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
    do doIt: @escaping (SwiftBuildSupport.SwiftBuildSystem, SWBBuildService, SWBBuildServiceSession, TestingObservability, BuildParameters, ) async throws -> (),
) async throws {
    let fileSystem = Basics.localFileSystem

    try await fixture(name: fixtureName) { fixturePath in
        try await withTemporaryDirectory { tmpDir in
            let buildParameters =
                if let buildParameters {
                    buildParameters
                } else {
                    mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
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
                hostBuildParameters: buildParameters,
                packageGraphLoader: graphLoader,
                packageManagerResourcesDirectory: nil,
                additionalFileRules: [],
                outputStream: TSCBasic.stderrStream,
                logLevel: logLevel,
                fileSystem: fileSystem,
                observabilityScope: observabilitySystem.topScope,
                pluginConfiguration: PluginConfiguration(
                    scriptRunner: pluginScriptRunner,
                    workDirectory: tmpDir.appending("plugin-script-working-dir"),
                    disableSandbox: true,
                ),
                delegate: nil,
                scratchDirectory: tmpDir.appending("scratchDirectory"),
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
                    try await doIt(swBuild, service, buildSession, observabilitySystem, buildParameters)
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
        case .address, .thread, .undefined, .scudo, .fuzzer: true
        }
    }

    var swiftBuildSettingName: String? {
        switch self {
        case .address: "ENABLE_ADDRESS_SANITIZER"
        case .thread: "ENABLE_THREAD_SANITIZER"
        case .undefined: "ENABLE_UNDEFINED_BEHAVIOR_SANITIZER"
        case .scudo: "ENABLE_SCUDO_SANITIZER"
        case .fuzzer: "ENABLE_LIBFUZZER"
        }

    }
}

@Suite(
    .tags(
        .TestSize.medium,
    ),
    .requireCompiledWith6_3OrLater("https://github.com/swiftlang/swift-corelibs-foundation/pull/5269")
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
                    buildSystemKind: .swiftbuild,
                    sanitizers: [sanitizer],
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings: SWBBuildParameters = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
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
                    buildSystemKind: .swiftbuild,
                    sanitizers: [sanitizer],
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                await #expect(throws: (any Error).self) {
                    try await swiftBuild.makeBuildParameters(
                        service: service,
                        session: session,
                        symbolGraphOptions: nil,
                        setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
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
                    buildSystemKind: .swiftbuild,
                    shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
                    triple: triple,
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                // WHEN we make the build parameter
                let _: SWBBuildParameters = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
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
                    buildSystemKind: .swiftbuild,
                    shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
                    triple: nonDarwinTriple,
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                // WHEN we make the build parameter
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
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
                buildSystemKind: .swiftbuild,
                indexStoreMode: indexStoreSettingUT,
            ),
        ) { swiftBuild, service, session, observabilityScope, buildParameters in
            let buildSettings = try await swiftBuild.makeBuildParameters(
                service: service,
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
            )

            let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
            let expectedSettingValue: String? =
                switch indexStoreSettingUT {
                case .on: "YES"
                case .off: "NO"
                case .auto: nil
                }
            let expectedPathValue: String? =
                switch indexStoreSettingUT {
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
                buildSystemKind: .swiftbuild,
                linkerDeadStrip: linkerDeadStripUT,
            ),
        ) { swiftBuild, service, session, observabilityScope, buildParameters in

            let buildSettings = try await swiftBuild.makeBuildParameters(
                service: service,
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false,  // Set this to false as SwiftBuild checks the toolchain path
            )

            let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
            let actual = synthesizedArgs.table["DEAD_CODE_STRIPPING"]
            #expect(
                actual == expectedValue,
                "dead strip: \(linkerDeadStripUT) >>> Actual: '\(actual)' expected: '\(String(describing: expectedValue))'",
            )
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9321", relationship: .verifies),
        arguments: [
            0,
            1,
            2,
            10,
        ],
    )
    func numberOfWorkersBuildParameterSetsTheExpectedSwiftBuildRequest(
        expectedNumberOfWorkers: UInt32,
    ) async throws {
        try await withTemporaryDirectory { tempDir in
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    numberOfWorkers: expectedNumberOfWorkers,
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildRequest = try await swiftBuild.makeBuildRequest(
                    service: service,
                    session: session,
                    configuredTargets: [],
                    derivedDataPath: tempDir,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                #expect(buildRequest.schedulerLaneWidthOverride == expectedNumberOfWorkers)
            }
        }
    }

    @Test
    func cFlagsAppliedToSwiftInBuildRequest() async throws {
        try await withTemporaryDirectory { tempDir in
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    flags: .init(cCompilerFlags: [BuildFlag(value: "-DFoo", source: .commandLineOptions)]),
                    buildSystemKind: .swiftbuild
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildRequest = try await swiftBuild.makeBuildRequest(
                    service: service,
                    session: session,
                    configuredTargets: [],
                    derivedDataPath: tempDir,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                #expect(buildRequest.parameters.overrides.synthesized?.table["OTHER_CFLAGS"]?.contains("-DFoo") == true)
                #expect(buildRequest.parameters.overrides.synthesized?.table["OTHER_SWIFT_FLAGS"]?.contains("-Xcc -DFoo") == true)
            }
        }
    }

    @Suite
    struct DebuggingSettingsTests {

        private static let isMacOS: Bool = {
            #if os(macOS)
                return true
            #else
                return false
            #endif
        }()

        @Test(
            .disabled(if: !Self.isMacOS, "shouldEnableDebuggingEntitlement is only effective on macOS"),
            arguments: [true, false]
        )
        func shouldEnableDebuggingEntitlementSetsDeploymentPostprocessing(
            shouldEnableDebuggingEntitlement: Bool
        ) async throws {
            // Note: shouldEnableDebuggingEntitlement is only effective on macOS
            // (see BuildParameters.Debugging.init where it checks triple.isMacOSX)
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    triple: .x86_64MacOS,
                    shouldEnableDebuggingEntitlement: shouldEnableDebuggingEntitlement
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)

                if shouldEnableDebuggingEntitlement {
                    #expect(synthesizedArgs.table["DEPLOYMENT_POSTPROCESSING"] == "NO")
                } else {
                    #expect(synthesizedArgs.table["DEPLOYMENT_POSTPROCESSING"] == nil)
                }
            }
        }

        @Test(
            arguments: [
                (debugInfoFormat: BuildParameters.DebugInfoFormat.dwarf, expectedSetting: "DEBUG_INFORMATION_FORMAT", expectedValue: "dwarf"),
                (debugInfoFormat: BuildParameters.DebugInfoFormat.none, expectedSetting: "GCC_GENERATE_DEBUGGING_SYMBOLS", expectedValue: "NO"),
            ]
        )
        func debugInfoFormatSetsCorrectBuildSettings(
            debugInfoFormat: BuildParameters.DebugInfoFormat,
            expectedSetting: String,
            expectedValue: String
        ) async throws {
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    debugInfoFormat: debugInfoFormat
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
                #expect(synthesizedArgs.table[expectedSetting] == expectedValue)
            }
        }

        #if os(Windows)
            @Test
            func debugInfoFormatCodeViewOnWindows() async throws {
                // Test CodeView format separately as it's only supported on Windows
                try await withInstantiatedSwiftBuildSystem(
                    fromFixture: "PIFBuilder/Simple",
                    buildParameters: mockBuildParameters(
                        destination: .host,
                        buildSystemKind: .swiftbuild,
                        triple: .windows,
                        debugInfoFormat: .codeview
                    ),
                ) { swiftBuild, service, session, observabilityScope, buildParameters in
                    let buildSettings = try await swiftBuild.makeBuildParameters(
                        service: service,
                        session: session,
                        symbolGraphOptions: nil,
                        setToolchainSetting: false
                    )

                    let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
                    #expect(synthesizedArgs.table["DEBUG_INFORMATION_FORMAT"] == "codeview")
                }
            }
        #endif

        @Test(
            arguments: [
                (omitFramePointers: true, expectedValue: "YES"),
                (omitFramePointers: false, expectedValue: "NO"),
            ]
        )
        func omitFramePointersSetsCorrectBuildSettings(
            omitFramePointers: Bool,
            expectedValue: String
        ) async throws {
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    omitFramePointers: omitFramePointers
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
                #expect(synthesizedArgs.table["CLANG_OMIT_FRAME_POINTERS"] == expectedValue)
                #expect(synthesizedArgs.table["SWIFT_OMIT_FRAME_POINTERS"] == expectedValue)
            }
        }

        @Test
        func omitFramePointersNilDoesNotSetBuildSettings() async throws {
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    omitFramePointers: nil
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)

                // Note: On Linux, omitFramePointers=nil is converted to false by BuildParameters.Debugging.init
                // to preserve frame pointers for better backtraces (see BuildParameters+Debugging.swift:34-36)
                #if os(Linux)
                    #expect(synthesizedArgs.table["CLANG_OMIT_FRAME_POINTERS"] == "NO")
                    #expect(synthesizedArgs.table["SWIFT_OMIT_FRAME_POINTERS"] == "NO")
                #else
                    #expect(synthesizedArgs.table["CLANG_OMIT_FRAME_POINTERS"] == nil)
                    #expect(synthesizedArgs.table["SWIFT_OMIT_FRAME_POINTERS"] == nil)
                #endif
            }
        }

        @Test
        func allDebuggingSettingsCombinedWork() async throws {
            // Test that all debugging settings work together correctly
            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    buildSystemKind: .swiftbuild,
                    debugInfoFormat: .dwarf,
                    shouldEnableDebuggingEntitlement: true,
                    omitFramePointers: false
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)

                // Check all settings are present
                #if os(macOS)
                    #expect(synthesizedArgs.table["DEPLOYMENT_POSTPROCESSING"] == "NO")
                #endif
                #expect(synthesizedArgs.table["DEBUG_INFORMATION_FORMAT"] == "dwarf")
                #expect(synthesizedArgs.table["CLANG_OMIT_FRAME_POINTERS"] == "NO")
                #expect(synthesizedArgs.table["SWIFT_OMIT_FRAME_POINTERS"] == "NO")
            }
        }

        @Test
        func debuggingFlagsAreFilteredFromCompilerFlags() async throws {
            // Verify that flags with source: .debugging are properly filtered out by rawFlagsForSwiftBuild
            // and don't appear in OTHER_CFLAGS, OTHER_CPLUSPLUSFLAGS, OTHER_SWIFT_FLAGS, or OTHER_LDFLAGS

            let debuggingCFlags = [
                BuildFlag(value: "-g", source: .debugging),
                BuildFlag(value: "-fomit-frame-pointer", source: .debugging),
            ]
            let debuggingSwiftFlags = [
                BuildFlag(value: "-g", source: .debugging),
                BuildFlag(value: "-Xcc", source: .debugging),
                BuildFlag(value: "-fno-omit-frame-pointer", source: .debugging),
            ]
            let userCFlags = [
                BuildFlag(value: "-DUSER_DEFINE", source: .commandLineOptions)
            ]
            let userSwiftFlags = [
                BuildFlag(value: "-DSWIFT_USER", source: .commandLineOptions)
            ]

            let flags = BuildFlags(
                cCompilerFlags: debuggingCFlags + userCFlags,
                cxxCompilerFlags: debuggingCFlags,
                swiftCompilerFlags: debuggingSwiftFlags + userSwiftFlags,
                linkerFlags: []
            )

            try await withInstantiatedSwiftBuildSystem(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(
                    destination: .host,
                    flags: flags,
                    buildSystemKind: .swiftbuild,
                    debugInfoFormat: .dwarf,
                    omitFramePointers: false
                ),
            ) { swiftBuild, service, session, observabilityScope, buildParameters in
                let buildSettings = try await swiftBuild.makeBuildParameters(
                    service: service,
                    session: session,
                    symbolGraphOptions: nil,
                    setToolchainSetting: false
                )

                let synthesizedArgs = try #require(buildSettings.overrides.synthesized)

                // Check OTHER_CFLAGS
                let otherCFlags = synthesizedArgs.table["OTHER_CFLAGS"] ?? ""
                #expect(
                    !otherCFlags.contains("-g"),
                    "OTHER_CFLAGS should not contain debug flags with source: .debugging"
                )
                #expect(
                    !otherCFlags.contains("-fomit-frame-pointer"),
                    "OTHER_CFLAGS should not contain frame pointer flags with source: .debugging"
                )
                #expect(
                    otherCFlags.contains("-DUSER_DEFINE"),
                    "OTHER_CFLAGS should contain user flags with source: .commandLineOptions"
                )

                // Check OTHER_CPLUSPLUSFLAGS
                let otherCPlusPlusFlags = synthesizedArgs.table["OTHER_CPLUSPLUSFLAGS"] ?? ""
                #expect(
                    !otherCPlusPlusFlags.contains("-g"),
                    "OTHER_CPLUSPLUSFLAGS should not contain debug flags with source: .debugging"
                )
                #expect(
                    !otherCPlusPlusFlags.contains("-fomit-frame-pointer"),
                    "OTHER_CPLUSPLUSFLAGS should not contain frame pointer flags with source: .debugging"
                )

                // Check OTHER_SWIFT_FLAGS
                let otherSwiftFlags = synthesizedArgs.table["OTHER_SWIFT_FLAGS"] ?? ""
                #expect(
                    !otherSwiftFlags.contains("-g"),
                    "OTHER_SWIFT_FLAGS should not contain debug flags with source: .debugging"
                )
                #expect(
                    !otherSwiftFlags.contains("-fno-omit-frame-pointer"),
                    "OTHER_SWIFT_FLAGS should not contain frame pointer flags with source: .debugging"
                )
                #expect(
                    otherSwiftFlags.contains("-DSWIFT_USER"),
                    "OTHER_SWIFT_FLAGS should contain user flags with source: .commandLineOptions"
                )

                // Verify that dedicated build settings are still set correctly
                #expect(synthesizedArgs.table["DEBUG_INFORMATION_FORMAT"] == "dwarf")
                #expect(synthesizedArgs.table["CLANG_OMIT_FRAME_POINTERS"] == "NO")
                #expect(synthesizedArgs.table["SWIFT_OMIT_FRAME_POINTERS"] == "NO")
            }
        }
    }

    @Test
    func swiftCompilerFlagsForwardedToLinkerDriver() async throws {
        let flags = BuildFlags(
            swiftCompilerFlags: [
                BuildFlag(value: "-no-toolchain-stdlib-rpath", source: .commandLineOptions)
            ]
        )

        try await withInstantiatedSwiftBuildSystem(
            fromFixture: "PIFBuilder/Simple",
            buildParameters: mockBuildParameters(
                destination: .host,
                flags: flags,
                buildSystemKind: .swiftbuild,
            ),
        ) { swiftBuild, service, session, observabilityScope, buildParameters in
            let buildSettings = try await swiftBuild.makeBuildParameters(
                service: service,
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false
            )

            let synthesizedArgs = try #require(buildSettings.overrides.synthesized)
            let otherSwiftFlags = try #require(synthesizedArgs.table["OTHER_SWIFT_FLAGS"])
            #expect(otherSwiftFlags.contains("-no-toolchain-stdlib-rpath"))
            let ldFlagsSwiftc = try #require(synthesizedArgs.table["OTHER_LDFLAGS_SWIFTC_LINKER_DRIVER_swiftc"])
            #expect(ldFlagsSwiftc.contains("-no-toolchain-stdlib-rpath"))
            let otherLDFlags = try #require(synthesizedArgs.table["OTHER_LDFLAGS"])
            #expect(otherLDFlags.contains("$(OTHER_LDFLAGS_SWIFTC_LINKER_DRIVER_$(LINKER_DRIVER))"))
        }
    }

    @Test
    func sdkRootOverrideIsSetInRunDestination() async throws {
        let sdkRoot = AbsolutePath("/fake/sdk/root")
        try await withInstantiatedSwiftBuildSystem(
            fromFixture: "PIFBuilder/Simple",
            buildParameters: mockBuildParameters(
                destination: .host,
                buildSystemKind: .swiftbuild,
                sdkRootOverride: sdkRoot,
            ),
        ) { swiftBuild, service, session, observabilityScope, buildParameters in
            let buildSettings = try await swiftBuild.makeBuildParameters(
                service: service,
                session: session,
                symbolGraphOptions: nil,
                setToolchainSetting: false,
            )

            let runDestination = try #require(buildSettings.activeRunDestination)
            #expect(runDestination.sdk == sdkRoot.pathString)
        }
    }
}
