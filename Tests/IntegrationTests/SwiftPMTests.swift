/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import _IntegrationTestSupport
import _InternalTestSupport
import Testing
import Basics
import struct SPMBuildCore.BuildSystemProvider
@Suite(
    .tags(Tag.TestSize.large)
)
private struct SwiftPMTests {
    @Test(.requireHostOS(.macOS))
    func binaryTargets() async throws {
        try await withKnownIssue("error: the path does not point to a valid framework:") {
            try await binaryTargetsFixture { fixturePath in
                do {
                    await withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let runOutput = try await executeSwiftRun(fixturePath, "exe", buildSystem: .native)
                        #expect(!runOutput.stderr.contains("error:"))
                        #expect(
                            runOutput.stdout == """
                            SwiftFramework()
                            Library(framework: SwiftFramework.SwiftFramework())

                            """
                        )
                    }
                }

                do {
                    await withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let runOutput = try await executeSwiftRun(fixturePath, "cexe", buildSystem: .native)
                        #expect(!runOutput.stderr.contains("error:"))
                        #expect(runOutput.stdout.contains("<CLibrary: "))
                    }
                }

                do {
                    let invalidPath = fixturePath.appending(component: "SwiftFramework.xcframework")

                    await #expect {
                        try await executeSwiftPackage(
                            fixturePath,
                            extraArgs: ["compute-checksum", invalidPath.pathString]
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
                        fixturePath, extraArgs:  ["compute-checksum", validPath.pathString]
                    )
                    #expect(
                        packageOutput.stdout.spm_chomp()
                            == "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158"
                    )
                }
            }
        }
    }

    @Test(
        .bug(
            "https://github.com/swiftlang/swift-package-manager/issues/8416",
            "[Linux] swift run using --build-system swiftbuild fails to run executable"
        ),
        .bug(
            "https://github.com/swiftlang/swift-package-manager/issues/8514",
            "[Windows] Integration test SwiftPMTests.packageInitExecutable with --build-system swiftbuild is skipped"
        ),
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
            try await executeSwiftPackage(packagePath, extraArgs: ["init", "--type", "executable"])
            try await executeSwiftBuild(packagePath, buildSystem: buildSystemProvider)

            try await withKnownIssue(
                "Error while loading shared libraries: libswiftCore.so: cannot open shared object file: No such file or directory"
            ) {
                // The 'native' build system uses 'swiftc' as the linker driver, which adds an RUNPATH to the swift
                // runtime libraries in the SDK.
                // 'swiftbuild' directly calls clang, which does not add the extra RUNPATH, so runtime libraries cannot
                // be found.
                let runOutput = try await executeSwiftRun(
                    packagePath,
                    nil,
                    buildSystem: buildSystemProvider,
                )
                #expect(!runOutput.stderr.contains("error:"))
                #expect(runOutput.stdout.contains("Hello, world!"))
            } when: {
                (buildSystemProvider == .swiftbuild && .windows == ProcessInfo.hostOperatingSystem)
                || (buildSystemProvider == .swiftbuild && .linux == ProcessInfo.hostOperatingSystem && CiEnvironment.runningInSelfHostedPipeline)
            }
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
            try await executeSwiftPackage(packagePath, extraArgs: ["init", "--type", "library"])
            try await withKnownIssue(
                """
                Linux: /lib/x86_64-linux-gnu/Scrt1.o:function _start: error: undefined reference to 'main'
                Windows: lld-link: error: subsystem must be defined
                MacOS: Could not find or use auto-linked library 'Testing': library 'Testing' not found
                """,
                isIntermittent: true
            ) {
                try await executeSwiftBuild(packagePath, buildSystem: buildSystemProvider)
                let testOutput = try await executeSwiftTest(packagePath, buildSystem: buildSystemProvider)
                // #expect(testOutput.returnCode == .terminated(code: 0))
                #expect(!testOutput.stderr.contains("error:"))

            } when: {
                (buildSystemProvider == .swiftbuild) || (buildSystemProvider == .xcode && ProcessInfo.hostOperatingSystem == .macOS)
            }
        }
    }

    @Test(.requireHostOS(.macOS))
    func testArchCustomization() async throws {
        try await  withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(packagePath, extraArgs: ["init", "--type", "executable"])
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
                try await executeSwiftBuild(packagePath, extraArgs: ["--arch", arch])
                let fooPath = try AbsolutePath(
                    validating: ".build/\(arch)-apple-macosx/debug/foo",
                    relativeTo: packagePath
                )
                #expect(localFileSystem.exists(fooPath))
            }

            // let args =
            //     [swiftBuild.pathString, "--package-path", packagePath.pathString]
            //         + archs.flatMap { ["--arch", $0] }
            try await executeSwiftBuild(packagePath, extraArgs: archs.flatMap { ["--arch", $0] })

            let fooPath = try AbsolutePath(
                validating: ".build/apple/Products/Debug/foo", relativeTo: packagePath
            )
            #expect(localFileSystem.exists(fooPath))

            let objectsDir = try AbsolutePath(
                validating:
                ".build/apple/Intermediates.noindex/foo.build/Debug/foo.build/Objects-normal",
                relativeTo: packagePath
            )
            for arch in archs {
                #expect(localFileSystem.isDirectory(objectsDir.appending(component: arch)))
            }
        }
    }

    @Test(.requireSwift6_2)
    func testCodeCoverageMergedAcrossSubprocesses() async throws {
        try await withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "test-package-coverage")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(packagePath, extraArgs: ["init", "--type", "empty"])
            try await executeSwiftPackage(packagePath, extraArgs: ["add-target", "--type", "test", "ReproTests"])
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
            let expectedCoveragePath = try await executeSwiftTest(packagePath, extraArgs: ["--show-coverage-path"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            try await executeSwiftTest(packagePath, extraArgs: ["--enable-code-coverage", "--disable-xctest"])
            let coveragePath = try AbsolutePath(validating: expectedCoveragePath)

            // Check the coverage path exists.
            #expect(localFileSystem.exists(coveragePath))

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
            let subjectCoverage = coverage.data.first?.files.first(where: { $0.filename.hasSuffix("Subject.swift") })
            #expect(subjectCoverage?.summary.functions.count == 2)
            #expect(subjectCoverage?.summary.functions.covered == 2)
            #expect(subjectCoverage?.summary.functions.percent == 100)

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
        }
    }
}
