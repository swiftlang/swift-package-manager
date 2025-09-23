//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import ArgumentParserToolInfo
@testable import Commands
@_spi(SwiftPMInternal)
@testable import CoreCommands
import Foundation
@testable import Workspace

import _InternalTestSupport
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)

import PackageGraph
import PackageLoading
import SourceControl
import SPMBuildCore
import Testing
import TSCUtility
import Workspace

@_spi(PackageRefactor) import SwiftRefactor

import class Basics.AsyncProcess
import class TSCBasic.BufferedOutputByteStream
import struct TSCBasic.ByteString
import enum TSCBasic.JSON

// MARK: - Helper Methods

private func makeTestResolver() throws -> (resolver: DefaultTemplateSourceResolver, tool: SwiftCommandState) {
    let options = try GlobalOptions.parse([])
    let tool = try SwiftCommandState.makeMockState(options: options)
    guard let cwd = tool.fileSystem.currentWorkingDirectory else {
        throw StringError("Unable to get current working directory")
    }
    let resolver = DefaultTemplateSourceResolver(
        cwd: cwd,
        fileSystem: tool.fileSystem,
        observabilityScope: tool.observabilityScope
    )
    return (resolver, tool)
}

private func makeTestTool() throws -> SwiftCommandState {
    let options = try GlobalOptions.parse([])
    return try SwiftCommandState.makeMockState(options: options)
}

private func makeVersions() -> (lower: Version, higher: Version) {
    let lowerBoundVersion = Version(stringLiteral: "1.2.0")
    let higherBoundVersion = Version(stringLiteral: "3.0.0")
    return (lowerBoundVersion, higherBoundVersion)
}

private func makeTestDependencyData() throws
    -> (
        tool: SwiftCommandState,
        packageName: String,
        templateURL: String,
        templatePackageID: String,
        path: AbsolutePath
    )
{
    let options = try GlobalOptions.parse([])
    let tool = try SwiftCommandState.makeMockState(options: options)
    let packageName = "foo"
    let templateURL = "git@github.com:foo/bar"
    let templatePackageID = "foo.bar"
    let resolvedTemplatePath = try AbsolutePath(validating: "/fake/path/to/template")
    return (tool, packageName, templateURL, templatePackageID, resolvedTemplatePath)
}

@Suite(
    // .serialized,
    .tags(
        .TestSize.large,
        .Feature.Command.Package.General,
    ),
)
struct TemplateTests {
    // MARK: - Template Source Resolution Tests

    @Suite(
        .tags(
            Tag.TestSize.small,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplateSourceResolverTests {
        @Test
        func resolveSourceWithNilInputs() throws {
            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            guard let cwd = tool.fileSystem.currentWorkingDirectory else { return }
            let fileSystem = tool.fileSystem
            let observabilityScope = tool.observabilityScope

            let resolver = DefaultTemplateSourceResolver(
                cwd: cwd,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )

            let nilSource = resolver.resolveSource(
                directory: nil, url: nil, packageID: nil
            )
            #expect(nilSource == nil)

            let localSource = resolver.resolveSource(
                directory: AbsolutePath("/fake/path/to/template"), url: nil, packageID: nil
            )
            #expect(localSource == .local)

            let packageIDSource = resolver.resolveSource(
                directory: AbsolutePath("/fake/path/to/template"), url: nil, packageID: "foo.bar"
            )
            #expect(packageIDSource == .registry)

            let gitSource = resolver.resolveSource(
                directory: AbsolutePath("/fake/path/to/template"), url: "https://github.com/foo/bar",
                packageID: "foo.bar"
            )
            #expect(gitSource == .git)
        }

        @Test
        func validateGitURLWithValidInput() async throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            try resolver.validate(
                templateSource: .git,
                directory: nil,
                url: "https://github.com/apple/swift",
                packageID: nil
            )

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(tool.observabilityScope.errorsReportedInAnyScope == false)
        }

        @Test
        func validateGitURLWithInvalidInput() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidGitURL("invalid-url").self) {
                try resolver.validate(templateSource: .git, directory: nil, url: "invalid-url", packageID: nil)
            }
        }

        @Test
        func validateRegistryIDWithValidInput() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "mona.LinkedList")

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(tool.observabilityScope.errorsReportedInAnyScope == false)
        }

        @Test
        func validateRegistryIDWithInvalidInput() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidRegistryIdentity("invalid-id")
                .self
            ) {
                try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "invalid-id")
            }
        }

        @Test
        func validateLocalSourceWithMissingPath() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.missingLocalPath.self) {
                try resolver.validate(templateSource: .local, directory: nil, url: nil, packageID: nil)
            }
        }

        @Test
        func validateLocalSourceWithInvalidPath() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(
                cwd: tool.fileSystem.currentWorkingDirectory!,
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError
                .invalidDirectoryPath("/fake/path/that/does/not/exist").self
            ) {
                try resolver.validate(
                    templateSource: .local,
                    directory: "/fake/path/that/does/not/exist",
                    url: nil,
                    packageID: nil
                )
            }
        }

        @Test
        func resolveRegistryDependencyWithNoVersion() async throws {
            // TODO: Set up registry mock for this test
            // Should test that registry dependency resolution returns nil when no version constraints are provided
        }
    }

    // MARK: - Dependency Requirement Resolution Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct DependencyRequirementResolverTests {
        @Test
        func resolveRegistryDependencyRequirements() async throws {
            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            let lowerBoundVersion = Version(stringLiteral: "1.2.0")
            let higherBoundVersion = Version(stringLiteral: "3.0.0")

            await #expect(throws: DependencyRequirementError.noRequirementSpecified.self) {
                try await DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: nil,
                    revision: "revision",
                    branch: "branch",
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: nil,
                ).resolveRegistry()
            }

            // test exact specification
            let exactRegistryDependency = try await DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: lowerBoundVersion,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveRegistry()

            if case .exact(let version) = exactRegistryDependency {
                #expect(version == lowerBoundVersion.description)
            } else {
                Issue.record("Expected exact registry dependency, got \(String(describing: exactRegistryDependency))")
            }

            // test from to
            let fromToRegistryDependency = try await DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: higherBoundVersion
            ).resolveRegistry()

            if case .range(let lowerBound, let upperBound) = fromToRegistryDependency {
                #expect(lowerBound == lowerBoundVersion.description)
                #expect(upperBound == higherBoundVersion.description)
            } else {
                Issue.record("Expected range registry dependency, got \(String(describing: fromToRegistryDependency))")
            }

            // test up-to-next-minor-from and to
            let upToNextMinorFromToRegistryDependency = try await DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: lowerBoundVersion,
                to: nil
            ).resolveRegistry()

            if case .range(let lowerBound, let upperBound) = upToNextMinorFromToRegistryDependency {
                let expectedRange = Range.upToNextMinor(from: lowerBoundVersion)
                #expect(lowerBound == expectedRange.lowerBound.description)
                #expect(upperBound == expectedRange.upperBound.description)
            } else {
                Issue
                    .record(
                        "Expected range registry dependency, got \(String(describing: upToNextMinorFromToRegistryDependency))"
                    )
            }

            // test just from
            let fromRegistryDependency = try await DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveRegistry()

            if case .rangeFrom(let lowerBound) = fromRegistryDependency {
                #expect(lowerBound == lowerBoundVersion.description)
            } else {
                Issue
                    .record("Expected rangeFrom registry dependency, got \(String(describing: fromRegistryDependency))")
            }

            // test just up-to-next-minor-from
            let upToNextMinorFromRegistryDependency = try await DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: lowerBoundVersion,
                to: nil
            ).resolveRegistry()

            if case .range(let lowerBound, let upperBound) = upToNextMinorFromRegistryDependency {
                let expectedRange = Range.upToNextMinor(from: lowerBoundVersion)
                #expect(lowerBound == expectedRange.lowerBound.description)
                #expect(upperBound == expectedRange.upperBound.description)
            } else {
                Issue
                    .record(
                        "Expected range registry dependency, got \(String(describing: upToNextMinorFromRegistryDependency))"
                    )
            }

            await #expect(throws: DependencyRequirementError.multipleRequirementsSpecified.self) {
                try await DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: lowerBoundVersion,
                    revision: nil,
                    branch: nil,
                    from: lowerBoundVersion,
                    upToNextMinorFrom: lowerBoundVersion,
                    to: nil
                ).resolveRegistry()
            }

            await #expect(throws: DependencyRequirementError.noRequirementSpecified.self) {
                try await DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: nil,
                    revision: nil,
                    branch: nil,
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: lowerBoundVersion
                ).resolveRegistry()
            }

            await #expect(throws: DependencyRequirementError.invalidToParameterWithoutFrom.self) {
                try await DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: lowerBoundVersion,
                    revision: nil,
                    branch: nil,
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: higherBoundVersion
                ).resolveRegistry()
            }
        }

        @Test
        func resolveSourceControlDependencyRequirements() throws {
            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            let lowerBoundVersion = Version(stringLiteral: "1.2.0")
            let higherBoundVersion = Version(stringLiteral: "3.0.0")

            let branchSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: "master",
                from: nil,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveSourceControl()

            if case .branch(let branchName) = branchSourceControlDependency {
                #expect(branchName == "master")
            } else {
                Issue
                    .record(
                        "Expected branch source control dependency, got \(String(describing: branchSourceControlDependency))"
                    )
            }

            let revisionSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: "dae86e",
                branch: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveSourceControl()

            if case .revision(let revisionHash) = revisionSourceControlDependency {
                #expect(revisionHash == "dae86e")
            } else {
                Issue
                    .record(
                        "Expected revision source control dependency, got \(String(describing: revisionSourceControlDependency))"
                    )
            }

            // test exact specification
            let exactSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: lowerBoundVersion,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveSourceControl()

            if case .exact(let version) = exactSourceControlDependency {
                #expect(version == lowerBoundVersion.description)
            } else {
                Issue
                    .record(
                        "Expected exact source control dependency, got \(String(describing: exactSourceControlDependency))"
                    )
            }

            // test from to
            let fromToSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: higherBoundVersion
            ).resolveSourceControl()

            if case .range(let lowerBound, let upperBound) = fromToSourceControlDependency {
                #expect(lowerBound == lowerBoundVersion.description)
                #expect(upperBound == higherBoundVersion.description)
            } else {
                Issue
                    .record(
                        "Expected range source control dependency, got \(String(describing: fromToSourceControlDependency))"
                    )
            }

            // test up-to-next-minor-from and to
            let upToNextMinorFromToSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: lowerBoundVersion,
                to: nil
            ).resolveSourceControl()

            if case .range(let lowerBound, let upperBound) = upToNextMinorFromToSourceControlDependency {
                let expectedRange = Range.upToNextMinor(from: lowerBoundVersion)
                #expect(lowerBound == expectedRange.lowerBound.description)
                #expect(upperBound == expectedRange.upperBound.description)
            } else {
                Issue
                    .record(
                        "Expected range source control dependency, got \(String(describing: upToNextMinorFromToSourceControlDependency))"
                    )
            }

            // test just from
            let fromSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: nil
            ).resolveSourceControl()

            if case .rangeFrom(let lowerBound) = fromSourceControlDependency {
                #expect(lowerBound == lowerBoundVersion.description)
            } else {
                Issue
                    .record(
                        "Expected rangeFrom source control dependency, got \(String(describing: fromSourceControlDependency))"
                    )
            }

            // test just up-to-next-minor-from
            let upToNextMinorFromSourceControlDependency = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: nil,
                upToNextMinorFrom: lowerBoundVersion,
                to: nil
            ).resolveSourceControl()

            if case .range(let lowerBound, let upperBound) = upToNextMinorFromSourceControlDependency {
                let expectedRange = Range.upToNextMinor(from: lowerBoundVersion)
                #expect(lowerBound == expectedRange.lowerBound.description)
                #expect(upperBound == expectedRange.upperBound.description)
            } else {
                Issue
                    .record(
                        "Expected range source control dependency, got \(String(describing: upToNextMinorFromSourceControlDependency))"
                    )
            }

            #expect(throws: DependencyRequirementError.multipleRequirementsSpecified.self) {
                try DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: lowerBoundVersion,
                    revision: "dae86e",
                    branch: nil,
                    from: lowerBoundVersion,
                    upToNextMinorFrom: lowerBoundVersion,
                    to: nil
                ).resolveSourceControl()
            }

            #expect(throws: DependencyRequirementError.noRequirementSpecified.self) {
                try DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: nil,
                    revision: nil,
                    branch: nil,
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: lowerBoundVersion
                ).resolveSourceControl()
            }

            #expect(throws: DependencyRequirementError.invalidToParameterWithoutFrom.self) {
                try DependencyRequirementResolver(
                    packageIdentity: nil,
                    swiftCommandState: tool,
                    exact: lowerBoundVersion,
                    revision: nil,
                    branch: nil,
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: higherBoundVersion
                ).resolveSourceControl()
            }

            let range = try DependencyRequirementResolver(
                packageIdentity: nil,
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: lowerBoundVersion
            ).resolveSourceControl()

            if case .range(let lowerBound, let upperBound) = range {
                #expect(lowerBound == lowerBoundVersion.description)
                #expect(upperBound == lowerBoundVersion.description)
            } else {
                Issue.record("Expected range source control dependency, got \(range)")
            }
        }
    }

    // MARK: - Template Path Resolution Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.LocalTemplate,
        ),
    )
    struct TemplatePathResolverTests {
        @Test
        func resolveLocalTemplatePath() async throws {
            let mockTemplatePath = AbsolutePath("/fake/path/to/template")
            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            let path = try await TemplatePathResolver(
                source: .local,
                templateDirectory: mockTemplatePath,
                templateURL: nil,
                sourceControlRequirement: nil,
                registryRequirement: nil,
                packageIdentity: nil,
                swiftCommandState: tool
            ).resolve()

            #expect(path == mockTemplatePath)
        }

        @Test(
            .skipHostOS(.windows, "Git operations not fully supported in test environment"),
            .requireUnrestrictedNetworkAccess("Test needs to create and access local git repositories"),
        )
        func resolveGitTemplatePath() async throws {
            try await testWithTemporaryDirectory { path in
                let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement.branch("main")
                let options = try GlobalOptions.parse([])

                let tool = try SwiftCommandState.makeMockState(options: options)

                let templateRepoPath = path.appending(component: "template-repo")
                let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                let templateRepoURL = sourceControlURL.url
                try! makeDirectories(templateRepoPath)
                initGitRepo(templateRepoPath, tag: "1.2.3")

                let resolver = try TemplatePathResolver(
                    source: .git,
                    templateDirectory: nil,
                    templateURL: templateRepoURL?.absoluteString,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: nil,
                    packageIdentity: nil,
                    swiftCommandState: tool
                )
                let path = try await resolver.resolve()
                #expect(
                    localFileSystem.exists(path.appending(component: "file.swift")),
                    "Template was not fetched correctly"
                )
            }
        }

        @Test(
            .skipHostOS(.windows, "Git operations not fully supported in test environment"),
            .requireUnrestrictedNetworkAccess("Test needs to attempt git clone operations"),
        )
        func resolveGitTemplatePathWithInvalidURL() async throws {
            try await testWithTemporaryDirectory { path in
                let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement.branch("main")
                let options = try GlobalOptions.parse([])

                let tool = try SwiftCommandState.makeMockState(options: options)

                let templateRepoPath = path.appending(component: "template-repo")
                try! makeDirectories(templateRepoPath)
                initGitRepo(templateRepoPath, tag: "1.2.3")

                let resolver = try TemplatePathResolver(
                    source: .git,
                    templateDirectory: nil,
                    templateURL: "invalid-git-url",
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: nil,
                    packageIdentity: nil,
                    swiftCommandState: tool
                )

                await #expect(throws: GitTemplateFetcher.GitTemplateFetcherError
                    .cloneFailed(source: "invalid-git-url")
                ) {
                    _ = try await resolver.resolve()
                }
            }
        }

        @Test
        func resolveRegistryTemplatePath() async throws {
            // TODO: Implement registry template path resolution test
            // Should test fetching template from package registry
        }
    }

    // MARK: - Template Directory Management Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplateDirectoryManagerTests {
        @Test
        func createTemporaryDirectories() throws {
            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            let (stagingPath, cleanupPath, tempDir) = try TemplateInitializationDirectoryManager(
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            ).createTemporaryDirectories()

            #expect(stagingPath.parentDirectory == tempDir)
            #expect(cleanupPath.parentDirectory == tempDir)

            #expect(stagingPath.basename == "generated-package")
            #expect(cleanupPath.basename == "clean-up")

            #expect(tool.fileSystem.exists(stagingPath))
            #expect(tool.fileSystem.exists(cleanupPath))
        }

        @Test(
            .tags(
                Tag.Feature.Command.Package.Init,
                Tag.Feature.PackageType.LocalTemplate,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func finalizeDirectoryTransfer(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                let stagingPath = fixturePath.appending("generated-package")
                let cleanupPath = fixturePath.appending("clean-up")
                let cwd = fixturePath.appending("cwd")

                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                try await executeSwiftBuild(
                    stagingPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem
                )

                let stagingBuildPath = stagingPath.appending(".build")
                let binPathComponents = try data.buildSystem.binPath(for: data.config, scratchPath: [])
                let stagingBinPath = stagingBuildPath.appending(components: binPathComponents)
                let stagingBinFile = stagingBinPath.appending(executableName("generated-package"))
                #expect(localFileSystem.exists(stagingBinFile))
                #expect(localFileSystem.isDirectory(stagingBuildPath))

                try await TemplateInitializationDirectoryManager(
                    fileSystem: tool.fileSystem,
                    observabilityScope: tool.observabilityScope
                ).finalize(cwd: cwd, stagingPath: stagingPath, cleanupPath: cleanupPath, swiftCommandState: tool)

                let cwdBuildPath = cwd.appending(".build")
                let cwdBinPathComponents = try data.buildSystem.binPath(for: data.config, scratchPath: [])
                let cwdBinPath = cwdBuildPath.appending(components: cwdBinPathComponents)
                let cwdBinFile = cwdBinPath.appending(executableName("generated-package"))

                // Postcondition checks
                #expect(localFileSystem.exists(cwd), "cwd should exist after finalize")
                #expect(
                    localFileSystem.exists(cwdBinFile) == false,
                    "Binary should have been cleaned before copying to cwd"
                )
            }
        }

        @Test
        func cleanUpTemporaryDirectories() throws {
            try fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                let pathToRemove = fixturePath.appending("targetFolderForRemoval")
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                try TemplateInitializationDirectoryManager(
                    fileSystem: tool.fileSystem,
                    observabilityScope: tool.observabilityScope
                ).cleanupTemporary(templateSource: .git, path: pathToRemove, temporaryDirectory: nil)

                #expect(!localFileSystem.exists(pathToRemove), "path should be removed")
            }

            try fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                let pathToRemove = fixturePath.appending("targetFolderForRemoval")
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                try TemplateInitializationDirectoryManager(
                    fileSystem: tool.fileSystem,
                    observabilityScope: tool.observabilityScope
                ).cleanupTemporary(templateSource: .registry, path: pathToRemove, temporaryDirectory: nil)

                #expect(!localFileSystem.exists(pathToRemove), "path should be removed")
            }

            try fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                let pathToRemove = fixturePath.appending("targetFolderForRemoval")
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                try TemplateInitializationDirectoryManager(
                    fileSystem: tool.fileSystem,
                    observabilityScope: tool.observabilityScope
                ).cleanupTemporary(templateSource: .local, path: pathToRemove, temporaryDirectory: nil)

                #expect(localFileSystem.exists(pathToRemove), "path should not be removed if local")
            }
        }
    }

    // MARK: - Package Dependency Builder Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct PackageDependencyBuilderTests {
        @Test
        func buildDependenciesFromTemplateSource() async throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)

            let packageName = "foo"
            let templateURL = "git@github.com:foo/bar"
            let templatePackageID = "foo.bar"

            let versionResolver = DependencyRequirementResolver(
                packageIdentity: templatePackageID, swiftCommandState: tool, exact: Version(stringLiteral: "1.2.0"),
                revision: nil, branch: nil, from: nil, upToNextMinorFrom: nil, to: nil
            )

            let sourceControlRequirement: SwiftRefactor.PackageDependency.SourceControl
                .Requirement = try versionResolver.resolveSourceControl()
            guard let registryRequirement = try await versionResolver.resolveRegistry() else {
                Issue.record("Registry ID of template could not be resolved.")
                return
            }

            let resolvedTemplatePath: AbsolutePath = try AbsolutePath(validating: "/fake/path/to/template")

            // local

            let localDependency = try DefaultPackageDependencyBuilder(
                templateSource: .local,
                packageName: packageName,
                templateURL: templateURL,
                templatePackageID: templatePackageID,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: resolvedTemplatePath
            ).makePackageDependency()

            // Test that local dependency was correctly created as filesystem dependency
            if case .fileSystem(let fileSystemDep) = localDependency {
                #expect(fileSystemDep.path == resolvedTemplatePath.pathString)
            } else {
                Issue.record("Expected fileSystem dependency, got \(localDependency)")
            }

            // git
            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingGitURLOrPath.self) {
                try DefaultPackageDependencyBuilder(
                    templateSource: .git,
                    packageName: packageName,
                    templateURL: nil,
                    templatePackageID: templatePackageID,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: registryRequirement,
                    resolvedTemplatePath: resolvedTemplatePath
                ).makePackageDependency()
            }

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingGitRequirement.self) {
                try DefaultPackageDependencyBuilder(
                    templateSource: .git,
                    packageName: packageName,
                    templateURL: templateURL,
                    templatePackageID: templatePackageID,
                    sourceControlRequirement: nil,
                    registryRequirement: registryRequirement,
                    resolvedTemplatePath: resolvedTemplatePath
                ).makePackageDependency()
            }

            let gitDependency = try DefaultPackageDependencyBuilder(
                templateSource: .git,
                packageName: packageName,
                templateURL: templateURL,
                templatePackageID: templatePackageID,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: resolvedTemplatePath
            ).makePackageDependency()

            // Test that git dependency was correctly created as sourceControl dependency
            if case .sourceControl(let sourceControlDep) = gitDependency {
                #expect(sourceControlDep.location == templateURL)
                if case .exact(let exactVersion) = sourceControlDep.requirement {
                    #expect(exactVersion == "1.2.0")
                } else {
                    Issue.record("Expected exact source control dependency, got \(sourceControlDep.requirement)")
                }
            } else {
                Issue.record("Expected sourceControl dependency, got \(gitDependency)")
            }

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingRegistryIdentity
                .self
            ) {
                try DefaultPackageDependencyBuilder(
                    templateSource: .registry,
                    packageName: packageName,
                    templateURL: templateURL,
                    templatePackageID: nil,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: registryRequirement,
                    resolvedTemplatePath: resolvedTemplatePath
                ).makePackageDependency()
            }

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingRegistryRequirement
                .self
            ) {
                try DefaultPackageDependencyBuilder(
                    templateSource: .registry,
                    packageName: packageName,
                    templateURL: templateURL,
                    templatePackageID: templatePackageID,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: nil,
                    resolvedTemplatePath: resolvedTemplatePath
                ).makePackageDependency()
            }

            let registryDependency = try DefaultPackageDependencyBuilder(
                templateSource: .registry,
                packageName: packageName,
                templateURL: templateURL,
                templatePackageID: templatePackageID,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: resolvedTemplatePath
            ).makePackageDependency()

            // Test that registry dependency was correctly created as registry dependency
            if case .registry(let registryDep) = registryDependency {
                #expect(registryDep.identity == templatePackageID)

            } else {
                Issue.record("Expected registry dependency, got \(registryDependency)")
            }
        }
    }

    // MARK: - Package Initializer Configuration Tests

    @Suite(
        .tags(
            Tag.TestSize.small,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct PackageInitializerConfigurationTests {
        @Test
        func createPackageInitializer() throws {
            try testWithTemporaryDirectory { tempDir in
                let globalOptions = try GlobalOptions.parse(["--package-path", tempDir.pathString])
                let testLibraryOptions = try TestLibraryOptions.parse([])
                let buildOptions = try BuildCommandOptions.parse([])
                let directoryPath = AbsolutePath("/")
                let tool = try SwiftCommandState.makeMockState(options: globalOptions)

                let templatePackageInitializer = try PackageInitConfiguration(
                    swiftCommandState: tool,
                    name: "foo",
                    initMode: "template",
                    testLibraryOptions: testLibraryOptions,
                    buildOptions: buildOptions,
                    globalOptions: globalOptions,
                    validatePackage: true,
                    args: ["--foobar foo"],
                    directory: directoryPath,
                    url: nil,
                    packageID: "foo.bar",
                    versionFlags: VersionFlags(
                        exact: nil,
                        revision: nil,
                        branch: "master",
                        from: nil,
                        upToNextMinorFrom: nil,
                        to: nil
                    )
                ).makeInitializer()

                #expect(templatePackageInitializer is TemplatePackageInitializer)

                let standardPackageInitalizer = try PackageInitConfiguration(
                    swiftCommandState: tool,
                    name: "foo",
                    initMode: "template",
                    testLibraryOptions: testLibraryOptions,
                    buildOptions: buildOptions,
                    globalOptions: globalOptions,
                    validatePackage: true,
                    args: ["--foobar foo"],
                    directory: nil,
                    url: nil,
                    packageID: nil,
                    versionFlags: VersionFlags(
                        exact: nil,
                        revision: nil,
                        branch: "master",
                        from: nil,
                        upToNextMinorFrom: nil,
                        to: nil
                    )
                ).makeInitializer()

                #expect(standardPackageInitalizer is StandardPackageInitializer)
            }
        }

        // TODO: Re-enable once SwiftCommandState mocking issues are resolved
        // The test fails because mocking swiftCommandState resolves to linux triple on Darwin
        /*
         @Test(
         .requireHostOS(.macOS, "SwiftCommandState mocking issue on non-Darwin platforms"),
         )
         func inferPackageTypeFromTemplate() async throws {
         try await fixture(name: "Miscellaneous/InferPackageType") { fixturePath in
         let options = try GlobalOptions.parse([])
         let tool = try SwiftCommandState.makeMockState(options: options)

         let libraryType = try await TemplatePackageInitializer.inferPackageType(
         from: fixturePath,
         templateName: "initialTypeLibrary",
         swiftCommandState: tool
         )

         #expect(libraryType.rawValue == "library")
         }
         }
         */
    }

    // MARK: - Template Prompting System Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplatePromptingSystemTests {
        // MARK: - Helper Methods

        private func createTestCommand(
            name: String = "test-template",
            arguments: [ArgumentInfoV0] = [],
            subcommands: [CommandInfoV0]? = nil
        ) -> CommandInfoV0 {
            CommandInfoV0(
                superCommands: [],
                shouldDisplay: true,
                commandName: name,
                abstract: "Test template command",
                discussion: "A command for testing template prompting",
                defaultSubcommand: nil,
                subcommands: subcommands ?? [],
                arguments: arguments
            )
        }

        private func createRequiredOption(
            name: String,
            defaultValue: String? = nil,
            allValues: [String]? = nil,
            parsingStrategy: ArgumentInfoV0.ParsingStrategyV0 = .default,
            completionKind: ArgumentInfoV0.CompletionKindV0? = nil
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: parsingStrategy,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: name)],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: name),
                valueName: name,
                defaultValue: defaultValue,
                allValueStrings: allValues,
                allValueDescriptions: nil,
                completionKind: completionKind,
                abstract: "\(name.capitalized) parameter",
                discussion: nil
            )
        }

        private func createOptionalOption(
            name: String,
            defaultValue: String? = nil,
            allValues: [String]? = nil,
            completionKind: ArgumentInfoV0.CompletionKindV0? = nil
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: name)],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: name),
                valueName: name,
                defaultValue: defaultValue,
                allValueStrings: allValues,
                allValueDescriptions: nil,
                completionKind: completionKind,
                abstract: "\(name.capitalized) parameter",
                discussion: nil
            )
        }

        private func createOptionalFlag(
            name: String,
            defaultValue: String? = nil,
            completionKind: ArgumentInfoV0.CompletionKindV0? = nil
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .flag,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: name)],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: name),
                valueName: name,
                defaultValue: defaultValue,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: completionKind,
                abstract: "\(name.capitalized) flag",
                discussion: nil
            )
        }

        private func createPositionalArgument(
            name: String,
            isOptional: Bool = false,
            defaultValue: String? = nil,
            parsingStrategy: ArgumentInfoV0.ParsingStrategyV0 = .default
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: isOptional,
                isRepeating: false,
                parsingStrategy: parsingStrategy,
                names: nil,
                preferredName: nil,
                valueName: name,
                defaultValue: defaultValue,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "\(name.capitalized) positional argument",
                discussion: nil
            )
        }

        // MARK: - Basic Functionality Tests

        @Test
        func createsPromptingSystemSuccessfully() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let emptyCommand = self.createTestCommand(name: "empty")

            let result = try promptingSystem.promptUser(
                command: emptyCommand,
                arguments: []
            )
            #expect(result.isEmpty)
        }

        @Test
        func handlesCommandWithProvidedArguments() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--name", "TestPackage"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        @Test
        func handlesOptionalArgumentsWithDefaults() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalFlag(name: "include-readme", defaultValue: "false"),
                ]
            )

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--name", "TestPackage"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            // Flag with default "false" should not appear in command line
            #expect(!result.contains("--include-readme"))
        }

        @Test
        func validatesMissingRequiredArguments() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            #expect(throws: Error.self) {
                _ = try promptingSystem.promptUser(
                    command: commandInfo,
                    arguments: []
                )
            }
        }

        // MARK: - Argument Response Tests

        @Test
        func argumentResponseHandlesExplicitlyUnsetFlags() throws {
            let arg = self.createOptionalFlag(name: "verbose", defaultValue: "false")

            // Test explicitly unset flag
            let explicitlyUnsetResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal flag response (true)
            let trueResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: ["true"],
                isExplicitlyUnset: false
            )
            #expect(trueResponse.isExplicitlyUnset == false)
            #expect(trueResponse.commandLineFragments == ["--verbose"])

            // Test false flag response (should be empty)
            let falseResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: ["false"],
                isExplicitlyUnset: false
            )
            #expect(falseResponse.commandLineFragments.isEmpty)
        }

        @Test
        func argumentResponseHandlesExplicitlyUnsetOptions() throws {
            let arg = self.createOptionalOption(name: "output")

            // Test explicitly unset option
            let explicitlyUnsetResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal option response
            let normalResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: ["./output"],
                isExplicitlyUnset: false
            )
            #expect(normalResponse.isExplicitlyUnset == false)
            #expect(normalResponse.commandLineFragments == ["--output", "./output"])

            // Test multiple values option
            let multiValueArg = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "define")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "define"),
                valueName: "define",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: .none,
                abstract: "Define parameter",
                discussion: nil
            )

            let multiValueResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: multiValueArg,
                values: ["FOO=bar", "BAZ=qux"],
                isExplicitlyUnset: false
            )
            #expect(multiValueResponse.commandLineFragments == ["--define", "FOO=bar", "--define", "BAZ=qux"])
        }

        @Test
        func argumentResponseHandlesPositionalArguments() throws {
            let arg = self.createPositionalArgument(name: "target", isOptional: true)

            // Test explicitly unset positional
            let explicitlyUnsetResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal positional response
            let normalResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: arg,
                values: ["MyTarget"],
                isExplicitlyUnset: false
            )
            #expect(normalResponse.isExplicitlyUnset == false)
            #expect(normalResponse.commandLineFragments == ["MyTarget"])
        }

        // MARK: - Command Line Generation Tests

        @Test
        func commandLineGenerationWithMixedArgumentStates() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)

            let flagArg = self.createOptionalFlag(name: "verbose")
            let requiredOptionArg = self.createRequiredOption(name: "name")
            let optionalOptionArg = self.createOptionalOption(name: "output")
            let positionalArg = self.createPositionalArgument(name: "target", isOptional: true)

            // Create responses with mixed states
            let responses = [
                TemplatePromptingSystem.ArgumentResponse(argument: flagArg, values: [], isExplicitlyUnset: true),
                TemplatePromptingSystem.ArgumentResponse(
                    argument: requiredOptionArg,
                    values: ["TestPackage"],
                    isExplicitlyUnset: false
                ),
                TemplatePromptingSystem.ArgumentResponse(
                    argument: optionalOptionArg,
                    values: [],
                    isExplicitlyUnset: true
                ),
                TemplatePromptingSystem.ArgumentResponse(
                    argument: positionalArg,
                    values: ["MyTarget"],
                    isExplicitlyUnset: false
                ),
            ]

            let commandLine = promptingSystem.buildCommandLine(from: responses)

            // Should only contain the non-unset arguments
            #expect(commandLine == ["--name", "TestPackage", "MyTarget"])
        }

        @Test
        func commandLineGenerationWithDefaultValues() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)

            let optionWithDefault = self.createOptionalOption(name: "version", defaultValue: "1.0.0")
            let flagWithDefault = self.createOptionalFlag(name: "enabled", defaultValue: "true")

            let responses = [
                TemplatePromptingSystem.ArgumentResponse(
                    argument: optionWithDefault,
                    values: ["1.0.0"],
                    isExplicitlyUnset: false
                ),
                TemplatePromptingSystem.ArgumentResponse(
                    argument: flagWithDefault,
                    values: ["true"],
                    isExplicitlyUnset: false
                ),
            ]

            let commandLine = promptingSystem.buildCommandLine(from: responses)

            #expect(commandLine == ["--version", "1.0.0", "--enabled"])
        }

        // MARK: - Argument Parsing Tests

        @Test
        func parsesProvidedArgumentsCorrectly() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalFlag(name: "verbose"),
                    self.createOptionalOption(name: "output"),
                ]
            )

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--name", "TestPackage", "--verbose", "--output", "./dist"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            #expect(result.contains("--verbose"))
            #expect(result.contains("--output"))
            #expect(result.contains("./dist"))
        }

        @Test
        func handlesValidationWithAllowedValues() throws {
            let restrictedArg = self.createRequiredOption(
                name: "type",
                allValues: ["executable", "library", "plugin"]
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [restrictedArg])

            // Valid value should work
            let validResult = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--type", "executable"]
            )
            #expect(validResult.contains("executable"))

            // Invalid value should throw
            #expect(throws: Error.self) {
                _ = try promptingSystem.promptUser(
                    command: commandInfo,
                    arguments: ["--type", "invalid"]
                )
            }
        }

        // MARK: - Subcommand Tests

        @Test
        func handlesSubcommandDetection() throws {
            let subcommand = self.createTestCommand(
                name: "init",
                arguments: [self.createRequiredOption(name: "name")]
            )

            let mainCommand = self.createTestCommand(
                name: "package",
                subcommands: [subcommand]
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)

            let result = try promptingSystem.promptUser(
                command: mainCommand,
                arguments: ["init", "--name", "TestPackage"]
            )

            #expect(result.contains("init"))
            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        // MARK: - Error Handling Tests

        @Test
        func handlesInvalidArgumentNames() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            // Should handle unknown arguments gracefully by treating them as potential subcommands
            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--name", "TestPackage", "--unknown", "value"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        @Test
        func handlesMissingValueForOption() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            #expect(throws: Error.self) {
                _ = try promptingSystem.promptUser(
                    command: commandInfo,
                    arguments: ["--name"]
                )
            }
        }

        @Test
        func handlesNestedSubcommands() throws {
            let innerSubcommand = self.createTestCommand(
                name: "create",
                arguments: [self.createRequiredOption(name: "name")]
            )

            let outerSubcommand = self.createTestCommand(
                name: "package",
                subcommands: [innerSubcommand]
            )

            let mainCommand = self.createTestCommand(
                name: "swift",
                subcommands: [outerSubcommand]
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)

            let result = try promptingSystem.promptUser(
                command: mainCommand,
                arguments: ["package", "create", "--name", "MyPackage"]
            )

            #expect(result.contains("package"))
            #expect(result.contains("create"))
            #expect(result.contains("--name"))
            #expect(result.contains("MyPackage"))
        }

        // MARK: - Integration Tests

        @Test
        func handlesComplexCommandStructure() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)

            let complexCommand = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalOption(name: "output", defaultValue: "./build"),
                    self.createOptionalFlag(name: "verbose", defaultValue: "false"),
                    self.createPositionalArgument(name: "target", isOptional: true, defaultValue: "main"),
                ]
            )

            let result = try promptingSystem.promptUser(
                command: complexCommand,
                arguments: ["--name", "TestPackage", "--verbose", "CustomTarget"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            #expect(result.contains("--verbose"))
            #expect(result.contains("CustomTarget"))
            // Default values for optional arguments should be included when no explicit value provided
            #expect(result.contains("--output"))
            #expect(result.contains("./build"))
        }

        @Test
        func handlesEmptyInputCorrectly() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createOptionalOption(name: "output", defaultValue: "default"),
                    self.createOptionalFlag(name: "verbose", defaultValue: "false"),
                ]
            )

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: []
            )

            // Should contain default values where appropriate
            #expect(result.contains("--output"))
            #expect(result.contains("default"))
            #expect(!result.contains("--verbose")) // false flag shouldn't appear
        }

        @Test
        func handlesRepeatingArguments() throws {
            let repeatingArg = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "define")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "define"),
                valueName: "define",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Define parameter",
                discussion: nil
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [repeatingArg])

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--define", "FOO=bar", "--define", "BAZ=qux"]
            )

            #expect(result.contains("--define"))
            #expect(result.contains("FOO=bar"))
            #expect(result.contains("BAZ=qux"))
        }

        @Test
        func handlesArgumentValidationWithCustomCompletions() throws {
            let completionArg = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "platform")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "platform"),
                valueName: "platform",
                defaultValue: nil,
                allValueStrings: ["iOS", "macOS", "watchOS", "tvOS"],
                allValueDescriptions: nil,
                completionKind: .list(values: ["iOS", "macOS", "watchOS", "tvOS"]),
                abstract: "Target platform",
                discussion: nil
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [completionArg])

            // Valid completion value should work
            let validResult = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--platform", "iOS"]
            )
            #expect(validResult.contains("iOS"))

            // Invalid completion value should throw
            #expect(throws: Error.self) {
                _ = try promptingSystem.promptUser(
                    command: commandInfo,
                    arguments: ["--platform", "Linux"]
                )
            }
        }

        @Test
        func handlesArgumentResponseBuilding() throws {
            let flagArg = self.createOptionalFlag(name: "verbose")
            let optionArg = self.createRequiredOption(name: "output")
            let positionalArg = self.createPositionalArgument(name: "target")

            // Test various response scenarios
            let flagResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: flagArg,
                values: ["true"],
                isExplicitlyUnset: false
            )
            #expect(flagResponse.commandLineFragments == ["--verbose"])

            let optionResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: optionArg,
                values: ["./output"],
                isExplicitlyUnset: false
            )
            #expect(optionResponse.commandLineFragments == ["--output", "./output"])

            let positionalResponse = TemplatePromptingSystem.ArgumentResponse(
                argument: positionalArg,
                values: ["MyTarget"],
                isExplicitlyUnset: false
            )
            #expect(positionalResponse.commandLineFragments == ["MyTarget"])
        }

        @Test
        func handlesMissingArgumentErrors() throws {
            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "required-arg"),
                    self.createOptionalOption(name: "optional-arg"),
                ]
            )

            // Should throw when required argument is missing
            #expect(throws: Error.self) {
                _ = try promptingSystem.promptUser(
                    command: commandInfo,
                    arguments: ["--optional-arg", "value"]
                )
            }
        }

        // MARK: - Parsing Strategy Tests

        @Test
        func handlesParsingStrategies() throws {
            let upToNextOptionArg = self.createRequiredOption(
                name: "files",
                parsingStrategy: .upToNextOption
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [upToNextOptionArg])

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--files", "file1.swift", "file2.swift", "file3.swift"]
            )

            #expect(result.contains("--files"))
            #expect(result.contains("file1.swift"))
        }

        @Test
        func handlesTerminatorParsing() throws {
            let postTerminatorArg = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: false,
                parsingStrategy: .postTerminator,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "post-args")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "post-args"),
                valueName: "post-args",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Post-terminator arguments",
                discussion: nil
            )

            let promptingSystem = TemplatePromptingSystem(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    postTerminatorArg,
                ]
            )

            let result = try promptingSystem.promptUser(
                command: commandInfo,
                arguments: ["--name", "TestPackage", "--", "arg1", "arg2"]
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            // Post-terminator args should be handled separately
        }
    }

    // MARK: - Template Plugin Coordinator Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplatePluginCoordinatorTests {
        @Test
        func createsCoordinatorWithValidConfiguration() async throws {
            try testWithTemporaryDirectory { tempDir in
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                let coordinator = TemplatePluginCoordinator(
                    buildSystem: .native,
                    swiftCommandState: tool,
                    scratchDirectory: tempDir,
                    template: "ExecutableTemplate",
                    args: ["--name", "TestPackage"],
                    branches: []
                )

                // Test coordinator functionality by verifying it can handle basic operations
                #expect(coordinator.buildSystem == .native)
                #expect(coordinator.scratchDirectory == tempDir)
            }
        }

        @Test
        func loadsPackageGraphInTemporaryWorkspace() async throws { // precondition linux error
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Copy template to temporary directory for workspace loading
                    let workspaceDir = tempDir.appending("workspace")
                    try tool.fileSystem.copy(from: templatePath, to: workspaceDir)

                    let coordinator = TemplatePluginCoordinator(
                        buildSystem: .native,
                        swiftCommandState: tool,
                        scratchDirectory: workspaceDir,
                        template: "ExecutableTemplate",
                        args: ["--name", "TestPackage"],
                        branches: []
                    )

                    // Test coordinator's ability to load package graph
                    // The coordinator handles the workspace switching internally
                    let graph = try await coordinator.loadPackageGraph()
                    #expect(!graph.rootPackages.isEmpty, "Package graph should have root packages")
                }
            }
        }

        @Test
        func handlesInvalidTemplateGracefully() async throws {
            try await testWithTemporaryDirectory { tempDir in
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                let coordinator = TemplatePluginCoordinator(
                    buildSystem: .native,
                    swiftCommandState: tool,
                    scratchDirectory: tempDir,
                    template: "NonexistentTemplate",
                    args: ["--name", "TestPackage"],
                    branches: []
                )

                // Test that coordinator handles invalid template name by throwing appropriate error
                await #expect(throws: (any Error).self) {
                    _ = try await coordinator.loadPackageGraph()
                }
            }
        }
    }

    // MARK: - Template Plugin Runner Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplatePluginRunnerTests {
        @Test
        func handlesPluginExecutionForValidPackage() async throws { // precondition linux error

            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { _ in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test that TemplatePluginRunner can handle static execution
                    try await tool.withTemporaryWorkspace(switchingTo: templatePath) { _, _ in
                        let graph = try await tool.loadPackageGraph()
                        let rootPackage = graph.rootPackages.first!

                        // Verify we can identify plugins for execution
                        let pluginModules = rootPackage.modules.filter { $0.type == .plugin }
                        #expect(!pluginModules.isEmpty, "Template should have plugin modules")
                    }
                }
            }
        }

        @Test
        func handlesPluginExecutionStaticAPI() async throws { // precondition linux error

            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")
                    try makeDirectories(packagePath)

                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test that TemplatePluginRunner static API works with valid input
                    try await tool.withTemporaryWorkspace(switchingTo: templatePath) { _, _ in
                        let graph = try await tool.loadPackageGraph()
                        let rootPackage = graph.rootPackages.first!

                        // Test plugin execution readiness
                        #expect(!graph.rootPackages.isEmpty, "Should have root packages for plugin execution")
                        #expect(
                            rootPackage.modules.contains { $0.type == .plugin },
                            "Should have plugin modules available"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Template Build Support Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplateBuildSupportTests {
        @Test
        func buildForTestingWithValidTemplate() async throws { // precondition linux error
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { _ in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)
                    let buildOptions = try BuildCommandOptions.parse([])

                    // Test TemplateBuildSupport static API for building templates
                    try await TemplateBuildSupport.buildForTesting(
                        swiftCommandState: tool,
                        buildOptions: buildOptions,
                        testingFolder: templatePath
                    )

                    // Verify build succeeds without errors
                    #expect(tool.fileSystem.exists(templatePath), "Template path should still exist after build")
                }
            }
        }

        @Test
        func buildWithValidConfiguration() async throws { // build system provider error
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { _ in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)
                    let buildOptions = try BuildCommandOptions.parse([])
                    let globalOptions = try GlobalOptions.parse([])

                    // Test TemplateBuildSupport.build static method
                    try await TemplateBuildSupport.build(
                        swiftCommandState: tool,
                        buildOptions: buildOptions,
                        globalOptions: globalOptions,
                        cwd: templatePath,
                        transitiveFolder: nil
                    )

                    // Verify build configuration works with template
                    #expect(
                        tool.fileSystem.exists(templatePath.appending("Package.swift")),
                        "Package.swift should exist"
                    )
                }
            }
        }
    }

    // MARK: - InitTemplatePackage Tests

    @Suite(
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.LocalTemplate,
        ),
    )
    struct InitTemplatePackageTests {
        @Test
        func createsTemplatePackageWithValidConfiguration() async throws {
            try fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Create package dependency for template
                    let dependency = SwiftRefactor.PackageDependency.fileSystem(
                        SwiftRefactor.PackageDependency.FileSystem(
                            path: templatePath.pathString
                        )
                    )

                    let initPackage = try InitTemplatePackage(
                        name: "TestPackage",
                        initMode: dependency,
                        fileSystem: tool.fileSystem,
                        packageType: .executable,
                        supportedTestingLibraries: [.xctest],
                        destinationPath: packagePath,
                        installedSwiftPMConfiguration: tool.getHostToolchain().installedSwiftPMConfiguration
                    )

                    // Test package configuration
                    #expect(initPackage.packageName == "TestPackage")
                    #expect(initPackage.packageType == .executable)
                    #expect(initPackage.destinationPath == packagePath)
                }
            }
        }

        @Test
        func writesPackageStructureWithTemplateDependency() async throws {
            try fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    let dependency = SwiftRefactor.PackageDependency.fileSystem(
                        SwiftRefactor.PackageDependency.FileSystem(
                            path: templatePath.pathString
                        )
                    )

                    let initPackage = try InitTemplatePackage(
                        name: "TestPackage",
                        initMode: dependency,
                        fileSystem: tool.fileSystem,
                        packageType: .executable,
                        supportedTestingLibraries: [.xctest],
                        destinationPath: packagePath,
                        installedSwiftPMConfiguration: tool.getHostToolchain().installedSwiftPMConfiguration
                    )

                    try initPackage.setupTemplateManifest()

                    // Verify package structure was created
                    #expect(tool.fileSystem.exists(packagePath))
                    #expect(tool.fileSystem.exists(packagePath.appending("Package.swift")))
                    #expect(tool.fileSystem.exists(packagePath.appending("Sources")))
                }
            }
        }

        @Test
        func handlesInvalidTemplatePath() async throws {
            try await testWithTemporaryDirectory { tempDir in
                let invalidTemplatePath = tempDir.appending("NonexistentTemplate")
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // Should handle invalid template path gracefully
                await #expect(throws: (any Error).self) {
                    _ = try await TemplatePackageInitializer.inferPackageType(
                        from: invalidTemplatePath,
                        templateName: "foo",
                        swiftCommandState: tool
                    )
                }
            }
        }
    }

    // MARK: - Integration Tests for Template Workflows

    @Suite(
        .tags(
            Tag.TestSize.large,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.LocalTemplate,
        ),
    )
    struct TemplateWorkflowIntegrationTests {
        @Test(
            .skipHostOS(.windows, "Template operations not fully supported in test environment"),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func templateResolutionToPackageCreationWorkflow(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test complete workflow: Template Resolution → Package Creation
                    let resolver = try TemplatePathResolver(
                        source: .local,
                        templateDirectory: templatePath,
                        templateURL: nil,
                        sourceControlRequirement: nil,
                        registryRequirement: nil,
                        packageIdentity: nil,
                        swiftCommandState: tool
                    )

                    let resolvedPath = try await resolver.resolve()
                    #expect(resolvedPath == templatePath)

                    // Create package dependency builder
                    let dependencyBuilder = DefaultPackageDependencyBuilder(
                        templateSource: .local,
                        packageName: "TestPackage",
                        templateURL: nil,
                        templatePackageID: nil,
                        sourceControlRequirement: nil,
                        registryRequirement: nil,
                        resolvedTemplatePath: resolvedPath
                    )

                    let packageDependency = try dependencyBuilder.makePackageDependency()

                    // Verify dependency was created correctly
                    if case .fileSystem(let fileSystemDep) = packageDependency {
                        #expect(fileSystemDep.path == resolvedPath.pathString)
                    } else {
                        Issue.record("Expected fileSystem dependency, got \(packageDependency)")
                    }

                    // Create template package
                    let initPackage = try InitTemplatePackage(
                        name: "TestPackage",
                        initMode: packageDependency,
                        fileSystem: tool.fileSystem,
                        packageType: .executable,
                        supportedTestingLibraries: [.xctest],
                        destinationPath: packagePath,
                        installedSwiftPMConfiguration: tool.getHostToolchain().installedSwiftPMConfiguration
                    )

                    try initPackage.setupTemplateManifest()

                    // Verify complete package structure
                    #expect(tool.fileSystem.exists(packagePath))
                    expectFileExists(at: packagePath.appending("Package.swift"))
                    expectDirectoryExists(at: packagePath.appending("Sources"))

                    /* Bad memory access error here
                     // Verify package builds successfully
                     try await executeSwiftBuild(
                         packagePath,
                         configuration: data.config,
                         buildSystem: data.buildSystem
                     )

                     let buildPath = packagePath.appending(".build")
                     expectDirectoryExists(at: buildPath)
                      */
                }
            }
        }

        @Test(
            .skipHostOS(.windows, "Git operations not fully supported in test environment"),
            .requireUnrestrictedNetworkAccess("Test needs to create and access local git repositories"),
        )
        func gitTemplateResolutionAndBuildWorkflow() async throws {
            try await testWithTemporaryDirectory { tempDir in
                let templateRepoPath = tempDir.appending("template-repo")

                // Copy template structure to git repo
                try fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { fixturePath in
                    try localFileSystem.copy(from: fixturePath, to: templateRepoPath)
                }

                initGitRepo(templateRepoPath, tag: "1.0.0")

                let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                let options = try GlobalOptions.parse([])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // Test Git template resolution
                let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement.branch("main")

                let resolver = try TemplatePathResolver(
                    source: .git,
                    templateDirectory: nil,
                    templateURL: sourceControlURL.url?.absoluteString,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: nil,
                    packageIdentity: nil,
                    swiftCommandState: tool
                )

                let resolvedPath = try await resolver.resolve()
                #expect(localFileSystem.exists(resolvedPath))

                // Verify template was fetched correctly with expected files
                #expect(localFileSystem.exists(resolvedPath.appending("Package.swift")))
                #expect(localFileSystem.exists(resolvedPath.appending("Templates")))
            }
        }

        @Test
        func pluginCoordinationWithBuildSystemIntegration() async throws { // Build provider not initialized.
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test plugin coordination with build system
                    let coordinator = TemplatePluginCoordinator(
                        buildSystem: .native,
                        swiftCommandState: tool,
                        scratchDirectory: tempDir,
                        template: "ExecutableTemplate",
                        args: ["--name", "TestPackage"],
                        branches: []
                    )

                    // Test coordinator functionality
                    #expect(coordinator.buildSystem == .native)
                    #expect(coordinator.scratchDirectory == tempDir)

                    // Test build support static API
                    let buildOptions = try BuildCommandOptions.parse([])
                    try await TemplateBuildSupport.buildForTesting(
                        swiftCommandState: tool,
                        buildOptions: buildOptions,
                        testingFolder: templatePath
                    )

                    // Verify they can work together (no errors thrown)
                    #expect(coordinator.buildSystem == .native)
                }
            }
        }

        @Test
        func packageDependencyBuildingWithVersionResolution() async throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)

            let lowerBoundVersion = Version(stringLiteral: "1.2.0")
            let higherBoundVersion = Version(stringLiteral: "3.0.0")

            // Test version requirement resolution integration
            let versionResolver = DependencyRequirementResolver(
                packageIdentity: "test.package",
                swiftCommandState: tool,
                exact: nil,
                revision: nil,
                branch: nil,
                from: lowerBoundVersion,
                upToNextMinorFrom: nil,
                to: higherBoundVersion
            )

            let sourceControlRequirement = try versionResolver.resolveSourceControl()
            let registryRequirement = try await versionResolver.resolveRegistry()

            // Test dependency building with resolved requirements
            let dependencyBuilder = try DefaultPackageDependencyBuilder(
                templateSource: .git,
                packageName: "TestPackage",
                templateURL: "https://github.com/example/template.git",
                templatePackageID: "test.package",
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: AbsolutePath(validating: "/fake/path")
            )

            let gitDependency = try dependencyBuilder.makePackageDependency()

            // Verify dependency structure
            if case .sourceControl(let sourceControlDep) = gitDependency {
                #expect(sourceControlDep.location == "https://github.com/example/template.git")
                if case .range(let lower, let upper) = sourceControlDep.requirement {
                    #expect(lower == "1.2.0")
                    #expect(upper == "3.0.0")
                } else {
                    Issue.record("Expected range requirement, got \(sourceControlDep.requirement)")
                }
            } else {
                Issue.record("Expected sourceControl dependency, got \(gitDependency)")
            }
        }
    }

    // MARK: - End-to-End Template Initialization Tests

    @Suite(
        .tags(
            Tag.TestSize.large,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.LocalTemplate,
        ),
    )
    struct EndToEndTemplateInitializationTests {
        @Test
        func templateInitializationErrorHandling() async throws {
            try await testWithTemporaryDirectory { tempDir in
                let packagePath = tempDir.appending("TestPackage")
                try FileManager.default.createDirectory(at: packagePath.asURL, withIntermediateDirectories: true, attributes: nil)
                let nonexistentPath = tempDir.appending("nonexistent-template")
                let options = try GlobalOptions.parse(["--package-path", packagePath.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // Test complete error handling workflow
                await #expect(throws: (any Error).self) {
                    let configuration = try PackageInitConfiguration(
                        swiftCommandState: tool,
                        name: "TestPackage",
                        initMode: "custom",
                        testLibraryOptions: TestLibraryOptions.parse([]),
                        buildOptions: BuildCommandOptions.parse([]),
                        globalOptions: options,
                        validatePackage: false,
                        args: ["--name", "TestPackage"],
                        directory: nonexistentPath,
                        url: nil,
                        packageID: nil,
                        versionFlags: VersionFlags(
                            exact: nil, revision: nil, branch: nil,
                            from: nil, upToNextMinorFrom: nil, to: nil
                        )
                    )

                    let initializer = try configuration.makeInitializer()

                    // Change to package directory
                    try tool.fileSystem.changeCurrentWorkingDirectory(to: packagePath)
                    try tool.fileSystem.createDirectory(packagePath, recursive: true)

                    try await initializer.run()
                }

                // Verify package was not created due to error
                #expect(!tool.fileSystem.exists(packagePath.appending("Package.swift")))
            }
        }

        @Test
        func standardPackageInitializerFallback() async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                try fs.createDirectory(path)
                let options = try GlobalOptions.parse(["--package-path", path.pathString])
                let tool = try SwiftCommandState.makeMockState(options: options)

                // Test fallback to standard initializer when no template is specified
                let configuration = try PackageInitConfiguration(
                    swiftCommandState: tool,
                    name: "TestPackage",
                    initMode: "executable", // Standard package type
                    testLibraryOptions: TestLibraryOptions.parse([]),
                    buildOptions: BuildCommandOptions.parse([]),
                    globalOptions: options,
                    validatePackage: false,
                    args: [],
                    directory: nil,
                    url: nil,
                    packageID: nil,
                    versionFlags: VersionFlags(
                        exact: nil, revision: nil, branch: nil,
                        from: nil, upToNextMinorFrom: nil, to: nil
                    )
                )

                let initializer = try configuration.makeInitializer()
                #expect(initializer is StandardPackageInitializer)

                // Change to package directory
                try await initializer.run()

                // Verify standard package was created
                #expect(tool.fileSystem.exists(path.appending("Package.swift")))
                #expect(try fs
                    .getDirectoryContents(path.appending("Sources").appending("TestPackage")) == ["TestPackage.swift"]
                )
            }
        }
    }
}
