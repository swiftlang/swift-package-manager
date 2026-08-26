//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
@testable import Build
@testable import Commands
@_spi(SwiftPMTesting) @testable import CoreCommands

import struct SPMBuildCore.BuildSystemProvider
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import func PackageGraph.loadModulesGraph

import _InternalTestSupport
@testable import PackageModel
import XCTest

import ArgumentParser
import Foundation
import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.SystemError
import var TSCBasic.stderrStream

import Testing

@Suite()
struct SwiftCommandStateTests {

    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: [
            AbsolutePath.root,
            AbsolutePath.root.appending(component: "cacheDir"),
            AbsolutePath.root.appending(components: "foo", "bar", "baz"),
        ]
    )
    func cacheDirTagFileContainsExpectedContents(
        cacheDirectory: AbsolutePath,
    ) async throws {
        let fs = InMemoryFileSystem()
        // let cacheDirectory = AbsolutePath.root.appending(components: components)

        let actual = try #require(createCacheDirFile(inDirectory: cacheDirectory, fs))

        let contents = try fs.readFileContents(actual).description
        let contentArray = contents.split(whereSeparator: \.isNewline)
        try #require(contentArray.isEmpty == false, "Content array is empty, when it shouldn't be. Content is: \(contents)")
        #expect(contentArray[0] == "Signature: 8a477f597d28d172789f06886806bc55")
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: getBuildData(for: BuildSystemProvider.Kind.allCases)
    ) func createBuildSystemFileContainsExpectedContents(
        buildData: BuildData,
    ) async throws {
        let fs = InMemoryFileSystem()
        let dir = AbsolutePath.root.appending(components: "tmp", "output", "build")
        let buildSystemDefinitionFile = dir.appending(".buildSystem_\(buildData.config)")

        try requireFileDoesNotExist(
            at: buildSystemDefinitionFile,
            fileSystem: fs,
        )
        let actualBuildSystemDefinition = try #require(
            createBuildSystemFile(
                inDirectory: dir,
                for: buildData.config,
                buildSystem: buildData.buildSystem,
                fileSystem: fs,
            )
        )

        // Assert
        try #require(actualBuildSystemDefinition == buildSystemDefinitionFile)
        try requireFileExists(
            at: actualBuildSystemDefinition,
            fileSystem: fs
        )
        let contents = try fs.readFileContents(actualBuildSystemDefinition).description
        #expect(
            contents == "\(buildData.buildSystem)",
            "Actual is not as expected",
        )
    }

    private static func makeSDKRootOverrideState(
        arguments: [String],
        environment: Environment,
    ) throws -> (state: SwiftCommandState, output: BufferedOutputByteStream) {
        let fs = InMemoryFileSystem(emptyFiles: ["/Pkg/Sources/exe/main.swift"])
        let outputStream = BufferedOutputByteStream()
        let state = try SwiftCommandState.makeMockState(
            outputStream: outputStream,
            options: GlobalOptions.parse(arguments),
            fileSystem: fs,
            environment: environment,
        )
        return (state, outputStream)
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func sdkRootOverrideDefaultsToUnset() throws {
        let (state, output) = try Self.makeSDKRootOverrideState(arguments: [], environment: [:])

        #expect(state.computeSDKRootOverride() == nil)

        state.waitForObservabilityEvents(timeout: .now() + .seconds(1))
        #expect(!output.bytes.validDescription!.contains("warning:"))
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func sdkRootOverrideComesFromSDKOption() throws {
        let (state, _) = try Self.makeSDKRootOverrideState(
            arguments: ["--sdk", "/fake/sdk"],
            environment: [:],
        )

        #expect(state.computeSDKRootOverride() == AbsolutePath("/fake/sdk"))
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func sdkRootOverrideComesFromSDKROOTEnvironmentVariable() throws {
        let (state, _) = try Self.makeSDKRootOverrideState(
            arguments: [],
            environment: ["SDKROOT": "/fake/env/sdk"],
        )

        #expect(state.computeSDKRootOverride() == AbsolutePath("/fake/env/sdk"))
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func sdkOptionTakesPrecedenceOverSDKROOTEnvironmentVariable() throws {
        let (state, _) = try Self.makeSDKRootOverrideState(
            arguments: ["--sdk", "/fake/sdk"],
            environment: ["SDKROOT": "/fake/env/sdk"],
        )

        #expect(state.computeSDKRootOverride() == AbsolutePath("/fake/sdk"))
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func swiftSDKSuppressesSDKOptionWithWarning() throws {
        let (state, output) = try Self.makeSDKRootOverrideState(
            arguments: ["--sdk", "/fake/sdk", "--swift-sdk", "my-swift-sdk"],
            environment: [:],
        )

        #expect(state.computeSDKRootOverride() == nil)

        state.waitForObservabilityEvents(timeout: .now() + .seconds(1))
        let contents = try #require(output.bytes.validDescription)
        #expect(
            contents.contains(
                "warning: ignoring the SDK '/fake/sdk' specified using '--sdk' because the Swift SDK 'my-swift-sdk' was selected with '--swift-sdk'"
            ),
        )
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func swiftSDKSuppressesSDKROOTEnvironmentVariableWithWarning() throws {
        let (state, output) = try Self.makeSDKRootOverrideState(
            arguments: ["--swift-sdk", "my-swift-sdk"],
            environment: ["SDKROOT": "/fake/env/sdk"],
        )

        #expect(state.computeSDKRootOverride() == nil)

        state.waitForObservabilityEvents(timeout: .now() + .seconds(1))
        let contents = try #require(output.bytes.validDescription)
        #expect(
            contents.contains(
                "warning: ignoring the SDK '/fake/env/sdk' specified using the 'SDKROOT' environment variable because the Swift SDK 'my-swift-sdk' was selected with '--swift-sdk'"
            ),
        )
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
        .enabled(if: ProcessInfo.hostOperatingSystem == .macOS),
    )
    func excludeFromBackupMarksDirectoryAsExcluded() async throws {
        try await withTemporaryDirectory { tmpDir in
            let scratchDirectory = tmpDir.appending(".build")
            try localFileSystem.createDirectory(scratchDirectory, recursive: true)

            #expect(excludeFromBackups(directory: scratchDirectory))

            let resourceValues = try scratchDirectory.asURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(resourceValues.isExcludedFromBackup == true)
        }
    }
    // MARK: - workspaceMemberFocusRequiresSwiftBuildDiagnostic

    func workspaceMemberFocusDiagnostic_withNilFocus_returnsNil() throws {
        for buildSystem in BuildSystemProvider.Kind.allCases {
            let diagnostic = SwiftCommandState.workspaceMemberFocusRequiresSwiftBuildDiagnostic(
                focus: nil,
                buildSystem: buildSystem,
            )
            #expect(
                diagnostic == nil,
                "no focus should never surface a diagnostic (buildSystem: \(buildSystem))",
            )
        }
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func workspaceMemberFocusDiagnostic_withFocusAndSwiftBuild_returnsNil() throws {
        let diagnostic = SwiftCommandState.workspaceMemberFocusRequiresSwiftBuildDiagnostic(
            focus: PackageIdentity.plain("app"),
            buildSystem: .swiftbuild,
        )
        #expect(diagnostic == nil)
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: BuildSystemProvider.Kind.allCases.filter { $0 != .swiftbuild },
    )
    func workspaceMemberFocusDiagnostic_withFocusAndNonSwiftBuild_returnsInvalidWorkspaceBuildSystemDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let focus = PackageIdentity.plain("app")
        let expected = Diagnostic.invalidWorkspaceBuildSystem(focus: focus)

        let actual = try #require(
            SwiftCommandState.workspaceMemberFocusRequiresSwiftBuildDiagnostic(
                focus: focus,
                buildSystem: buildSystem,
            ),
            "expected a diagnostic when focus is set and buildSystem is \(buildSystem)",
        )

        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }
    // MARK: - computeResolvedVersionsFile (Slice 8a)

    @Suite(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    struct ComputeResolvedVersionsFileTests {

        /// Baseline: no workspace, no `--multiroot-data-file` → the
        /// resolver falls back to per-package `Package.resolved` at the
        /// current package root. Preserves single-package behavior.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func singlePackage_returnsPerPackagePath() throws {
            let packageRoot = AbsolutePath("/Pkg")
            let actual = try SwiftCommandState.computeResolvedVersionsFile(
                multiRootPackageDataFile: nil,
                workspaceRoot: nil,
                packageRoot: packageRoot,
                buildSystem: .swiftbuild,
            )
            #expect(actual == packageRoot.appending("Package.resolved"))
        }

        /// When a `Workspace.swift` is discovered AND the build system
        /// is Swift Build, `Package.resolved` moves to the workspace
        /// root. This is the Slice 8a invariant: all members share a
        /// single `Package.resolved` and no member ever writes its own.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func withWorkspaceRootAndSwiftBuild_returnsWorkspaceRootPath() throws {
            let workspaceRoot = AbsolutePath("/Workspace")
            let packageRoot = AbsolutePath("/Workspace/packages/app")
            let actual = try SwiftCommandState.computeResolvedVersionsFile(
                multiRootPackageDataFile: nil,
                workspaceRoot: workspaceRoot,
                packageRoot: packageRoot,
                buildSystem: .swiftbuild,
            )
            #expect(actual == workspaceRoot.appending("Package.resolved"))
        }

        /// A `Workspace.swift` is present but the invocation targets a
        /// non-Swift Build backend (native or Xcode). The workspace
        /// model is Slice-1-and-later infrastructure wired only through
        /// Swift Build; the native / XCBuild backends still expect
        /// per-package `Package.resolved`. Letting them see a
        /// workspace-root file would cause them to re-resolve on every
        /// build. So the workspace-root branch is suppressed and the
        /// resolver falls back to the per-package path.
        @Test(
            .tags(
                .TestSize.small,
            ),
            arguments: BuildSystemProvider.Kind.allCases.filter { $0 != .swiftbuild },
        )
        func withWorkspaceRootAndNonSwiftBuild_fallsBackToPerPackagePath(
            buildSystem: BuildSystemProvider.Kind,
        ) throws {
            let workspaceRoot = AbsolutePath("/Workspace")
            let packageRoot = AbsolutePath("/Workspace/packages/app")
            let actual = try SwiftCommandState.computeResolvedVersionsFile(
                multiRootPackageDataFile: nil,
                workspaceRoot: workspaceRoot,
                packageRoot: packageRoot,
                buildSystem: buildSystem,
            )
            #expect(
                actual == packageRoot.appending("Package.resolved"),
                "non-Swift Build backend (\(buildSystem)) must not see workspace-root Package.resolved",
            )
        }

        /// `--multiroot-data-file` still wins over the workspace-root
        /// preference — its `xcshareddata/swiftpm/Package.resolved`
        /// location is an explicit Xcode-workspace override that predates
        /// the Slice 1 workspace model and must remain honored,
        /// regardless of the build system in play.
        @Test(
            .tags(
                .TestSize.small,
            ),
            arguments: BuildSystemProvider.Kind.allCases,
        )
        func withMultirootDataFile_takesPrecedenceOverWorkspaceRoot(
            buildSystem: BuildSystemProvider.Kind,
        ) throws {
            let multirootDataFile = AbsolutePath("/App.xcworkspace")
            let workspaceRoot = AbsolutePath("/Workspace")
            let packageRoot = AbsolutePath("/Workspace/packages/app")
            let actual = try SwiftCommandState.computeResolvedVersionsFile(
                multiRootPackageDataFile: multirootDataFile,
                workspaceRoot: workspaceRoot,
                packageRoot: packageRoot,
                buildSystem: buildSystem,
            )
            #expect(
                actual == multirootDataFile.appending(components: "xcshareddata", "swiftpm", "Package.resolved"),
            )
        }

        /// Terminal fallback: no workspace, no multiroot override, and no
        /// package root either — nothing to anchor `Package.resolved` to.
        /// The function throws `SwiftCommandStateError.packageManifestNotFound`
        /// so callers can distinguish "no manifest" from other filesystem
        /// errors, and the pre-workspaces error path stays intact.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func withNoInputs_throwsPackageManifestNotFound() throws {
            #expect(throws: SwiftCommandStateError.packageManifestNotFound) {
                _ = try SwiftCommandState.computeResolvedVersionsFile(
                    multiRootPackageDataFile: nil,
                    workspaceRoot: nil,
                    packageRoot: nil,
                    buildSystem: .swiftbuild,
                )
            }

        }
    }

    // MARK: - flushMemberStateFindings (Slice 8c)

    /// End-to-end integration coverage for the
    /// `SwiftCommandState.memberStateFindings` push buffer and its
    /// `flushMemberStateFindings()` drain. The unit-level formatter
    /// and scanner are covered in `MemberStateFindingsTests`; this
    /// suite pins the `SwiftCommandState` boundary — that seeded
    /// findings actually reach the observability sink as a single
    /// aggregated warning, and that the buffer's `nil` sentinel makes
    /// the drain idempotent so both the sync and async command
    /// runners can safely call it.
    @Suite(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    struct FlushMemberStateFindingsTests {

        /// Seed one finding, flush, and observe the aggregated warning
        /// on the tool's output stream. Pins the happy-path contract:
        /// `flushMemberStateFindings()` routes buffered findings
        /// through `MemberStateFindings.formatWarning` and emits the
        /// resulting diagnostic on `observabilityScope`.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func withFindingsInBuffer_emitsAggregatedWarning() async throws {
            try fixture(name: "Miscellaneous/Simple") { fixturePath in
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)

                tool.memberStateFindings = [
                    MemberStateFindings(
                        memberIdentity: .plain("lib-a"),
                        detectedStateFiles: [.build, .packageResolved],
                    ),
                ]
                tool.flushMemberStateFindings()
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let output = try #require(outputStream.bytes.validDescription)
                #expect(output.contains("workspace members have ignored state:"))
                #expect(output.contains("lib-a"))
                #expect(output.contains(".build/, Package.resolved"))
                #expect(tool.memberStateFindings == nil)
            }
        }

        /// After a successful flush, `memberStateFindings` must be
        /// `nil` — not an empty array. The nil sentinel is what makes
        /// a second flush (from the other command runner) a no-op
        /// rather than an empty-diagnostic re-emission.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func afterFlush_bufferIsNil() async throws {
            try fixture(name: "Miscellaneous/Simple") { fixturePath in
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)

                tool.memberStateFindings = [
                    MemberStateFindings(
                        memberIdentity: .plain("lib-a"),
                        detectedStateFiles: [.build],
                    ),
                ]
                tool.flushMemberStateFindings()

                #expect(tool.memberStateFindings == nil)
            }
        }

        /// When workspace discovery never ran, `memberStateFindings`
        /// stays `nil` and flush is a no-op — nothing on the wire, no
        /// spurious buffer initialization. Covers the guard clause
        /// that keeps single-package commands quiet.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func withNilBuffer_emitsNothing() async throws {
            try fixture(name: "Miscellaneous/Simple") { fixturePath in
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)

                tool.flushMemberStateFindings()
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let output = try #require(outputStream.bytes.validDescription)
                #expect(output.contains("workspace members have ignored state:") == false)
                #expect(tool.memberStateFindings == nil)
            }
        }

        /// Workspace discovery ran but no member has stale state:
        /// buffer is `[]`. Flush must still consume the buffer (set
        /// to `nil`) and emit nothing — the empty case is not a
        /// diagnostic, just a clean workspace.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func withEmptyBuffer_emitsNothing() async throws {
            try fixture(name: "Miscellaneous/Simple") { fixturePath in
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)

                tool.memberStateFindings = []
                tool.flushMemberStateFindings()
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let output = try #require(outputStream.bytes.validDescription)
                #expect(output.contains("workspace members have ignored state:") == false)
                #expect(tool.memberStateFindings == nil)
            }
        }

        /// Both `SwiftCommand.run()` and `AsyncSwiftCommand.run()`
        /// call `flushMemberStateFindings()` from their runners; a
        /// tool invoked via one entry point then torn down through
        /// the other must not double-emit. Seed once, flush twice,
        /// assert the aggregated warning appears exactly once in the
        /// captured bytes.
        @Test(
            .tags(
                .TestSize.small,
            ),
        )
        func doubleFlush_secondCallIsNoOp() async throws {
            try fixture(name: "Miscellaneous/Simple") { fixturePath in
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)

                tool.memberStateFindings = [
                    MemberStateFindings(
                        memberIdentity: .plain("lib-a"),
                        detectedStateFiles: [.build],
                    ),
                ]
                tool.flushMemberStateFindings()
                tool.flushMemberStateFindings()
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let output = try #require(outputStream.bytes.validDescription)
                let occurrences = output.components(separatedBy: "workspace members have ignored state:").count - 1
                #expect(occurrences == 1, "expected the aggregated warning to be emitted exactly once, got \(occurrences)")
            }
        }
    }
}

final class SwiftCommandStateTestsXCTest: XCTestCase {
    /// Original working directory before the test ran (if known).
    private var originalWorkingDirectory: AbsolutePath? = .none

    override func setUp() {
        originalWorkingDirectory = localFileSystem.currentWorkingDirectory
    }

    override func tearDown() {
        if let originalWorkingDirectory {
            try? localFileSystem.changeCurrentWorkingDirectory(to: originalWorkingDirectory)
        }
     }

    func testSeverityEnum() async throws {
        try fixtureXCTest(name: "Miscellaneous/Simple") { _ in

            do {
                let info = Diagnostic(severity: .info, message: "info-string", metadata: nil)
                let debug = Diagnostic(severity: .debug, message: "debug-string", metadata: nil)
                let warning = Diagnostic(severity: .warning, message: "warning-string", metadata: nil)
                let error = Diagnostic(severity: .error, message: "error-string", metadata: nil)
                // testing color
                XCTAssertEqual(info.severity.color, .white)
                XCTAssertEqual(debug.severity.color, .white)
                XCTAssertEqual(warning.severity.color, .yellow)
                XCTAssertEqual(error.severity.color, .red)

                // testing prefix
                XCTAssertEqual(info.severity.logLabel, "info: ")
                XCTAssertEqual(debug.severity.logLabel, "debug: ")
                XCTAssertEqual(warning.severity.logLabel, "warning: ")
                XCTAssertEqual(error.severity.logLabel, "error: ")

                // testing boldness
                XCTAssertTrue(info.severity.isBold)
                XCTAssertTrue(debug.severity.isBold)
                XCTAssertTrue(warning.severity.isBold)
                XCTAssertTrue(error.severity.isBold)
            }
        }
    }

    func testVerbosityLogLevel() async throws {
        try fixtureXCTest(name: "Miscellaneous/Simple") { fixturePath in
            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .warning)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--verbose"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-v"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--very-verbose"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--vv"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--quiet"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-q"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }
        }
    }

    func testAuthorizationProviders() async throws {
        try fixtureXCTest(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let customPath = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    customPath,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                let authorizationProvider = try tool.getAuthorizationProvider() as? CompositeAuthorizationProvider
                let netrcProviders = authorizationProvider?.providers.compactMap { $0 as? NetrcAuthorizationProvider } ?? []
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(try netrcProviders.first.map { try resolveSymlinks($0.path) }, try resolveSymlinks(customPath))

                let auth = try tool.getAuthorizationProvider()?.authentication(for: "https://mymachine.labkey.org")
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getAuthorizationProvider(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("Did not find netrc file at \(customPath)."))
                }
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    func testRegistryAuthorizationProviders() async throws {
        try fixtureXCTest(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let customPath = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    customPath,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // There is only one AuthorizationProvider depending on platform
#if canImport(Security)
                let keychainProvider = try tool.getRegistryAuthorizationProvider() as? KeychainAuthorizationProvider
                XCTAssertNotNil(keychainProvider)
#else
                let netrcProvider = try tool.getRegistryAuthorizationProvider() as? NetrcAuthorizationProvider
                XCTAssertNotNil(netrcProvider)
                XCTAssertEqual(try netrcProvider.map { try resolveSymlinks($0.path) }, try resolveSymlinks(customPath))

                let auth = try tool.getRegistryAuthorizationProvider()?.authentication(for: "https://mymachine.labkey.org")
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getRegistryAuthorizationProvider(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("did not find netrc file at \(customPath)"))
                }
#endif
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    func testDebugFormatFlags() async throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/Pkg/Sources/exe/main.swift",
        ])

        let observer = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(fileSystem: fs, manifests: [
            Manifest.createRootManifest(displayName: "Pkg",
                                        path: "/Pkg",
                                        targets: [TargetDescription(name: "exe")])
        ], observabilityScope: observer.topScope)

        var plan: BuildPlan

        /* -debug-info-format dwarf */
        let explicitDwarfOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "dwarf"])
        let explicitDwarf = try SwiftCommandState.makeMockState(options: explicitDwarfOptions)
        plan = try await BuildPlan(
            destinationBuildParameters: explicitDwarf.productsBuildParameters,
            toolsBuildParameters: explicitDwarf.toolsBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"])

        /* -debug-info-format codeview */
        let explicitCodeViewOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "codeview"])
        let explicitCodeView = try SwiftCommandState.makeMockState(options: explicitCodeViewOptions)

        plan = try await BuildPlan(
            destinationBuildParameters: explicitCodeView.productsBuildParameters,
            toolsBuildParameters: explicitCodeView.productsBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-debug-info-format=codeview", "-Xlinker", "-debug"])

        // Explicitly pass Linux as when the `SwiftCommandState` tests are enabled on
        // Windows, this would fail otherwise as CodeView is supported on the
        // native host.
        let unsupportedCodeViewOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-linux-gnu", "-debug-info-format", "codeview"])
        let unsupportedCodeView = try SwiftCommandState.makeMockState(options: unsupportedCodeViewOptions)

        XCTAssertThrowsError(try unsupportedCodeView.productsBuildParameters) {
            XCTAssertEqual($0 as? StringError, StringError("CodeView debug information is currently not supported on linux"))
        }

        /* <<null>> */
        let implicitDwarfOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc"])
        let implicitDwarf = try SwiftCommandState.makeMockState(options: implicitDwarfOptions)
        plan = try await BuildPlan(
            destinationBuildParameters: implicitDwarf.productsBuildParameters,
            toolsBuildParameters: implicitDwarf.toolsBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"])

        /* -debug-info-format none */
        let explicitNoDebugInfoOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "none"])
        let explicitNoDebugInfo = try SwiftCommandState.makeMockState(options: explicitNoDebugInfoOptions)
        plan = try await BuildPlan(
            destinationBuildParameters: explicitNoDebugInfo.productsBuildParameters,
            toolsBuildParameters: explicitNoDebugInfo.toolsBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-gnone", .anySequence])
    }

    func testToolchainOption() async throws {
        try XCTSkipOnWindows(because: #"https://github.com/swiftlang/swift-package-manager/issues/8660, threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation"#)
        let customTargetToolchain = AbsolutePath("/path/to/toolchain")
        let hostSwiftcPath = AbsolutePath("/usr/bin/swiftc")
        let hostArPath = AbsolutePath("/usr/bin/ar")
        let targetSwiftcPath = customTargetToolchain.appending(components: ["usr", "bin", "swiftc"])
        let targetArPath = customTargetToolchain.appending(components: ["usr", "bin", "llvm-ar"])

        let fs = InMemoryFileSystem(emptyFiles: [
            "/Pkg/Sources/exe/main.swift",
            hostSwiftcPath.pathString,
            hostArPath.pathString,
            targetSwiftcPath.pathString,
            targetArPath.pathString
        ])

        for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath,] {
            try fs.updatePermissions(path, isExecutable: true)
        }

        let observer = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [TargetDescription(name: "exe")]
                )
            ],
            observabilityScope: observer.topScope
        )

        let options = try GlobalOptions.parse([
            "--toolchain", customTargetToolchain.pathString,
            "--triple", "x86_64-unknown-linux-gnu",
        ])
        let swiftCommandState = try SwiftCommandState.makeMockState(
            options: options,
            fileSystem: fs,
            environment: ["PATH": "/usr/bin"]
        )

        XCTAssertEqual(swiftCommandState.originalWorkingDirectory, fs.currentWorkingDirectory)
        XCTAssertEqual(
            try swiftCommandState.getTargetToolchain().swiftCompilerPath,
            targetSwiftcPath
        )
        XCTAssertEqual(
            try swiftCommandState.getTargetToolchain().swiftSDK.toolset.knownTools[.swiftCompiler]?.path,
            nil
        )

        let plan = try await BuildPlan(
            destinationBuildParameters: swiftCommandState.productsBuildParameters,
            toolsBuildParameters: swiftCommandState.toolsBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )

        let arguments = try plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? []

        XCTAssertMatch(arguments, [.contains("/path/to/toolchain")])
    }

    func testToolsetOption() throws {
        try XCTSkipOnWindows(because: #"https://github.com/swiftlang/swift-package-manager/issues/8660. threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation"#)
        let targetToolchainPath = "/path/to/toolchain"
        let customTargetToolchain = AbsolutePath(targetToolchainPath)
        let hostSwiftcPath = AbsolutePath("/usr/bin/swiftc")
        let hostArPath = AbsolutePath("/usr/bin/ar")
        let targetSwiftcPath = customTargetToolchain.appending(components: ["swiftc"])
        let targetArPath = customTargetToolchain.appending(components: ["llvm-ar"])

        let fs = InMemoryFileSystem(emptyFiles: [
            hostSwiftcPath.pathString,
            hostArPath.pathString,
            targetSwiftcPath.pathString,
            targetArPath.pathString
        ])

        for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath,] {
            try fs.updatePermissions(path, isExecutable: true)
        }

        try fs.writeFileContents("/toolset.json", string: """
        {
            "schemaVersion": "1.0",
            "rootPath": "\(targetToolchainPath)"
        }
        """)

        let options = try GlobalOptions.parse(["--toolset", "/toolset.json"])
        let swiftCommandState = try SwiftCommandState.makeMockState(
            options: options,
            fileSystem: fs,
            environment: ["PATH": "/usr/bin"]
        )

        let hostToolchain = try swiftCommandState.getHostToolchain()
        let targetToolchain = try swiftCommandState.getTargetToolchain()

        XCTAssertEqual(
            targetToolchain.swiftSDK.toolset.rootPaths,
            [customTargetToolchain] + hostToolchain.swiftSDK.toolset.rootPaths
        )
        XCTAssertEqual(targetToolchain.swiftCompilerPath, targetSwiftcPath)
        XCTAssertEqual(targetToolchain.librarianPath, targetArPath)
    }

    func testMultipleToolsets() throws {
        try XCTSkipOnWindows(because: #"https://github.com/swiftlang/swift-package-manager/issues/8660, threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation"#)
        let targetToolchainPath1 = "/path/to/toolchain1"
        let customTargetToolchain1 = AbsolutePath(targetToolchainPath1)
        let targetToolchainPath2 = "/path/to/toolchain2"
        let customTargetToolchain2 = AbsolutePath(targetToolchainPath2)
        let hostSwiftcPath = AbsolutePath("/usr/bin/swiftc")
        let hostArPath = AbsolutePath("/usr/bin/ar")
        let targetSwiftcPath = customTargetToolchain1.appending(components: ["swiftc"])
        let targetArPath = customTargetToolchain1.appending(components: ["llvm-ar"])
        let targetClangPath = customTargetToolchain2.appending(components: ["clang"])

        let fs = InMemoryFileSystem(emptyFiles: [
            hostSwiftcPath.pathString,
            hostArPath.pathString,
            targetSwiftcPath.pathString,
            targetArPath.pathString,
            targetClangPath.pathString
        ])

        for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath, targetClangPath,] {
            try fs.updatePermissions(path, isExecutable: true)
        }

        try fs.writeFileContents("/toolset1.json", string: """
        {
            "schemaVersion": "1.0",
            "rootPath": "\(targetToolchainPath1)"
        }
        """)

        try fs.writeFileContents("/toolset2.json", string: """
        {
            "schemaVersion": "1.0",
            "rootPath": "\(targetToolchainPath2)"
        }
        """)

        let options = try GlobalOptions.parse([
            "--toolset", "/toolset1.json", "--toolset", "/toolset2.json"
        ])
        let swiftCommandState = try SwiftCommandState.makeMockState(
            options: options,
            fileSystem: fs,
            environment: ["PATH": "/usr/bin"]
        )

        let hostToolchain = try swiftCommandState.getHostToolchain()
        let targetToolchain = try swiftCommandState.getTargetToolchain()

        XCTAssertEqual(
            targetToolchain.swiftSDK.toolset.rootPaths,
            [customTargetToolchain2, customTargetToolchain1] + hostToolchain.swiftSDK.toolset.rootPaths
        )
        XCTAssertEqual(targetToolchain.swiftCompilerPath, targetSwiftcPath)
        XCTAssertEqual(try targetToolchain.getClangCompiler(), targetClangPath)
        XCTAssertEqual(targetToolchain.librarianPath, targetArPath)
    }

    func testPackagePathWithMissingFolder() async throws {
        try withTemporaryDirectory { fixturePath in
            let packagePath = fixturePath.appending(component: "Foo")
            let options = try GlobalOptions.parse(["--package-path", packagePath.pathString])

            do {
                let outputStream = BufferedOutputByteStream()
                XCTAssertThrowsError(try SwiftCommandState.makeMockState(outputStream: outputStream, options: options), "error expected")
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options, createPackagePath: true)
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("error:"))
            }
        }
    }

}
