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
@testable import CoreCommands

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import func PackageGraph.loadModulesGraph

import _InternalTestSupport
@testable import PackageModel
import XCTest

import ArgumentParser
import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.SystemError
import var TSCBasic.stderrStream

final class SwiftCommandStateTests: CommandsTestCase {
    func testSeverityEnum() async throws {
        try fixture(name: "Miscellaneous/Simple") { _ in

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
        try fixture(name: "Miscellaneous/Simple") { fixturePath in
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
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
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
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
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

extension SwiftCommandState {
    static func makeMockState(
        outputStream: OutputByteStream = stderrStream,
        options: GlobalOptions,
        createPackagePath: Bool = false,
        fileSystem: any FileSystem = localFileSystem,
        environment: Environment = .current
    ) throws -> SwiftCommandState {
        return try SwiftCommandState(
            outputStream: outputStream,
            options: options,
            toolWorkspaceConfiguration: .init(shouldInstallSignalHandlers: false),
            workspaceDelegateProvider: {
                CommandWorkspaceDelegate(
                    observabilityScope: $0,
                    outputHandler: $1,
                    progressHandler: $2,
                    inputHandler: $3
                )
            },
            workspaceLoaderProvider: {
                XcodeWorkspaceLoader(
                    fileSystem: $0,
                    observabilityScope: $1
                )
            },
            createPackagePath: createPackagePath,
            hostTriple: .arm64Linux,
            fileSystem: fileSystem,
            environment: environment
        )
    }
}
