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

@Suite(
    .serialized,
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
        @Test()
        func resolveSourceWithNilInputs() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])

                    let tool = try SwiftCommandState.makeMockState(options: options)

                    guard let cwd = tool.fileSystem.currentWorkingDirectory else {
                        Issue.record("Could not find working directory")
                        return
                    }
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
            }
        }

        @Test
        func validateGitURLWithValidInput() async throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
            )

            try resolver.validate(
                templateSource: .git,
                directory: nil,
                url: "https://github.com/apple/swift",
                packageID: nil
            )

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(observabilityScope.topScope.errorsReportedInAnyScope == false)
        }

        @Test
        func validateGitURLWithInvalidInput() throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidGitURL("invalid-url").self) {
                try resolver.validate(templateSource: .git, directory: nil, url: "invalid-url", packageID: nil)
            }
        }

        @Test
        func validateRegistryIDWithValidInput() throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
            )

            try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "mona.LinkedList")

            // Check that nothing was emitted (i.e., no error for valid URL)
            #expect(observabilityScope.topScope.errorsReportedInAnyScope == false)
        }

        @Test
        func validateRegistryIDWithInvalidInput() throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidRegistryIdentity("invalid-id").self
            ) {
                try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "invalid-id")
            }
        }

        @Test
        func validateLocalSourceWithMissingPath() throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
            )

            #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.missingLocalPath.self) {
                try resolver.validate(templateSource: .local, directory: nil, url: nil, packageID: nil)
            }
        }

        @Test
        func validateLocalSourceWithInvalidPath() throws {
            let fileSystem = InMemoryFileSystem()
            let observabilityScope = ObservabilitySystem.makeForTesting()

            let resolver = DefaultTemplateSourceResolver(
                cwd: fileSystem.currentWorkingDirectory!,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope.topScope
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
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])

                    let tool = try SwiftCommandState.makeMockState(options: options)

                    let lowerBoundVersion = Version(stringLiteral: "1.2.0")
                    let higherBoundVersion = Version(stringLiteral: "3.0.0")

                    await #expect(throws: DependencyRequirementError.noRequirementSpecified.self) {
                        try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: nil,
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
                        templateURL: nil,
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
                        Issue
                            .record(
                                "Expected exact registry dependency, got \(String(describing: exactRegistryDependency))"
                            )
                    }

                    // test from to
                    let fromToRegistryDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                        Issue
                            .record(
                                "Expected range registry dependency, got \(String(describing: fromToRegistryDependency))"
                            )
                    }

                    // test up-to-next-minor-from and to
                    let upToNextMinorFromToRegistryDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                        templateURL: nil,
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
                            .record(
                                "Expected rangeFrom registry dependency, got \(String(describing: fromRegistryDependency))"
                            )
                    }

                    // test just up-to-next-minor-from
                    let upToNextMinorFromRegistryDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                            templateURL: nil,
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
                            templateURL: nil,
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
                            templateURL: nil,
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
            }
        }

        @Test()
        func resolveSourceControlDependencyRequirements() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])

                    let tool = try SwiftCommandState.makeMockState(options: options)

                    let lowerBoundVersion = Version(stringLiteral: "1.2.0")
                    let higherBoundVersion = Version(stringLiteral: "3.0.0")

                    let branchSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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

                    let revisionSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                    let exactSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                    let fromToSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                    let upToNextMinorFromToSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                    let fromSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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
                    let upToNextMinorFromSourceControlDependency = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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

                    await #expect(throws: DependencyRequirementError.multipleRequirementsSpecified.self) {
                        try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: nil,
                            swiftCommandState: tool,
                            exact: lowerBoundVersion,
                            revision: "dae86e",
                            branch: nil,
                            from: lowerBoundVersion,
                            upToNextMinorFrom: lowerBoundVersion,
                            to: nil
                        ).resolveSourceControl()
                    }

                    await #expect(throws: DependencyRequirementError.noRequirementSpecified.self) {
                        try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: nil,
                            swiftCommandState: tool,
                            exact: nil,
                            revision: nil,
                            branch: nil,
                            from: nil,
                            upToNextMinorFrom: nil,
                            to: nil
                        ).resolveSourceControl()
                    }

                    await #expect(throws: DependencyRequirementError.invalidToParameterWithoutFrom.self) {
                        try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: nil,
                            swiftCommandState: tool,
                            exact: lowerBoundVersion,
                            revision: nil,
                            branch: nil,
                            from: nil,
                            upToNextMinorFrom: nil,
                            to: higherBoundVersion
                        ).resolveSourceControl()
                    }

                    // Git stuff

                    try await testWithTemporaryDirectory { path in
                        let templateRepoPath = path.appending(component: "template-repo")
                        let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                        try! makeDirectories(templateRepoPath)
                        initGitRepo(templateRepoPath, tag: lowerBoundVersion.defaultValueDescription)

                        let exactVersion = try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: sourceControlURL.absoluteString,
                            swiftCommandState: tool,
                            exact: nil,
                            revision: nil,
                            branch: nil,
                            from: nil,
                            upToNextMinorFrom: nil,
                            to: nil
                        ).resolveSourceControl()

                        if case .exact(let version) = exactVersion {
                            #expect(version == lowerBoundVersion.description)
                        } else {
                            Issue
                                .record(
                                    "Expected exact source control dependency, got \(String(describing: exactSourceControlDependency))"
                                )
                        }
                    }

                    try await testWithTemporaryDirectory { path in
                        let templateRepoPath = path.appending(component: "template-repo")
                        let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                        try! makeDirectories(templateRepoPath)
                        initGitRepo(templateRepoPath, tag: "not-a-semver-compliant-version")

                        await #expect(throws: DependencyRequirementError
                            .noVersionTagsFound(url: sourceControlURL.absoluteString).self
                        ) {
                            _ = try await DependencyRequirementResolver(
                                packageIdentity: nil,
                                templateURL: sourceControlURL.absoluteString,
                                swiftCommandState: tool,
                                exact: nil,
                                revision: nil,
                                branch: nil,
                                from: nil,
                                upToNextMinorFrom: nil,
                                to: nil
                            ).resolveSourceControl()
                        }
                    }

                    try await testWithTemporaryDirectory { path in
                        let templateRepoPath = path.appending(component: "template-repo")
                        let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                        try! makeDirectories(templateRepoPath)
                        initGitRepo(templateRepoPath, tag: "not-a-semver-compliant-version")

                        await #expect(throws: DependencyRequirementError
                            .noVersionTagsFound(url: sourceControlURL.absoluteString).self
                        ) {
                            _ = try await DependencyRequirementResolver(
                                packageIdentity: nil,
                                templateURL: sourceControlURL.absoluteString,
                                swiftCommandState: tool,
                                exact: nil,
                                revision: nil,
                                branch: nil,
                                from: nil,
                                upToNextMinorFrom: nil,
                                to: nil
                            ).resolveSourceControl()
                        }
                    }

                    await #expect(throws: (any Error).self) {
                        _ = try await DependencyRequirementResolver(
                            packageIdentity: nil,
                            templateURL: "url-that-does-not-exist",
                            swiftCommandState: tool,
                            exact: nil,
                            revision: nil,
                            branch: nil,
                            from: nil,
                            upToNextMinorFrom: nil,
                            to: nil
                        ).resolveSourceControl()
                    }

                    let range = try await DependencyRequirementResolver(
                        packageIdentity: nil,
                        templateURL: nil,
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

            let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: InMemoryFileSystem())

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
                let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement
                    .branch("main")

                let templateRepoPath = path.appending(component: "template-repo")
                let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                let templateRepoURL = sourceControlURL.url
                try! makeDirectories(templateRepoPath)
                initGitRepo(templateRepoPath, tag: "1.2.3")

                try await withTaskLocalWorkingDirectory(templateRepoPath) {
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

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
        }

        @Test(
            .skipHostOS(.windows, "Git operations not fully supported in test environment"),
            .requireUnrestrictedNetworkAccess("Test needs to attempt git clone operations"),
        )
        func resolveGitTemplatePathWithInvalidURL() async throws {
            try await testWithTemporaryDirectory { path in
                let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement
                    .branch("main")
                let options = try GlobalOptions.parse([])

                let tool = try SwiftCommandState.makeMockState(options: options)

                let templateRepoPath = path.appending(component: "template-repo")
                try! makeDirectories(templateRepoPath)
                initGitRepo(templateRepoPath, tag: "1.2.3")
                try await withTaskLocalWorkingDirectory(templateRepoPath) {
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

            // Create InMemoryFileSystem with necessary directories
            let fileSystem = InMemoryFileSystem()
            try fileSystem.createDirectory(AbsolutePath("/tmp"), recursive: true)

            let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: fileSystem)

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
            .skipSwiftCISelfHosted(
                "Caught error: /tmp/Miscellaneous_DirectoryManagerFinalize.FBjvCq/clean-up/Package.swift doesn't exist in file system"
            ),
            // to investigate later
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

                // Manually create the built package structure instead of building
                // This tests the directory transfer logic without subprocess complications
                let stagingBuildPath = stagingPath.appending(".build")
                let binPathComponents = try data.buildSystem.binPath(for: data.config, scratchPath: [])
                let stagingBinPath = stagingBuildPath.appending(components: binPathComponents)
                let stagingBinFile = stagingBinPath.appending(executableName("generated-package"))

                // Create the directory structure and mock executable
                try localFileSystem.createDirectory(stagingBinPath, recursive: true)
                try localFileSystem.writeFileContents(stagingBinFile, bytes: ByteString([0x00, 0x01, 0x02]))

                #expect(localFileSystem.exists(stagingBinFile))
                #expect(localFileSystem.isDirectory(stagingBuildPath))

                try await withTaskLocalWorkingDirectory(fixturePath) {
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

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
        }

        @Test
        func cleanUpTemporaryDirectories() async throws {
            try await fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                try await withTaskLocalWorkingDirectory(fixturePath) {
                    let pathToRemove = fixturePath.appending("cwd")
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    try TemplateInitializationDirectoryManager(
                        fileSystem: tool.fileSystem,
                        observabilityScope: tool.observabilityScope
                    ).cleanupTemporary(templateSource: .git, path: pathToRemove, temporaryDirectory: nil)

                    #expect(!localFileSystem.exists(pathToRemove), "path should be removed")
                }
            }

            try await fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                try await withTaskLocalWorkingDirectory(fixturePath) {
                    let pathToRemove = fixturePath.appending("clean-up")
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    try TemplateInitializationDirectoryManager(
                        fileSystem: tool.fileSystem,
                        observabilityScope: tool.observabilityScope
                    ).cleanupTemporary(templateSource: .registry, path: pathToRemove, temporaryDirectory: nil)

                    #expect(!localFileSystem.exists(pathToRemove), "path should be removed")
                }
            }

            try await fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
                try await withTaskLocalWorkingDirectory(fixturePath) {
                    let pathToRemove = fixturePath.appending("clean-up")
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
            let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: InMemoryFileSystem())

            let packageName = "foo"
            let templateURL = "git@github.com:foo/bar"
            let templatePackageID = "foo.bar"

            let versionResolver = DependencyRequirementResolver(
                packageIdentity: templatePackageID, templateURL: nil, swiftCommandState: tool,
                exact: Version(stringLiteral: "1.2.0"),
                revision: nil, branch: nil, from: nil, upToNextMinorFrom: nil, to: nil
            )

            let sourceControlRequirement: SwiftRefactor.PackageDependency.SourceControl
                .Requirement = try await versionResolver.resolveSourceControl()
            let registryRequirement = try await versionResolver.resolveRegistry()

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
            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingGitURLOrPath
                .self
            ) {
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

            #expect(throws: DefaultPackageDependencyBuilder.PackageDependencyBuilderError.missingGitRequirement
                .self
            ) {
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
        func createPackageInitializer() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
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
        }

        @Test(.skip("Failing due to package resolution"))
        func findTemplateName() async throws {
            try await fixture(name: "Miscellaneous/InitTemplates") { workingDir in
                let templatePath = workingDir.appending(component: "ExecutableTemplate")
                let versionFlags = VersionFlags(
                    exact: nil,
                    revision: nil,
                    branch: nil,
                    from: nil,
                    upToNextMinorFrom: nil,
                    to: nil
                )

                let globalOptions = try GlobalOptions.parse(["--package-path", workingDir.pathString])
                let swiftCommandState = try SwiftCommandState.makeMockState(options: globalOptions)

                let testLibraryOptions = try TestLibraryOptions.parse([])

                let buildOptions = try BuildCommandOptions.parse([])

                let templatePackageInitializer = try PackageInitConfiguration(
                    swiftCommandState: swiftCommandState,
                    name: nil,
                    initMode: nil,
                    testLibraryOptions: testLibraryOptions,
                    buildOptions: buildOptions,
                    globalOptions: globalOptions,
                    validatePackage: false,
                    args: [],
                    directory: templatePath,
                    url: nil,
                    packageID: nil,
                    versionFlags: versionFlags
                ).makeInitializer() as? TemplatePackageInitializer

                let templateName = try await templatePackageInitializer?
                    .resolveTemplateNameInPackage(from: templatePath)
                #expect(templateName == "ExecutableTemplate")
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
    struct TemplateCLIConstructorTests {
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
            completionKind: ArgumentInfoV0.CompletionKindV0? = nil,
            isRepeating: Bool = false
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: isRepeating,
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
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let emptyCommand = self.createTestCommand(name: "empty")

            let toolInfo = ToolInfoV0(command: emptyCommand)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: [],
                toolInfoJson: toolInfo
            )

            #expect(result.isEmpty)
        }

        @Test
        func handlesCommandWithProvidedArguments() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage"],
                toolInfoJson: toolInfo
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        @Test
        func handlesOptionalArgumentsWithDefaults() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalFlag(name: "include-readme", defaultValue: "false"),
                ]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage"],
                toolInfoJson: toolInfo
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            // Flag with default "false" should not appear in command line
            #expect(!result.contains("--include-readme"))
        }

        @Test
        func validatesMissingRequiredArguments() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: [],
                    toolInfoJson: toolInfo
                )
            }
        }

        // MARK: - Argument Response Tests

        @Test
        func argumentResponseHandlesExplicitlyUnsetFlags() throws {
            let arg = self.createOptionalFlag(name: "verbose", defaultValue: "false")

            // Test explicitly unset flag
            let explicitlyUnsetResponse = ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal flag response (true)
            let trueResponse = ArgumentResponse(
                argument: arg,
                values: ["true"],
                isExplicitlyUnset: false
            )
            #expect(trueResponse.isExplicitlyUnset == false)
            #expect(trueResponse.commandLineFragments == ["--verbose"])

            // Test false flag response (should be empty)
            let falseResponse = ArgumentResponse(
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
            let explicitlyUnsetResponse = ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal option response
            let normalResponse = ArgumentResponse(
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

            let multiValueResponse = ArgumentResponse(
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
            let explicitlyUnsetResponse = ArgumentResponse(
                argument: arg,
                values: [],
                isExplicitlyUnset: true
            )
            #expect(explicitlyUnsetResponse.isExplicitlyUnset == true)
            #expect(explicitlyUnsetResponse.commandLineFragments.isEmpty)

            // Test normal positional response
            let normalResponse = ArgumentResponse(
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
            // Test the actual public API instead of internal buildCommandLine
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)

            let flagArg = self.createOptionalFlag(name: "verbose")
            let requiredOptionArg = self.createRequiredOption(name: "name")
            let optionalOptionArg = self.createOptionalOption(name: "output")

            let commandInfo = self.createTestCommand(
                arguments: [flagArg, requiredOptionArg, optionalOptionArg]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage", "--verbose"],
                toolInfoJson: toolInfo
            )

            // Should contain the provided arguments
            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            #expect(result.contains("--verbose"))
        }

        @Test
        func commandLineGenerationWithDefaultValues() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)

            let optionWithDefault = self.createOptionalOption(name: "version", defaultValue: "1.0.0")
            let flagWithDefault = self.createOptionalFlag(name: "enabled", defaultValue: "true")

            let commandInfo = self.createTestCommand(
                arguments: [optionWithDefault, flagWithDefault]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: [],
                toolInfoJson: toolInfo
            )

            // Should contain default values
            #expect(result.contains("--version"))
            #expect(result.contains("1.0.0"))
            #expect(result.contains("--enabled"))
        }

        // MARK: - Argument Parsing Tests

        @Test
        func parsesProvidedArgumentsCorrectly() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalFlag(name: "verbose"),
                    self.createOptionalOption(name: "output"),
                ]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage", "--verbose", "--output", "./dist"],
                toolInfoJson: toolInfo
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [restrictedArg])

            // Valid value should work
            let toolInfo = ToolInfoV0(command: commandInfo)
            let validResult = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--type", "executable"],
                toolInfoJson: toolInfo
            )
            #expect(validResult.contains("executable"))

            // Invalid value should throw
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--type", "invalid"],
                    toolInfoJson: toolInfo
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let toolInfo = ToolInfoV0(command: mainCommand)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["init", "--name", "TestPackage"],
                toolInfoJson: toolInfo
            )

            #expect(result.contains("init"))
            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        @Test
        func handlesBranchingSubcommandDetection() throws {
            let subcommand = self.createTestCommand(
                name: "init",
                arguments: [self.createRequiredOption(name: "name")]
            )

            let branchingSubcommand = self.createTestCommand(
                name: "ios"
            )

            let mainCommand = self.createTestCommand(
                name: "package",
                arguments: [self.createRequiredOption(name: "package-path")],
                subcommands: [subcommand, branchingSubcommand],
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let toolInfo = ToolInfoV0(command: mainCommand)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--package-path", "foo", "init", "--name", "TestPackage"],
                toolInfoJson: toolInfo
            )

            #expect(result.contains("init"))
            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
        }

        // MARK: - Error Handling Tests

        @Test
        func handlesInvalidArgumentNames() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            // Should throw errors if invalid predefined arguments have been given.
            let toolInfo = ToolInfoV0(command: commandInfo)
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "TestPackage", "--unknown", "value"],
                    toolInfoJson: toolInfo
                )
            }
        }

        @Test
        func handlesMissingValueForOption() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [self.createRequiredOption(name: "name")]
            )

            let toolInfo = ToolInfoV0(command: commandInfo)
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name"],
                    toolInfoJson: toolInfo
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let toolInfo = ToolInfoV0(command: mainCommand)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["package", "create", "--name", "MyPackage"],
                toolInfoJson: toolInfo
            )

            #expect(result.contains("package"))
            #expect(result.contains("create"))
            #expect(result.contains("--name"))
            #expect(result.contains("MyPackage"))
        }

        // MARK: - Integration Tests

        @Test
        func handlesComplexCommandStructure() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)

            let complexCommand = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    self.createOptionalOption(name: "output", defaultValue: "./build"),
                    self.createOptionalFlag(name: "verbose", defaultValue: "false"),
                    self.createPositionalArgument(name: "target", isOptional: true, defaultValue: "main"),
                ]
            )

            let toolInfo = ToolInfoV0(command: complexCommand)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage", "--verbose", "CustomTarget"],
                toolInfoJson: toolInfo
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
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createOptionalOption(name: "output", defaultValue: "default"),
                    self.createOptionalFlag(name: "verbose", defaultValue: "false"),
                ]
            )

            let toolInfoJSON = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(predefinedArgs: [], toolInfoJson: toolInfoJSON)

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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [repeatingArg])

            let toolInfoJSON = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--define", "FOO=bar", "--define", "BAZ=qux"],
                toolInfoJson: toolInfoJSON
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [completionArg])

            let toolInfoJSON = ToolInfoV0(command: commandInfo)
            // Valid completion value should work
            let validResult = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--platform", "iOS"],
                toolInfoJson: toolInfoJSON
            )
            #expect(validResult.contains("iOS"))

            // Invalid completion value should throw
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--platform", "Linux"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesArgumentResponseBuilding() throws {
            let flagArg = self.createOptionalFlag(name: "verbose")
            let optionArg = self.createRequiredOption(name: "output")
            let positionalArg = self.createPositionalArgument(name: "target")

            // Test various response scenarios
            let flagResponse = ArgumentResponse(
                argument: flagArg,
                values: ["true"],
                isExplicitlyUnset: false
            )
            #expect(flagResponse.commandLineFragments == ["--verbose"])

            let optionResponse = ArgumentResponse(
                argument: optionArg,
                values: ["./output"],
                isExplicitlyUnset: false
            )
            #expect(optionResponse.commandLineFragments == ["--output", "./output"])

            let positionalResponse = ArgumentResponse(
                argument: positionalArg,
                values: ["MyTarget"],
                isExplicitlyUnset: false
            )
            #expect(positionalResponse.commandLineFragments == ["MyTarget"])
        }

        @Test
        func handlesMissingArgumentErrors() throws {
            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "required-arg"),
                    self.createOptionalOption(name: "optional-arg"),
                ]
            )

            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Should throw when required argument is missing
            #expect(throws: Error.self) {
                _ = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--optional-arg", "value"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        // MARK: - Parsing Strategy Tests

        @Test
        func handlesParsingStrategies() throws {
            let upToNextOptionArg = self.createRequiredOption(
                name: "files",
                parsingStrategy: .upToNextOption,
                isRepeating: true
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [upToNextOptionArg])

            let toolInfoJSON = ToolInfoV0(command: commandInfo)
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--files", "file1.swift", "file2.swift", "file3.swift"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--files"))
            #expect(result.contains("file1.swift"))
            #expect(result.contains("file2.swift"))
            #expect(result.contains("file3.swift"))
        }

        @Test
        func handlesPostTerminatorStrategy() throws {
            let preTerminatorArg = self.createRequiredOption(name: "name")
            let postTerminatorArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [preTerminatorArg, postTerminatorArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestName", "--", "file1", "file2", "--option"],
                toolInfoJson: toolInfoJSON
            )

            // Pre-terminator should be parsed normally
            #expect(result.contains("--name"))
            #expect(result.contains("TestName"))
            // Post-terminator should capture everything after --
            #expect(result.contains("file1"))
            #expect(result.contains("file2"))
            #expect(result.contains("--option")) // Even options are treated as values after --
        }

        // MARK: - Error Handling Tests

        @Test
        func handlesUnknownOptions() throws {
            let nameArg = self.createRequiredOption(name: "name")
            let formatArg = self.createRequiredOption(name: "format")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, formatArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test unknown long option
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test", "--format", "json", "--unknown"],
                    toolInfoJson: toolInfoJSON
                )
            }

            // Test unknown short option
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test", "--format", "json", "-q"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesMissingRequiredValues() throws {
            let nameArg = self.createRequiredOption(name: "name")
            let formatArg = self.createRequiredOption(name: "format")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, formatArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test missing value for option
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test", "--format"],
                    toolInfoJson: toolInfoJSON
                )
            }

            // Test missing required argument entirely
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesUnexpectedArguments() throws {
            let nameArg = self.createRequiredOption(name: "name")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test single unexpected argument
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test", "unexpected"],
                    toolInfoJson: toolInfoJSON
                )
            }

            // Test multiple unexpected arguments
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", "test", "unexpected1", "unexpected2"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesInvalidEnumValues() throws {
            let enumArg = self.createRequiredOption(
                name: "format",
                allValues: ["json", "xml", "yaml"]
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [enumArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test invalid enum value
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--format", "invalid"],
                    toolInfoJson: toolInfoJSON
                )
            }

            // Test valid enum value should work
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--format", "json"],
                toolInfoJson: toolInfoJSON
            )
            #expect(result.contains("--format"))
            #expect(result.contains("json"))
        }

        // MARK: - Edge Case Tests

        @Test
        func handlesEmptyInput() throws {
            let optionalArg = self.createOptionalOption(name: "name", defaultValue: "default")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [optionalArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Empty input should work with optional arguments
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: [],
                toolInfoJson: toolInfoJSON
            )

            // Should use default value
            #expect(result.contains("--name"))
            #expect(result.contains("default"))
        }

        @Test
        func handlesMalformedArguments() throws {
            let nameArg = self.createRequiredOption(name: "name")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test malformed long option (triple dash)
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["---name", "value"],
                    toolInfoJson: toolInfoJSON
                )
            }

            // Test empty option name
            #expect(throws: (any Error).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--", "value"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesSpecialCharactersInValues() throws {
            let nameArg = self.createRequiredOption(name: "name")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test values with special characters
            let specialValues = [
                "value with spaces",
                "value-with-dashes",
                "value_with_underscores",
                "value.with.dots",
                "value@with@symbols",
                "value/with/slashes",
            ]

            for specialValue in specialValues {
                let result = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", specialValue],
                    toolInfoJson: toolInfoJSON
                )
                #expect(result.contains("--name"))
                #expect(result.contains(specialValue))
            }
        }

        @Test
        func handlesEqualsSignInOptions() throws {
            let nameArg = self.createRequiredOption(name: "name")
            let formatArg = self.createRequiredOption(name: "format")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, formatArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test equals sign syntax
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name=TestName", "--format=json"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestName"))
            #expect(result.contains("--format"))
            #expect(result.contains("json"))
        }

        @Test
        func handlesUnicodeCharacters() throws {
            let nameArg = self.createRequiredOption(name: "name")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test Unicode characters
            let unicodeValues = [
                "测试", // Chinese
                "テスト", // Japanese
                "тест", // Russian
                "🎯📱💻", // Emojis
                "café", // Accented characters
            ]

            for unicodeValue in unicodeValues {
                let result = try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--name", unicodeValue],
                    toolInfoJson: toolInfoJSON
                )
                #expect(result.contains("--name"))
                #expect(result.contains(unicodeValue))
            }
        }

        // MARK: - Positional Argument Tests

        @Test
        func handlesSinglePositionalArgument() throws {
            let positionalArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "name")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "name"),
                valueName: "name",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Package name",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [positionalArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["MyPackage"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("MyPackage"))
        }

        @Test
        func handlesMultiplePositionalArguments() throws {
            let nameArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "name")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "name"),
                valueName: "name",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Package name",
                discussion: nil
            )

            let pathArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "path")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "path"),
                valueName: "path",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Package path",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, pathArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["MyPackage", "/path/to/package"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("MyPackage"))
            #expect(result.contains("/path/to/package"))
        }

        @Test
        func handlesRepeatingPositionalArguments() throws {
            let filesArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "files")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "files"),
                valueName: "files",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Input files",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [filesArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["file1.swift", "file2.swift", "file3.swift"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("file1.swift"))
            #expect(result.contains("file2.swift"))
            #expect(result.contains("file3.swift"))
        }

        @Test // RELOOK
        func handlesPositionalWithTerminator() throws {
            let nameArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .postTerminator,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "name")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "name"),
                valueName: "name",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Package name",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test positional argument that looks like an option after terminator
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--", "--package-name"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--package-name"))
        }

        // MARK: - Short Option and Combined Short Option Tests

        private func createShortOption(
            name: String,
            shortName: Character,
            isOptional: Bool = false,
            isRepeating: Bool = false
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: isOptional,
                isRepeating: isRepeating,
                parsingStrategy: .default,
                names: [
                    ArgumentInfoV0.NameInfoV0(kind: .short, name: String(shortName)),
                    ArgumentInfoV0.NameInfoV0(kind: .long, name: name),
                ],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .short, name: String(shortName)),
                valueName: name,
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "\(name.capitalized) parameter",
                discussion: nil
            )
        }

        private func createShortFlag(
            name: String,
            shortName: Character,
            isOptional: Bool = true
        ) -> ArgumentInfoV0 {
            ArgumentInfoV0(
                kind: .flag,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: isOptional,
                isRepeating: false,
                parsingStrategy: .default,
                names: [
                    ArgumentInfoV0.NameInfoV0(kind: .short, name: String(shortName)),
                    ArgumentInfoV0.NameInfoV0(kind: .long, name: name),
                ],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .short, name: String(shortName)),
                valueName: name,
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "\(name.capitalized) flag",
                discussion: nil
            )
        }

        @Test
        func handlesShortOptions() throws {
            let nameArg = self.createShortOption(name: "name", shortName: "n")
            let formatArg = self.createShortOption(name: "format", shortName: "f")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, formatArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["-n", "TestName", "-f", "json"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("-n"))
            #expect(result.contains("TestName"))
            #expect(result.contains("-f"))
            #expect(result.contains("json"))
        }

        @Test
        func handlesShortFlags() throws {
            let verboseFlag = self.createShortFlag(name: "verbose", shortName: "v")
            let debugFlag = self.createShortFlag(name: "debug", shortName: "d")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [verboseFlag, debugFlag])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["-v", "-d"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("-v"))
            #expect(result.contains("-d"))
        }

        @Test
        func handlesCombinedShortFlags() throws {
            let verboseFlag = self.createShortFlag(name: "verbose", shortName: "v")
            let debugFlag = self.createShortFlag(name: "debug", shortName: "d")
            let forceFlag = self.createShortFlag(name: "force", shortName: "f")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [verboseFlag, debugFlag, forceFlag])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test combined short flags like -vdf
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["-vdf"],
                toolInfoJson: toolInfoJSON
            )

            // Should expand to individual flags
            #expect(result.contains("-v"))
            #expect(result.contains("-d"))
            #expect(result.contains("-f"))
        }

        @Test
        func handlesShortOptionWithEqualsSign() throws {
            let nameArg = self.createShortOption(name: "name", shortName: "n")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["-n=TestName"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("-n"))
            #expect(result.contains("TestName"))
        }

        // MARK: - Advanced Terminator Tests

        @Test
        func handlesTerminatorSeparation() throws {
            let nameArg = self.createRequiredOption(name: "name")
            let filesArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .postTerminator,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "files")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "files"),
                valueName: "files",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Input files",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg, filesArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test that options before -- are parsed as options, after -- as positional
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestName", "--", "--file1", "--file2", "-option"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestName"))
            #expect(result.contains("--file1"))
            #expect(result.contains("--file2"))
            #expect(result.contains("-option"))
        }

        @Test
        func handlesEmptyTerminator() throws {
            let nameArg = self.createRequiredOption(name: "name")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [nameArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test terminator with no arguments after it
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestName", "--"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestName"))
        }

        @Test
        func handlesMultipleTerminators() throws {
            let filesArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .postTerminator,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "files")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "files"),
                valueName: "files",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Input files",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [filesArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test multiple terminators - subsequent ones should be treated as values
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--", "file1", "--", "file2"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("file1"))
            #expect(result.contains("--")) // Second -- should be treated as a value
            #expect(result.contains("file2"))
        }

        // MARK: - Array/Repeating Argument Tests

        @Test
        func handlesRepeatingOptions() throws {
            let includeArg = self.createRequiredOption(
                name: "include",
                isRepeating: true
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [includeArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--include", "path1", "--include", "path2", "--include", "path3"],
                toolInfoJson: toolInfoJSON
            )

            // Should preserve multiple instances
            #expect(result.filter { $0 == "--include" }.count == 3)
            #expect(result.contains("path1"))
            #expect(result.contains("path2"))
            #expect(result.contains("path3"))
        }

        @Test
        func handlesRepeatingOptionsWithUpToNextOption() throws {
            let filesArg = self.createRequiredOption(
                name: "files",
                parsingStrategy: .upToNextOption,
                isRepeating: true
            )
            let outputArg = self.createRequiredOption(name: "output")

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [filesArg, outputArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--files", "file1.swift", "file2.swift", "file3.swift", "--output", "result.txt"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--files"))
            #expect(result.contains("file1.swift"))
            #expect(result.contains("file2.swift"))
            #expect(result.contains("file3.swift"))
            #expect(result.contains("--output"))
            #expect(result.contains("result.txt"))
        }

        @Test
        func handlesArrayOfFlags() throws {
            let verboseFlag = ArgumentInfoV0(
                kind: .flag,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true, // Repeating flag (counts verbosity level)
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "verbose")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "verbose"),
                valueName: "verbose",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Increase verbosity level",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [verboseFlag])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--verbose", "--verbose", "--verbose"],
                toolInfoJson: toolInfoJSON
            )

            // Should preserve all verbose flags (for counting)
            #expect(result.filter { $0 == "--verbose" }.count == 3)
        }

        @Test
        func handlesEmptyRepeatingArguments() throws {
            let filesArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "files")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "files"),
                valueName: "files",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Input files",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [filesArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Should handle no input for optional repeating arguments
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: [],
                toolInfoJson: toolInfoJSON
            )

            // For optional repeating arguments, empty input should be valid
            #expect(result.isEmpty || result.allSatisfy { !$0.hasSuffix(".swift") })
        }

        // MARK: - Comprehensive Parsing Strategy Tests

        @Test
        func handlesScanningForValueStrategy() throws {
            let arg1 = self.createRequiredOption(
                name: "name",
                parsingStrategy: .scanningForValue
            )
            let arg2 = self.createRequiredOption(
                name: "format",
                parsingStrategy: .scanningForValue
            )
            let arg3 = self.createRequiredOption(
                name: "input",
                parsingStrategy: .scanningForValue
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [arg1, arg2, arg3])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test 1: Normal order
            let result1 = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "Foo", "--format", "Bar", "--input", "Baz"],
                toolInfoJson: toolInfoJSON
            )
            #expect(result1.contains("--name"))
            #expect(result1.contains("Foo"))
            #expect(result1.contains("--format"))
            #expect(result1.contains("Bar"))
            #expect(result1.contains("--input"))
            #expect(result1.contains("Baz"))

            // Test 2: Scanning finds values after other options
            let result2 = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "--format", "Foo", "Bar", "--input", "Baz"],
                toolInfoJson: toolInfoJSON
            )
            #expect(result2.contains("Foo"))
            #expect(result2.contains("Bar"))
            #expect(result2.contains("Baz"))
        }

        @Test
        func handlesUnconditionalStrategy() throws {
            let arg1 = self.createRequiredOption(
                name: "name",
                parsingStrategy: .unconditional
            )
            let arg2 = self.createRequiredOption(
                name: "format",
                parsingStrategy: .unconditional
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [arg1, arg2])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            // Test unconditional parsing - takes next value regardless
            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "--name", "--format", "--format"],
                toolInfoJson: toolInfoJSON
            )

            // Should treat option names as values
            #expect(result.contains("--name"))
            #expect(result.contains("--format"))
        }

        @Test
        func handlesAllRemainingInputStrategy() throws {
            let remainingArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
                parsingStrategy: .allRemainingInput,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "remaining")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "remaining"),
                valueName: "remaining",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Remaining arguments",
                discussion: nil
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(arguments: [remainingArg])
            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["file1.swift", "file2.swift", "--unknown", "value"],
                toolInfoJson: toolInfoJSON
            )

            // All remaining input should be captured
            #expect(result.contains("file1.swift"))
            #expect(result.contains("file2.swift"))
            #expect(result.contains("--unknown"))
            #expect(result.contains("value"))
        }

        @Test
        func handlesTerminatorParsing() throws {
            let postTerminatorArg = ArgumentInfoV0(
                kind: .positional,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: true,
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

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)
            let commandInfo = self.createTestCommand(
                arguments: [
                    self.createRequiredOption(name: "name"),
                    postTerminatorArg,
                ]
            )

            let toolInfoJSON = ToolInfoV0(command: commandInfo)

            let result = try promptingSystem.createCLIArgs(
                predefinedArgs: ["--name", "TestPackage", "--", "arg1", "arg2"],
                toolInfoJson: toolInfoJSON
            )

            #expect(result.contains("--name"))
            #expect(result.contains("TestPackage"))
            // Post-terminator args should be handled separately
        }

        @Test
        func handlesConditionalNilSuffixForOptions() throws {
            // Test that "nil" suffix only shows for optional arguments without defaults

            // Test optional option without default, should show nil suffix
            let optionalWithoutDefault = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "optional-param")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "optional-param"),
                valueName: "optional-param",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Optional parameter",
                discussion: nil
            )

            // Test optional option with default, should NOT show nil suffix
            let optionalWithDefault = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: true,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "output")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "output"),
                valueName: "output",
                defaultValue: "stdout",
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Output parameter",
                discussion: nil
            )

            // Test required option, should NOT show nil suffix
            let requiredOption = ArgumentInfoV0(
                kind: .option,
                shouldDisplay: true,
                sectionTitle: nil,
                isOptional: false,
                isRepeating: false,
                parsingStrategy: .default,
                names: [ArgumentInfoV0.NameInfoV0(kind: .long, name: "name")],
                preferredName: ArgumentInfoV0.NameInfoV0(kind: .long, name: "name"),
                valueName: "name",
                defaultValue: nil,
                allValueStrings: nil,
                allValueDescriptions: nil,
                completionKind: nil,
                abstract: "Name parameter",
                discussion: nil
            )

            // Optional without default should allow nil suffix
            #expect(optionalWithoutDefault.isOptional == true)
            #expect(optionalWithoutDefault.defaultValue == nil)
            let shouldShowNilForOptionalWithoutDefault = optionalWithoutDefault.isOptional && optionalWithoutDefault
                .defaultValue == nil
            #expect(shouldShowNilForOptionalWithoutDefault == true)

            // Optional with default should NOT allow nil suffix
            #expect(optionalWithDefault.isOptional == true)
            #expect(optionalWithDefault.defaultValue == "stdout")
            let shouldShowNilForOptionalWithDefault = optionalWithDefault.isOptional && optionalWithDefault
                .defaultValue == nil
            #expect(shouldShowNilForOptionalWithDefault == false)

            // Required should NOT allow nil suffix
            #expect(requiredOption.isOptional == false)
            let shouldShowNilForRequired = requiredOption.isOptional && requiredOption.defaultValue == nil
            #expect(shouldShowNilForRequired == false)
        }

        @Test
        func handlesTemplateWithNoArguments() throws {
            let noArgsCommand = CommandInfoV0(
                superCommands: [],
                shouldDisplay: true,
                commandName: "no-args-template",
                abstract: "Template with no arguments",
                discussion: "A template that requires no user input",
                defaultSubcommand: nil,
                subcommands: [],
                arguments: []
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)

            let toolInfoJSON = ToolInfoV0(command: noArgsCommand)

            let result = try promptingSystem.createCLIArgs(predefinedArgs: [], toolInfoJson: toolInfoJSON)

            #expect(result.isEmpty)

            #expect(throws: TemplateError.unexpectedArguments(["--some-flag", "extra-arg"]).self) {
                try promptingSystem.createCLIArgs(
                    predefinedArgs: ["--some-flag", "extra-arg"],
                    toolInfoJson: toolInfoJSON
                )
            }
        }

        @Test
        func handlesTemplateWithEmptyArgumentsArray() throws {
            // Test template with empty arguments array (not nil, but empty)
            let emptyArgsCommand = CommandInfoV0(
                superCommands: [],
                shouldDisplay: true,
                commandName: "empty-args-template",
                abstract: "Template with empty arguments array",
                discussion: "A template with an empty arguments array",
                defaultSubcommand: nil,
                subcommands: [],
                arguments: [] // Explicitly empty array
            )

            let promptingSystem = TemplateCLIConstructor(hasTTY: false)

            let toolInfoJSON = ToolInfoV0(command: emptyArgsCommand)
            let result = try promptingSystem.createCLIArgs(predefinedArgs: [], toolInfoJson: toolInfoJSON)

            #expect(result.isEmpty)
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
        @Test(.disabled("Fatal error: Unexpectedly found nil while unwrapping an Optional value"))
        func createsCoordinatorWithValidConfiguration() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: InMemoryFileSystem())

                    let coordinator = TemplatePluginCoordinator(
                        buildSystem: .native,
                        swiftCommandState: tool,
                        scratchDirectory: tempDir,
                        template: "ExecutableTemplate",
                        branches: []
                    )

                    // Test coordinator functionality by verifying it can handle basic operations
                    #expect(coordinator.buildSystem == .native)
                    #expect(coordinator.scratchDirectory == tempDir)

                }
            }
        }

        @Test(.skip("Intermittent failures when loading package graph, needs investigating"))
        func loadsPackageGraphInTemporaryWorkspace() async throws {
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(
                        options: options,
                        fileSystem: InMemoryFileSystem()
                    )
                    let workspaceDir = tempDir.appending("workspace")
                    try tool.fileSystem.copy(from: templatePath, to: workspaceDir)

                    let coordinator = TemplatePluginCoordinator(
                        buildSystem: .native,
                        swiftCommandState: tool,
                        scratchDirectory: workspaceDir,
                        template: "ExecutableTemplate",
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
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    let coordinator = TemplatePluginCoordinator(
                        buildSystem: .native,
                        swiftCommandState: tool,
                        scratchDirectory: tempDir,
                        template: "NonexistentTemplate",
                        branches: []
                    )

                    // Test that coordinator handles invalid template name by throwing appropriate error
                    await #expect(throws: (any Error).self) {
                        _ = try await coordinator.loadPackageGraph()
                    }
                }
            }
        }
    }

    // MARK: - Template Plugin Runner Tests

    @Suite(
        .skip("Intermittent failures when loading package graph, needs investigating"),
        .tags(
            Tag.TestSize.medium,
            Tag.Feature.Command.Package.Init,
        ),
    )
    struct TemplatePluginRunnerTests {
        @Test
        func handlesPluginExecutionForValidPackage() async throws {
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { _ in
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test that TemplatePluginRunner can handle static execution
                    try await withTaskLocalWorkingDirectory(templatePath) {
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
        }

        @Test()
        func handlesPluginExecutionStaticAPI() async throws {
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")
                    try makeDirectories(packagePath)

                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test that TemplatePluginRunner static API works with valid input
                    try await withTaskLocalWorkingDirectory(templatePath) {
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
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")

                    try await withTaskLocalWorkingDirectory(tempDir) {
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
        }

        @Test()
        func writesPackageStructureWithTemplateDependency() async throws {
            try await fixture(name: "Miscellaneous/InitTemplates/ExecutableTemplate") { templatePath in
                try await testWithTemporaryDirectory { tempDir in
                    let packagePath = tempDir.appending("TestPackage")

                    try await withTaskLocalWorkingDirectory(tempDir) {
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
        }

        @Test
        func handlesInvalidTemplatePath() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
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

                    try await withTaskLocalWorkingDirectory(tempDir) {
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

                try await withTaskLocalWorkingDirectory(templateRepoPath) {
                    let sourceControlURL = SourceControlURL(stringLiteral: templateRepoPath.pathString)
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    // Test Git template resolution
                    let sourceControlRequirement = SwiftRefactor.PackageDependency.SourceControl.Requirement
                        .branch("main")

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
        }

        @Test()
        func packageDependencyBuildingWithVersionResolution() async throws {
            try await testWithTemporaryDirectory { tempDir in
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let options = try GlobalOptions.parse([])
                    let tool = try SwiftCommandState.makeMockState(options: options)

                    let lowerBoundVersion = Version(stringLiteral: "1.2.0")
                    let higherBoundVersion = Version(stringLiteral: "3.0.0")

                    // Test version requirement resolution integration
                    let versionResolver = DependencyRequirementResolver(
                        packageIdentity: "test.package",
                        templateURL: nil,
                        swiftCommandState: tool,
                        exact: nil,
                        revision: nil,
                        branch: nil,
                        from: lowerBoundVersion,
                        upToNextMinorFrom: nil,
                        to: higherBoundVersion
                    )

                    let sourceControlRequirement = try await versionResolver.resolveSourceControl()
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
                try await withTaskLocalWorkingDirectory(tempDir) {
                    let packagePath = tempDir.appending("TestPackage")
                    try FileManager.default.createDirectory(
                        at: packagePath.asURL,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
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
        }

        @Test(.disabled("Disabled as it is already tested via swift package init"))
        func standardPackageInitializerFallback() async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let packagePath = tmpPath.appending("Foo")
                try localFileSystem.createDirectory(packagePath)

                let options = try GlobalOptions.parse(["--package-path", packagePath.pathString])
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
                #expect(tool.fileSystem.exists(packagePath.appending("Package.swift")))
                #expect(try localFileSystem
                    .getDirectoryContents(packagePath.appending("Sources").appending("TestPackage")) ==
                        ["TestPackage.swift"]
                )
            }
        }
    }

    @Suite(
        .tags(
            Tag.TestSize.large,
            Tag.Feature.Command.Test,
        ),
    )
    struct TestTemplateCommandTests {
        @Suite(
            .skipSwiftCISelfHosted(
                "Caught error: /tmp/Miscellaneous_DirectoryManagerFinalize.FBjvCq/clean-up/Package.swift doesn't exist in file system"
            ),
            .tags(
                Tag.TestSize.small,
                Tag.Feature.Command.Test,
            ),
        )
        struct TemplateTestingDirectoryManagerTests {
            @Test
            func createOutputDirectory() throws {
                let options = try GlobalOptions.parse([])

                let fileSystem = InMemoryFileSystem()
                try fileSystem.createDirectory(AbsolutePath("/tmp"), recursive: true)

                let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: fileSystem)

                let tempDirectoryPath = AbsolutePath("/tmp/test")
                try tool.fileSystem.createDirectory(tempDirectoryPath)

                let templateTestingDirectoryManager = TemplateTestingDirectoryManager(
                    fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope
                )

                let outputDirectory = tempDirectoryPath.appending(component: "foo")

                try templateTestingDirectoryManager.createOutputDirectory(
                    outputDirectoryPath: outputDirectory,
                    swiftCommandState: tool
                )

                #expect(try tool.fileSystem.isDirectory(outputDirectory))
            }

            @Test
            func omitOutputDirectoryCreation() throws {
                let options = try GlobalOptions.parse([])
                let fileSystem = InMemoryFileSystem()
                try fileSystem.createDirectory(AbsolutePath("/tmp"), recursive: true)

                let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: fileSystem)

                let tempDirectory = AbsolutePath("/tmp/test")
                try tool.fileSystem.createDirectory(tempDirectory)

                let templateTestingDirectoryManager = TemplateTestingDirectoryManager(
                    fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope
                )

                let outputDirectory = tempDirectory.appending(component: "foo")
                try tool.fileSystem.createDirectory(outputDirectory)

                try templateTestingDirectoryManager.createOutputDirectory(
                    outputDirectoryPath: outputDirectory,
                    swiftCommandState: tool
                )

                // should not throw error if the directory exists
                #expect(try tool.fileSystem.isDirectory(outputDirectory))
            }

            @Test
            func ManifestFileExistsInOutputDirectory() throws {
                let fileSystem = InMemoryFileSystem()
                let tmpDir = AbsolutePath("/tmp")
                try fileSystem.createDirectory(tmpDir, recursive: true)

                let options = try GlobalOptions.parse(["--package-path", tmpDir.pathString])

                let outputDirectory = tmpDir.appending(component: "foo")

                try fileSystem.createDirectory(outputDirectory)
                fileSystem.createEmptyFiles(at: outputDirectory, files: "/Package.swift")

                let tool = try SwiftCommandState.makeMockState(options: options, fileSystem: fileSystem)

                let templateTestingDirectoryManager = TemplateTestingDirectoryManager(
                    fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope
                )

                #expect(throws: DirectoryManagerError.foundManifestFile(path: outputDirectory)) {
                    try templateTestingDirectoryManager.createOutputDirectory(
                        outputDirectoryPath: outputDirectory,
                        swiftCommandState: tool
                    )
                }
            }
        }

        // to be tested

        /*

         test commandFragments prompting

         test dry Run

         redirectStDoutandStDerr and deferral

         End2End for this, 1 where generation errror, 1 build errorr, one thats clean
         */
    }
}


