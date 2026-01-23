//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import _IntegrationTestSupport
import _InternalTestSupport
import Testing
import Basics
import enum PackageModel.BuildConfiguration
import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .tags(Tag.TestSize.large)
)
private struct SwiftPMTests {
    @Test(.requireHostOS(.macOS), arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func binaryTargets(buildSystem: BuildSystemProvider.Kind) async throws {
        try await binaryTargetsFixture { fixturePath in
            do {
                let runOutput = try await executeSwiftRun(
                    fixturePath,
                    "exe",
                    buildSystem: buildSystem,
                )
                #expect(!runOutput.stderr.contains("error:"))
                #expect(
                    runOutput.stdout == """
                            SwiftFramework()
                            Library(framework: SwiftFramework.SwiftFramework())

                            """
                )
            }

            do {
                let runOutput = try await executeSwiftRun(fixturePath, "cexe", buildSystem: buildSystem)
                #expect(!runOutput.stderr.contains("error:"))
                #expect(runOutput.stdout.contains("<CLibrary: "))
            }

            do {
                let invalidPath = fixturePath.appending(component: "SwiftFramework.xcframework")

                await #expect {
                    try await executeSwiftPackage(
                        fixturePath,
                        extraArgs: ["compute-checksum", invalidPath.pathString],
                        buildSystem: .native,
                    )
                } throws: { error in
                    // The order of supported extensions is not ordered, and changes.
                    //   '...supported extensions are: zip, tar.gz, tar'
                    //   '...supported extensions are: tar.gz, zip, tar'
                    // Only check for the start of that string.
                    // TODO: error.stderr.contains("error: unexpected file type; supported extensions are:")
                    return true
                }

                let validPath = fixturePath.appending(component: "SwiftFramework.zip")
                let packageOutput = try await executeSwiftPackage(
                    fixturePath,
                    extraArgs: ["compute-checksum", validPath.pathString],
                    buildSystem: .native,
                )
                #expect(
                    packageOutput.stdout.spm_chomp()
                    == "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158"
                )
            }
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.Executable,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func packageInitExecutable(_ buildSystemProvider: BuildSystemProvider.Kind) throws {
        try withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "executable"],
                buildSystem: buildSystemProvider,
            )
            try await executeSwiftBuild(
                packagePath,
                buildSystem: buildSystemProvider,
            )

            let runOutput = try await executeSwiftRun(
                packagePath,
                nil,
                buildSystem: buildSystemProvider,
            )
            #expect(!runOutput.stderr.contains("error:"))
            #expect(runOutput.stdout.contains("Hello, world!"))
        }
    }

    @Test(
        .bug(id: 0, "SWBINTTODO: Linux: /lib/x86_64-linux-gnu/Scrt1.o:function _start: error:"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8380", "lld-link: error: subsystem must be defined"),
        .bug(id: 0, "SWBINTTODO: MacOS: Could not find or use auto-linked library 'Testing': library 'Testing' not found"),
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.Library,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func packageInitLibrary(_ buildSystemProvider: BuildSystemProvider.Kind) async throws {
        try await withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "library"],
                buildSystem: buildSystemProvider,
            )
            try await withKnownIssue(
                """
                Linux: /lib/x86_64-linux-gnu/Scrt1.o:function _start: error: undefined reference to 'main'
                Windows: lld-link: error: subsystem must be defined
                MacOS: Could not find or use auto-linked library 'Testing': library 'Testing' not found
                """,
                isIntermittent: true
            ) {
                try await executeSwiftBuild(
                    packagePath,
                    buildSystem: buildSystemProvider,
                )
                let testOutput = try await executeSwiftTest(
                    packagePath,
                    buildSystem: buildSystemProvider,
                )
                // #expect(testOutput.returnCode == .terminated(code: 0))
                #expect(!testOutput.stderr.contains("error:"))

            } when: {
                (buildSystemProvider == .swiftbuild) || (buildSystemProvider == .xcode && ProcessInfo.hostOperatingSystem == .macOS)
            }
        }
    }

    @Test(
        .requireHostOS(.macOS),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testArchCustomization(buildSystem: BuildSystemProvider.Kind) async throws {
        try await  withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "executable"],
                buildSystem: buildSystem,
            )
            // delete any files generated
            for entry in try localFileSystem.getDirectoryContents(
                packagePath.appending(components: "Sources")
            ) {
                try localFileSystem.removeFileTree(
                    packagePath.appending(components: "Sources", entry)
                )
            }
            try localFileSystem.writeFileContents(
                AbsolutePath(validating: "Sources/main.m", relativeTo: packagePath)
            ) {
                $0.send("int main() {}")
            }
            let archs = ["x86_64", "arm64"]

            for arch in archs {
                try await executeSwiftBuild(
                    packagePath,
                    extraArgs: ["--arch", arch],
                    buildSystem: buildSystem,
                )
                let fooPath: AbsolutePath
                switch buildSystem {
                case .native:
                    fooPath = try AbsolutePath(
                        validating: ".build/\(arch)-apple-macosx/debug/foo",
                        relativeTo: packagePath
                    )
                case .swiftbuild:
                    fooPath = try AbsolutePath(
                        validating: ".build/out/Products/Debug/foo",
                        relativeTo: packagePath
                    )
                default:
                    preconditionFailure("Unsupported backend: \(buildSystem)")
                }
                #expect(localFileSystem.exists(fooPath))
                // Check the product has the expected slice
                #expect(try sh("/usr/bin/file", fooPath.pathString).stdout.contains(arch))
            }

            try await executeSwiftBuild(
                packagePath,
                extraArgs: archs.flatMap { ["--arch", $0] },
                buildSystem: buildSystem,
            )

            let fooPath: AbsolutePath
            let hostArch: String
            #if arch(x86_64)
            hostArch = "x86_64"
            #elseif arch(arm64)
            hostArch = "arm64"
            #else
            precondition("Unsupported platform or host arch for test")
            #endif
            switch buildSystem {
            case .native:
                fooPath = try AbsolutePath(
                    validating: ".build/apple/Products/Debug/foo", relativeTo: packagePath
                )
            case .swiftbuild:
                fooPath = try AbsolutePath(
                    validating: ".build/out/Products/Debug/foo",
                    relativeTo: packagePath
                )
            default:
                preconditionFailure("Unsupported backend: \(buildSystem)")
            }
            #expect(localFileSystem.exists(fooPath))
            // Check the product has the expected slices
            let fileOutput = try sh("/usr/bin/file", fooPath.pathString).stdout
            for arch in archs {
                #expect(fileOutput.contains(arch))
            }
        }
    }

    @Test(
        .requireSwift6_2,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .defect),
        .tags(
            .UserWorkflow,
            .Feature.CodeCoverage,
            .Feature.Command.Package.Init,
            .Feature.Command.Package.AddTarget,
            .Feature.Command.Test,
            .Feature.PackageType.Empty,
            .Feature.TargetType.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func testCodeCoverageMergedAcrossSubprocesses(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await withTemporaryDirectory(removeTreeOnDeinit: false) { tmpDir in
            let packagePath = tmpDir.appending(component: "test-package-coverage")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["init", "--type", "empty"],
                buildSystem: buildSystem,
            )
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["add-target", "--type", "test", "ReproTests"],
                buildSystem: buildSystem,
            )
            try localFileSystem.writeFileContents(
                AbsolutePath(validating: "Tests/ReproTests/Subject.swift", relativeTo: packagePath),
                string: """
                struct Subject {
                    static func a() { _ = "a" }
                    static func b() { _ = "b" }
                }
                """
            )
            try localFileSystem.writeFileContents(
                AbsolutePath(validating: "Tests/ReproTests/ReproTests.swift", relativeTo: packagePath),
                string: """
                import Testing
                import class Foundation.ProcessInfo
                @Suite struct Suite {
                    @Test func testProfilePathCanary() throws {
                        let pattern = try #require(ProcessInfo.processInfo.environment["LLVM_PROFILE_FILE"])
                        #expect(pattern.hasSuffix(".%p.profraw"))
                    }
                    @Test func testA() async { await #expect(processExitsWith: .success) { Subject.a() } }
                    @Test func testB() async { await #expect(processExitsWith: .success) { Subject.b() } }
                }
                """
            )
            let expectedCoveragePath = try await getCoveragePath(
                packagePath,
                with: BuildData(buildSystem: buildSystem, config: config),
            )

            try await executeSwiftTest(
                packagePath,
                configuration: config,
                extraArgs: ["--enable-code-coverage", "--disable-xctest"],
                throwIfCommandFails: true,
                buildSystem: buildSystem,
            )
            let coveragePath = try AbsolutePath(validating: expectedCoveragePath)

            // Check the coverage path exists.
            // the CoveragePath file does not exists in Linux platform build
            expectFileExists(at: coveragePath)

            // This resulting coverage file should be merged JSON, with a schema that valiades against this subset.
            struct Coverage: Codable {
                var data: [Entry]
                struct Entry: Codable {
                    var files: [File]
                    struct File: Codable {
                        var filename: String
                        var summary: Summary
                        struct Summary: Codable {
                            var functions: Functions
                            struct Functions: Codable {
                                var count, covered: Int
                                var percent: Double
                            }
                        }
                    }
                }
            }
            let coverageJSON = try localFileSystem.readFileContents(coveragePath)
            let coverage = try JSONDecoder().decode(Coverage.self, from: Data(coverageJSON.contents))

            // Check for 100% coverage for Subject.swift, which should happen because the per-PID files got merged.
            try withKnownIssue(isIntermittent: true) {
                let data = try #require(coverage.data.first, "covege JSON = \(coverage)")
                let subjectCoverage = try #require(data.files.first(where: { $0.filename.hasSuffix("Subject.swift") }), "covege JSON = \(data.files)")
                #expect(subjectCoverage.summary.functions.count == 2)
                #expect(subjectCoverage.summary.functions.covered == 2)
                #expect(subjectCoverage.summary.functions.percent == 100)

                // Check the directory with the coverage path contains the profraw files.
                let coverageDirectory = coveragePath.parentDirectory
                let coverageDirectoryContents = try localFileSystem.getDirectoryContents(coverageDirectory)

                // SwiftPM uses an LLVM_PROFILE_FILE that ends with ".%p.profraw", which we validated in the test above.
                // Let's first check all the files have the expected extension.
                let profrawFiles = coverageDirectoryContents.filter { $0.hasSuffix(".profraw") }

                // Then check that %p expanded as we expected: to something that plausibly looks like a PID.
                for profrawFile in profrawFiles {
                    let shouldBePID = try #require(profrawFile.split(separator: ".").dropLast().last)
                    #expect(Int(shouldBePID) != nil)
                }

                // Group the files by binary identifier (have a different prefix, before the per-PID suffix).
                let groups = Dictionary(grouping: profrawFiles) { path in path.split(separator: ".").dropLast(2) }.values

                // Check each group has 3 files: one per PID (the above suite has 2 exit tests => 2 forks => 3 PIDs total).
                for binarySpecificProfrawFiles in groups {
                    #expect(binarySpecificProfrawFiles.count == 3)
                }
            } when: {
                [.linux, .windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
            }
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }
}
