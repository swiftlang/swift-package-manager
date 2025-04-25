/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import IntegrationTestSupport
import Testing
import TSCBasic
import TSCTestSupport

// TODO: This should be replaced with BuildSystem.BuildSystemProvider if 'IntegrationTests' are moved up under the swift-package-manager tests.
public enum BuildSystemProvider: String, Codable, CaseIterable {
    case native
    case swiftbuild
}

@Suite
private struct SwiftPMTests {
    @Test(.requireHostOS(.macOS))
    func binaryTargets() throws {
        withKnownIssue("error: the path does not point to a valid framework:") {
            try binaryTargetsFixture { fixturePath in
                do {
                    withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let runOutput = try sh(swiftRun, "--package-path", fixturePath, "exe")
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
                    withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let runOutput = try sh(swiftRun, "--package-path", fixturePath, "cexe")
                        #expect(!runOutput.stderr.contains("error:"))
                        #expect(runOutput.stdout.contains("<CLibrary: "))
                    }
                }

                do {
                    let invalidPath = fixturePath.appending(component: "SwiftFramework.xcframework")
                    var packageOutput = try shFails(
                        swiftPackage, "--package-path", fixturePath, "compute-checksum", invalidPath
                    )
                    #expect(
                        // The order of supported extensions is not ordered, and changes.
                        //   '...supported extensions are: zip, tar.gz, tar'
                        //   '...supported extensions are: tar.gz, zip, tar'
                        // Only check for the start of that string.
                        packageOutput.stderr.contains("error: unexpected file type; supported extensions are:")
                    )

                    let validPath = fixturePath.appending(component: "SwiftFramework.zip")
                    packageOutput = try sh(
                        swiftPackage, "--package-path", fixturePath, "compute-checksum", validPath
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
        .requireThreadSafeWorkingDirectory,
        arguments: [BuildSystemProvider.native]
    )
    func packageInitExecutable(_ buildSystemProvider: BuildSystemProvider) throws {
        try _packageInitExecutable(buildSystemProvider)
    }

    @Test(
        .skipHostOS(.windows),
        .requireThreadSafeWorkingDirectory,
        .bug(
            "https://github.com/swiftlang/swift-package-manager/issues/8416",
            "[Linux] swift run using --build-system swiftbuild fails to run executable"
        ),
        .bug(
            "https://github.com/swiftlang/swift-package-manager/issues/8514",
            "[Windows] Integration test SwiftPMTests.packageInitExecutable with --build-system swiftbuild is skipped"
        ),
        arguments: [BuildSystemProvider.swiftbuild]
    )
    func packageInitExecutablSkipWindows(_ buildSystemProvider: BuildSystemProvider) throws {
        try _packageInitExecutable(buildSystemProvider)
    }

    private func _packageInitExecutable(_ buildSystemProvider: BuildSystemProvider) throws {
        try withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            try sh(swiftBuild, "--package-path", packagePath, "--build-system", buildSystemProvider.rawValue)

            try withKnownIssue(
                "Error while loading shared libraries: libswiftCore.so: cannot open shared object file: No such file or directory"
            ) {
                // The 'native' build system uses 'swiftc' as the linker driver, which adds an RUNPATH to the swift
                // runtime libraries in the SDK.
                // 'swiftbuild' directly calls clang, which does not add the extra RUNPATH, so runtime libraries cannot
                // be found.
                let runOutput = try sh(
                    swiftRun, "--package-path", packagePath, "--build-system", buildSystemProvider.rawValue
                )
                #expect(!runOutput.stderr.contains("error:"))
                #expect(runOutput.stdout.contains("Hello, world!"))
            } when: {
                buildSystemProvider == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }
        }
    }

    @Test(
        .requireThreadSafeWorkingDirectory,
        .bug(id: 0, "SWBINTTODO: Linux: /lib/x86_64-linux-gnu/Scrt1.o:function _start: error:"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8380", "lld-link: error: subsystem must be defined"),
        .bug(id: 0, "SWBINTTODO: MacOS: Could not find or use auto-linked library 'Testing': library 'Testing' not found"),
        arguments: BuildSystemProvider.allCases
    )
    func packageInitLibrary(_ buildSystemProvider: BuildSystemProvider) throws {
        try withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            try withKnownIssue(
                """
                Linux: /lib/x86_64-linux-gnu/Scrt1.o:function _start: error: undefined reference to 'main'
                Windows: lld-link: error: subsystem must be defined
                MacOS: Could not find or use auto-linked library 'Testing': library 'Testing' not found
                """,
                isIntermittent: true
            ) {
                try sh(swiftBuild, "--package-path", packagePath, "--build-system", buildSystemProvider.rawValue)
                let testOutput = try sh(
                    swiftTest, "--package-path", packagePath, "--build-system", buildSystemProvider.rawValue
                )
                #expect(testOutput.returnCode == .terminated(code: 0))
                #expect(!testOutput.stderr.contains("error:"))

            } when: {
                buildSystemProvider == .swiftbuild
            }
        }
    }

    @Test(.requireHostOS(.macOS))
    func testArchCustomization() throws {
        try withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
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
                try sh(swiftBuild, "--package-path", packagePath, "--arch", arch)
                let fooPath = try AbsolutePath(
                    validating: ".build/\(arch)-apple-macosx/debug/foo",
                    relativeTo: packagePath
                )
                #expect(localFileSystem.exists(fooPath))
            }

            let args =
                [swiftBuild.pathString, "--package-path", packagePath.pathString]
                    + archs.flatMap { ["--arch", $0] }
            try _sh(args)

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
}
