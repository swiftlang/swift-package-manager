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

@_spi(SwiftPMInternal)
@testable import CoreCommands
@testable import Commands

import Foundation

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)

import PackageGraph
import TSCUtility
import PackageLoading
import SourceControl
import SPMBuildCore
import _InternalTestSupport
import Workspace
import Testing

@_spi(PackageRefactor) import SwiftRefactor

import struct TSCBasic.ByteString
import class TSCBasic.BufferedOutputByteStream
import enum TSCBasic.JSON
import class Basics.AsyncProcess


// MARK: - Helper Methods
fileprivate func makeTestResolver() throws -> (resolver: DefaultTemplateSourceResolver, tool: SwiftCommandState) {
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


fileprivate func makeTestTool() throws -> SwiftCommandState {
    let options = try GlobalOptions.parse([])
    return try SwiftCommandState.makeMockState(options: options)
}

fileprivate func makeVersions() -> (lower: Version, higher: Version) {
    let lowerBoundVersion = Version(stringLiteral: "1.2.0")
    let higherBoundVersion = Version(stringLiteral: "3.0.0")
    return (lowerBoundVersion, higherBoundVersion)
}


fileprivate func makeTestDependencyData() throws -> (tool: SwiftCommandState, packageName: String, templateURL: String, templatePackageID: String, path: AbsolutePath) {
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

struct TemplateTests{
    // MARK: - Template Source Resolution Tests
    @Suite(
        .tags(
            Tag.TestSize.small,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplateSourceResolverTests {
        @Test func resolveSourceWithNilInputs() throws {

            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)


            guard let cwd = tool.fileSystem.currentWorkingDirectory else {return}
            let fileSystem = tool.fileSystem
            let observabilityScope = tool.observabilityScope

            let resolver = DefaultTemplateSourceResolver(cwd: cwd, fileSystem: fileSystem, observabilityScope: observabilityScope)

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
                directory: AbsolutePath("/fake/path/to/template"), url: "https://github.com/foo/bar", packageID: "foo.bar"
            )
            #expect(gitSource == .git)
        }

        @Test func validateGitURLWithValidInput() async throws {

            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            try resolver.validate(templateSource: .git, directory: nil, url: "https://github.com/apple/swift", packageID: nil)

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(tool.observabilityScope.errorsReportedInAnyScope == false)

        }

        @Test func validateGitURLWithInvalidInput() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidGitURL("invalid-url").self) {
                try resolver.validate(templateSource: .git, directory: nil, url: "invalid-url", packageID: nil)
            }
        }

        @Test func validateRegistryIDWithValidInput() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "mona.LinkedList")

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(tool.observabilityScope.errorsReportedInAnyScope == false)
        }

        @Test func validateRegistryIDWithInvalidInput() throws {

            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidRegistryIdentity("invalid-id").self) {
                try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "invalid-id")
            }
        }

        @Test func validateLocalSourceWithMissingPath() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.missingLocalPath.self) {
                try resolver.validate(templateSource: .local, directory: nil, url: nil, packageID: nil)
            }
        }

        @Test func validateLocalSourceWithInvalidPath() throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)
            let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidDirectoryPath("/fake/path/that/does/not/exist").self) {
                try resolver.validate(templateSource: .local, directory: "/fake/path/that/does/not/exist", url: nil, packageID: nil)
            }
        }

        @Test func resolveRegistryDependencyWithNoVersion() async throws {
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

        @Test func resolveRegistryDependencyRequirements() async throws {

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
                Issue.record("Expected range registry dependency, got \(String(describing: upToNextMinorFromToRegistryDependency))")
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
                Issue.record("Expected rangeFrom registry dependency, got \(String(describing: fromRegistryDependency))")
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
                Issue.record("Expected range registry dependency, got \(String(describing: upToNextMinorFromRegistryDependency))")
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

        @Test func resolveSourceControlDependencyRequirements() throws {

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
                Issue.record("Expected branch source control dependency, got \(String(describing: branchSourceControlDependency))")
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
                Issue.record("Expected revision source control dependency, got \(String( describing: revisionSourceControlDependency))")
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
                Issue.record("Expected exact source control dependency, got \(String(describing: exactSourceControlDependency))")
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
                Issue.record("Expected range source control dependency, got \(String(describing: fromToSourceControlDependency))")
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
                Issue.record("Expected range source control dependency, got \(String(describing: upToNextMinorFromToSourceControlDependency))")
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
                Issue.record("Expected rangeFrom source control dependency, got \(String(describing: fromSourceControlDependency))")
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
                Issue.record("Expected range source control dependency, got \(String(describing: upToNextMinorFromSourceControlDependency))")
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

        @Test func resolveLocalTemplatePath() async throws {
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
                #expect(localFileSystem.exists(path.appending(component: "file.swift")), "Template was not fetched correctly")
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

                await #expect(throws: GitTemplateFetcher.GitTemplateFetcherError.cloneFailed(source: "invalid-git-url")) {
                    _ = try await resolver.resolve()
                }
            }
        }

        @Test func resolveRegistryTemplatePath() async throws {
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

        @Test func createTemporaryDirectories() throws {

            let options = try GlobalOptions.parse([])

            let tool = try SwiftCommandState.makeMockState(options: options)

            let (stagingPath, cleanupPath, tempDir) = try TemplateInitializationDirectoryManager(fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope).createTemporaryDirectories()


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
                #expect(localFileSystem.exists(cwdBinFile) == false, "Binary should have been cleaned before copying to cwd")
            }
        }

        @Test func cleanUpTemporaryDirectories() throws {

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

        @Test func buildDependenciesFromTemplateSource() async throws {
            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)

            let packageName = "foo"
            let templateURL = "git@github.com:foo/bar"
            let templatePackageID = "foo.bar"

            let versionResolver = DependencyRequirementResolver(
                packageIdentity: templatePackageID, swiftCommandState: tool, exact: Version(stringLiteral: "1.2.0"), revision: nil, branch: nil, from: nil, upToNextMinorFrom: nil, to: nil
            )

            let sourceControlRequirement: SwiftRefactor.PackageDependency.SourceControl.Requirement = try versionResolver.resolveSourceControl()
            guard let registryRequirement = try await versionResolver.resolveRegistry() else {
                Issue.record("Registry ID of template could not be resolved.")
                return
            }

            let resolvedTemplatePath: AbsolutePath = try AbsolutePath(validating: "/fake/path/to/template")

            //local

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

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingRegistryIdentity.self) {
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

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingRegistryRequirement.self) {
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

        @Test func createPackageInitializer() throws {

            let globalOptions = try GlobalOptions.parse([])
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
                versionFlags: VersionFlags(exact: nil, revision: nil, branch: "master", from: nil, upToNextMinorFrom: nil ,to: nil)
            ).makeInitializer()

            #expect(templatePackageInitializer is TemplatePackageInitializer)


            let standardPackageInitalizer  = try PackageInitConfiguration(
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
                versionFlags: VersionFlags(exact: nil, revision: nil, branch: "master", from: nil, upToNextMinorFrom: nil ,to: nil)
            ).makeInitializer()

            #expect(standardPackageInitalizer is StandardPackageInitializer)
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
}
