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

@Suite
private struct SwiftPMTests {
    @Test(.requireHostOS(.macOS))
    func binaryTargets() throws {
        withKnownIssue("error: the path does not point to a valid framework:") {
            try binaryTargetsFixture { fixturePath in
                do {
                    withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let (stdout, stderr) = try sh(swiftRun, "--package-path", fixturePath, "exe")
                        #expect(!stderr.contains("error:"))
                        #expect(
                            stdout == """
                            SwiftFramework()
                            Library(framework: SwiftFramework.SwiftFramework())

                            """
                        )
                    }
                }

                do {
                    withKnownIssue("error: local binary target ... does not contain a binary artifact") {
                        let (stdout, stderr) = try sh(swiftRun, "--package-path", fixturePath, "cexe")
                        #expect(!stderr.contains("error:"))
                        #expect(stdout.contains("<CLibrary: "))
                    }
                }

                do {
                    let invalidPath = fixturePath.appending(component: "SwiftFramework.xcframework")
                    let (_, stderr) = try shFails(
                        swiftPackage, "--package-path", fixturePath, "compute-checksum", invalidPath
                    )
                    #expect(
                        // The order of supported extensions is not ordered, and changes.
                        //   '...supported extensions are: zip, tar.gz, tar'
                        //   '...supported extensions are: tar.gz, zip, tar'
                        // Only check for the start of that string.
                        stderr.contains("error: unexpected file type; supported extensions are:")
                    )

                    let validPath = fixturePath.appending(component: "SwiftFramework.zip")
                    let (stdout, _) = try sh(
                        swiftPackage, "--package-path", fixturePath, "compute-checksum", validPath
                    )
                    #expect(
                        stdout.spm_chomp()
                            == "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158"
                    )
                }
            }
        }
    }

    @Test(.requireThreadSafeWorkingDirectory)
    func packageInitExecutable() throws {
        // Executable
        do {
            try withTemporaryDirectory { tmpDir in
                let packagePath = tmpDir.appending(component: "foo")
                try localFileSystem.createDirectory(packagePath)
                try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
                try sh(swiftBuild, "--package-path", packagePath, "--build-system", "swiftbuild")
                // SWBINTTODO: Path issues related to swift test of the output from a swiftbuild buildsystem
                // let (stdout, stderr) = try sh(
                //     swiftRun, "--package-path", packagePath, "--build-system", "swiftbuild"
                // )
                // #expect(!stderr.contains("error:"))
                // #expect(stdout.contains("Hello, world!"))
            }
        }
    }

    @Test(
        .skipHostOS(
            .windows,
            "Windows fails to link this library package due to a 'lld-link: error: subsystem must be defined' error. See https://github.com/swiftlang/swift-build/issues/310"
        ),
        .requireThreadSafeWorkingDirectory
    )
    func packageInitLibrary() throws {
        do {
            try withTemporaryDirectory { tmpDir in
                let packagePath = tmpDir.appending(component: "foo")
                try localFileSystem.createDirectory(packagePath)
                try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
                try sh(swiftBuild, "--package-path", packagePath, "--build-system", "swiftbuild")
                // SWBINTTODO: Path issues related to swift test of the output from a swiftbuild buildsystem
                // let (stdout, stderr) = try sh(
                //     swiftTest, "--package-path", packagePath, "--build-system", "swiftbuild"
                // )
                // #expect(!stderr.contains("error:"))
                // #expect(stdout.contains("Test Suite 'All tests' passed"))
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
