//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@testable import Basics
@testable import Build
@testable import Commands
@testable import CoreCommands

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import func PackageGraph.loadModulesGraph

import _InternalTestSupport
@testable import PackageModel
import Testing

import ArgumentParser
import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.SystemError
import var TSCBasic.stderrStream

@Suite(
    .serialized,
)
struct SwiftCommandStateTests {
    @Test(
        .tags(
            .TestSize.small,
        )
    )
    func severityEnum() async throws {
        try fixture(name: "Miscellaneous/Simple") { _ in

            do {
                let info = Diagnostic(severity: .info, message: "info-string", metadata: nil)
                let debug = Diagnostic(severity: .debug, message: "debug-string", metadata: nil)
                let warning = Diagnostic(severity: .warning, message: "warning-string", metadata: nil)
                let error = Diagnostic(severity: .error, message: "error-string", metadata: nil)
                // testing color
                #expect(info.severity.color == .white)
                #expect(debug.severity.color == .white)
                #expect(warning.severity.color == .yellow)
                #expect(error.severity.color == .red)

                // testing prefix
                #expect(info.severity.logLabel == "info: ")
                #expect(debug.severity.logLabel == "debug: ")
                #expect(warning.severity.logLabel == "warning: ")
                #expect(error.severity.logLabel == "error: ")

                // testing boldness
                #expect(info.severity.isBold)
                #expect(debug.severity.isBold)
                #expect(warning.severity.isBold)
                #expect(error.severity.isBold)
            }
        }
    }

    @Test
    func verbosityLogLevel() async throws {
        try fixture(name: "Miscellaneous/Simple") { fixturePath in
            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .warning)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(description.contains("warning: warning"))
                #expect(!description.contains("info: info"))
                #expect(!description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--verbose"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(description.contains("warning: warning"))
                #expect(description.contains("info: info"))
                #expect(!description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-v"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(description.contains("warning: warning"))
                #expect(description.contains("info: info"))
                #expect(!description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--very-verbose"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(description.contains("warning: warning"))
                #expect(description.contains("info: info"))
                #expect(description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--vv"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(description.contains("warning: warning"))
                #expect(description.contains("info: info"))
                #expect(description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--quiet"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(!description.contains("warning: warning"))
                #expect(!description.contains("info: info"))
                #expect(!description.contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-q"])
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                #expect(tool.logLevel == .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                let description = try #require(outputStream.bytes.validDescription)
                #expect(description.contains("error: error"))
                #expect(!description.contains("warning: warning"))
                #expect(!description.contains("info: info"))
                #expect(!description.contains("debug: debug"))
            }
        }
    }

    @Test
    func authorizationProviders() async throws {
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let netrcFile = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    netrcFile,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", netrcFile.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                let authorizationProvider = try #require(tool.getAuthorizationProvider() as? CompositeAuthorizationProvider)
                let netrcProviders = authorizationProvider.providers.compactMap { $0 as? NetrcAuthorizationProvider }
                try #require(netrcProviders.count == 1)
                let expectedPath = try resolveSymlinks(netrcFile)
                let actualPath = try netrcProviders.first.map { try resolveSymlinks($0.path) }
                #expect(actualPath == expectedPath)

                let auth = try #require(tool.getAuthorizationProvider()?.authentication(for: "https://mymachine.labkey.org"))
                #expect(auth.user == "custom@labkey.org")
                #expect(auth.password == "custom")

                // delete it
                try localFileSystem.removeFileTree(netrcFile)
                #expect(throws: StringError("Did not find netrc file at \(netrcFile).")) {
                    try tool.getAuthorizationProvider()
                }
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    @Test
    func registryAuthorizationProviders() async throws {
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let netrcFile = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    netrcFile,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", netrcFile.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // There is only one AuthorizationProvider depending on platform
                #if canImport(Security)
                    let _ = try #require(tool.getRegistryAuthorizationProvider() as? KeychainAuthorizationProvider)
                #else
                    let netrcProvider = try #require(tool.getRegistryAuthorizationProvider() as? NetrcAuthorizationProvider)
                    let expectedPath = try resolveSymlinks(netrcFile)
                    #expect(try netrcProvider.map { try resolveSymlinks($0.path) } == expectedPath)

                    let authorizationProvider = try #require(tool.getRegistryAuthorizationProvider())
                    let auth = authorizationProvider.authentication(for: "https://mymachine.labkey.org")
                    #expect(auth.user == "custom@labkey.org")
                    #expect(auth.password == "custom")

                    // delete it
                    try localFileSystem.removeFileTree(netrcFile)
                    #expect(throws: (any Error).self, "error expected") { error in
                        #expect(error as? StringError == StringError("did not find netrc file at \(netrcFile)"))
                    }
                #endif
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    @Test
    func debugFormatFlags() async throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/Pkg/Sources/exe/main.swift"
        ])

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
        try XCTAssertMatch(
            plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
            [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"]
        )

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
        try XCTAssertMatch(
            plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
            [.anySequence, "-g", "-debug-info-format=codeview", "-Xlinker", "-debug"]
        )

        // Explicitly pass Linux as when the `SwiftCommandState` tests are enabled on
        // Windows, this would fail otherwise as CodeView is supported on the
        // native host.
        let unsupportedCodeViewOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-linux-gnu", "-debug-info-format", "codeview"])
        let unsupportedCodeView = try SwiftCommandState.makeMockState(options: unsupportedCodeViewOptions)

        #expect(throws: StringError("CodeView debug information is currently not supported on linux")) {
            try unsupportedCodeView.productsBuildParameters
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
        try XCTAssertMatch(
            plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
            [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"]
        )

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
        try XCTAssertMatch(
            plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
            [.anySequence, "-gnone", .anySequence]
        )
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8660", relationship: .defect), // threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation
    )
    func toolchainOption() async throws {
        try await withKnownIssue {
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
                targetArPath.pathString,
            ])

            for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath] {
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

            #expect(swiftCommandState.originalWorkingDirectory == fs.currentWorkingDirectory)
            #expect(try swiftCommandState.getTargetToolchain().swiftCompilerPath == targetSwiftcPath)
            let compilerToolProperties = try #require(try swiftCommandState.getTargetToolchain().swiftSDK.toolset.knownTools[.swiftCompiler])
            #expect(compilerToolProperties.path == nil)

            let plan = try await BuildPlan(
                destinationBuildParameters: swiftCommandState.productsBuildParameters,
                toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                graph: graph,
                fileSystem: fs,
                observabilityScope: observer.topScope
            )

            let buildProduct = try #require(try plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first)
            let arguments = try buildProduct.linkArguments()

            #expect(arguments.contains("/path/to/toolchain"))
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8660", relationship: .defect), // threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation
    )
    func toolsetOption() async throws {
        try withKnownIssue {
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
                targetArPath.pathString,
            ])

            for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath] {
                try fs.updatePermissions(path, isExecutable: true)
            }

            try fs.writeFileContents(
                "/toolset.json",
                string: """
                    {
                        "schemaVersion": "1.0",
                        "rootPath": "\(targetToolchainPath)"
                    }
                    """
            )

            let options = try GlobalOptions.parse(["--toolset", "/toolset.json"])
            let swiftCommandState = try SwiftCommandState.makeMockState(
                options: options,
                fileSystem: fs,
                environment: ["PATH": "/usr/bin"]
            )

            let hostToolchain = try swiftCommandState.getHostToolchain()
            let targetToolchain = try swiftCommandState.getTargetToolchain()

            #expect(targetToolchain.swiftSDK.toolset.rootPaths == [customTargetToolchain] + hostToolchain.swiftSDK.toolset.rootPaths)
            #expect(targetToolchain.swiftCompilerPath == targetSwiftcPath)
            #expect(targetToolchain.librarianPath == targetArPath)
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8660", relationship: .defect), // threw error \"toolchain is invalid: could not find CLI tool `swiftc` at any of these directories: [<AbsolutePath:\"\usr\bin\">]\", needs investigation
    )
    func multipleToolsets() async throws {
        try withKnownIssue {
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
                targetClangPath.pathString,
            ])

            for path in [hostSwiftcPath, hostArPath, targetSwiftcPath, targetArPath, targetClangPath] {
                try fs.updatePermissions(path, isExecutable: true)
            }

            try fs.writeFileContents(
                "/toolset1.json",
                string: """
                    {
                        "schemaVersion": "1.0",
                        "rootPath": "\(targetToolchainPath1)"
                    }
                    """
            )

            try fs.writeFileContents(
                "/toolset2.json",
                string: """
                    {
                        "schemaVersion": "1.0",
                        "rootPath": "\(targetToolchainPath2)"
                    }
                    """
            )

            let options = try GlobalOptions.parse([
                "--toolset", "/toolset1.json", "--toolset", "/toolset2.json",
            ])
            let swiftCommandState = try SwiftCommandState.makeMockState(
                options: options,
                fileSystem: fs,
                environment: ["PATH": "/usr/bin"]
            )

            let hostToolchain = try swiftCommandState.getHostToolchain()
            let targetToolchain = try swiftCommandState.getTargetToolchain()

            #expect(targetToolchain.swiftSDK.toolset.rootPaths == [customTargetToolchain2, customTargetToolchain1] + hostToolchain.swiftSDK.toolset.rootPaths)
            #expect(targetToolchain.swiftCompilerPath == targetSwiftcPath)
            try #expect(targetToolchain.getClangCompiler() == targetClangPath)
            #expect(targetToolchain.librarianPath == targetArPath)
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test
    func packagePathWithMissingFolder() async throws {
        try withTemporaryDirectory { fixturePath in
            let packagePath = fixturePath.appending(component: "Foo")
            let options = try GlobalOptions.parse(["--package-path", packagePath.pathString])

            do {
                let outputStream = BufferedOutputByteStream()
                #expect(throws: (any Error).self) {
                    try SwiftCommandState.makeMockState(outputStream: outputStream, options: options)
                }
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let tool = try SwiftCommandState.makeMockState(outputStream: outputStream, options: options, createPackagePath: true)
                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))
                let description = try #require(outputStream.bytes.validDescription)
                #expect(!description.contains("error:"))
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
            targetInfo: UserToolchain.mockTargetInfo,
            fileSystem: fileSystem,
            environment: environment
        )
    }
}
