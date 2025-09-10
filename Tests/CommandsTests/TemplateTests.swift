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
@testable import PackageModel

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


import struct TSCBasic.ByteString
import class TSCBasic.BufferedOutputByteStream
import enum TSCBasic.JSON
import class Basics.AsyncProcess


@Suite("Template Tests") struct TestTemplates {


    //maybe add tags
    @Test func resolveSourceTests() throws {

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

    @Test func testValidGitURL() async throws {

        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        try resolver.validate(templateSource: .git, directory: nil, url: "https://github.com/apple/swift", packageID: nil)

        // Check that nothing was emitted (i.e., no error for valid URL)
        #expect(tool.observabilityScope.errorsReportedInAnyScope == false)

    }

    @Test func testInvalidGitURL() throws {
        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidGitURL("invalid-url").self) {
            try resolver.validate(templateSource: .git, directory: nil, url: "invalid-url", packageID: nil)
        }
    }

    @Test func testValidRegistryID() throws {
        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "mona.LinkedList")

        // Check that nothing was emitted (i.e., no error for valid URL)
        #expect(tool.observabilityScope.errorsReportedInAnyScope == false)
    }

    @Test func testInvalidRegistryID() throws {

        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidRegistryIdentity("invalid-id").self) {
            try resolver.validate(templateSource: .registry, directory: nil, url: nil, packageID: "invalid-id")
        }
    }

    @Test func testlocalMissingPath() throws {
        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.missingLocalPath.self) {
            try resolver.validate(templateSource: .local, directory: nil, url: nil, packageID: nil)
        }
    }

    @Test func testInvalidPath() throws {
        let options = try GlobalOptions.parse([])
        let tool = try SwiftCommandState.makeMockState(options: options)
        let resolver = DefaultTemplateSourceResolver(cwd: tool.fileSystem.currentWorkingDirectory!, fileSystem: tool.fileSystem, observabilityScope: tool.observabilityScope)

        #expect(throws: DefaultTemplateSourceResolver.SourceResolverError.invalidDirectoryPath("/fake/path/that/does/not/exist").self) {
            try resolver.validate(templateSource: .local, directory: "/fake/path/that/does/not/exist", url: nil, packageID: nil)
        }
    }

    @Test func resolveRegistryDependencyWithNoVersion() async throws {

        /* Need to do mock up of registry for this
         // if exact, from, upToNextMinorFrom and to are nil, then should return nil
         let nilRegistryDependency = try await DependencyRequirementResolver(
         packageIdentity: nil,
         swiftCommandState: tool,
         exact: nil,
         revision: "revision",
         branch: "branch",
         from: nil,
         upToNextMinorFrom: nil,
         to: nil,
         ).resolveRegistry()

         #expect(nilRegistryDependency == nil)
         */

        //TODO: Set it up
    }

    @Test func resolveRegistryDependencyTests() async throws {

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

        #expect(exactRegistryDependency == PackageDependency.Registry.Requirement.exact(lowerBoundVersion))


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

        #expect(fromToRegistryDependency == PackageDependency.Registry.Requirement.range(lowerBoundVersion ..< higherBoundVersion))

        // test up-to-next-minor-from and to
        let upToNextMinorFromToRegistryDependency = try await DependencyRequirementResolver(
            packageIdentity: nil,
            swiftCommandState: tool,
            exact: nil,
            revision: nil,
            branch: nil,
            from: nil,
            upToNextMinorFrom: lowerBoundVersion,
            to: higherBoundVersion
        ).resolveRegistry()

        #expect(upToNextMinorFromToRegistryDependency == PackageDependency.Registry.Requirement.range(lowerBoundVersion ..< higherBoundVersion))

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

        #expect(fromRegistryDependency == PackageDependency.Registry.Requirement.range(.upToNextMajor(from: lowerBoundVersion)))

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

        #expect(upToNextMinorFromRegistryDependency == PackageDependency.Registry.Requirement.range(.upToNextMinor(from: lowerBoundVersion)))


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

    // TODO: should we add edge cases to < from and from == from
    @Test func resolveSourceControlDependencyTests() throws {

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

        #expect(branchSourceControlDependency == PackageDependency.SourceControl.Requirement.branch("master"))

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

        #expect(revisionSourceControlDependency == PackageDependency.SourceControl.Requirement.revision("dae86e"))

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

        #expect(exactSourceControlDependency == PackageDependency.SourceControl.Requirement.exact(lowerBoundVersion))

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

        #expect(fromToSourceControlDependency == PackageDependency.SourceControl.Requirement.range(lowerBoundVersion ..< higherBoundVersion))

        // test up-to-next-minor-from and to
        let upToNextMinorFromToSourceControlDependency = try DependencyRequirementResolver(
            packageIdentity: nil,
            swiftCommandState: tool,
            exact: nil,
            revision: nil,
            branch: nil,
            from: nil,
            upToNextMinorFrom: lowerBoundVersion,
            to: higherBoundVersion
        ).resolveSourceControl()

        #expect(upToNextMinorFromToSourceControlDependency == PackageDependency.SourceControl.Requirement.range(lowerBoundVersion ..< higherBoundVersion))

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

        #expect(fromSourceControlDependency == PackageDependency.SourceControl.Requirement.range(.upToNextMajor(from: lowerBoundVersion)))

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

        #expect(upToNextMinorFromSourceControlDependency == PackageDependency.SourceControl.Requirement.range(.upToNextMinor(from: lowerBoundVersion)))


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
    }

    // test local
    // test git
    // test registry

    @Test func localTemplatePathResolver() async throws {
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

    // Need to add traits of not running on windows, and CI
    @Test func gitTemplatePathResolver() async throws {

        try await testWithTemporaryDirectory { path in

            let sourceControlRequirement = PackageDependency.SourceControl.Requirement.branch("main")
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
            #expect(try localFileSystem.exists(path.appending(component: "file.swift")), "Template was not fetched correctly")
        }
    }

    @Test func packageRegistryTemplatePathResolver() async throws {
        //TODO: im too lazy right now
    }

    //should we clean up after??
    @Test func initDirectoryManagerCreateTempDirs() throws {

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

    @Test func initDirectoryManagerFinalize() async throws {

        try await fixture(name: "Miscellaneous/DirectoryManagerFinalize", createGitRepo: false) { fixturePath in
            let stagingPath = fixturePath.appending("generated-package")
            let cleanupPath = fixturePath.appending("clean-up")
            let cwd = fixturePath.appending("cwd")

            let options = try GlobalOptions.parse([])
            let tool = try SwiftCommandState.makeMockState(options: options)

            // Build it. TODO: CHANGE THE XCTAsserts build to the swift testing helper function instead
            await XCTAssertBuilds(stagingPath)


            let stagingBuildPath = stagingPath.appending(".build")
            let binFile = stagingBuildPath.appending(components: try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "generated-package")
            #expect(localFileSystem.exists(binFile))
            #expect(localFileSystem.isDirectory(stagingBuildPath))


            try await TemplateInitializationDirectoryManager(
                fileSystem: tool.fileSystem,
                observabilityScope: tool.observabilityScope
            ).finalize(cwd: cwd, stagingPath: stagingPath, cleanupPath: cleanupPath, swiftCommandState: tool)

            let cwdBuildPath = cwd.appending(".build")
            let cwdBinaryFile = cwdBuildPath.appending(components: try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "generated-package")

            // Postcondition checks
            #expect(localFileSystem.exists(cwd), "cwd should exist after finalize")
            #expect(localFileSystem.exists(cwdBinaryFile) == false, "Binary should have been cleaned before copying to cwd")
        }
    }

    @Test func initPackageInitializer() throws {

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

    //tests:
    // infer package type
    // set up the template package

    //TODO: Fix here, as mocking swiftCommandState resolves to linux triple, but if testing on Darwin, runs into precondition error.
    /*
     @Test func inferInitialPackageType() async throws {

     try await fixture(name: "Miscellaneous/InferPackageType") { fixturePath in

     let options = try GlobalOptions.parse([])
     let tool = try SwiftCommandState.makeMockState(options: options)


     let libraryType = try await TemplatePackageInitializer.inferPackageType(from: fixturePath, templateName: "initialTypeLibrary", swiftCommandState: tool)


     #expect(libraryType.rawValue == "library")
     }

     }
     */
}
