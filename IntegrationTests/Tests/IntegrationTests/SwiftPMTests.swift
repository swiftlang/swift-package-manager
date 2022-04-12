/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TSCBasic
import TSCTestSupport

final class SwiftPMTests: XCTestCase {
    func testBinaryTargets() throws {
        try XCTSkip("FIXME: ld: warning: dylib (/../BinaryTargets.6YVYK4/TestBinary/.build/x86_64-apple-macosx/debug/SwiftFramework.framework/SwiftFramework) was built for newer macOS version (10.15) than being linked (10.10)")

#if !os(macOS)
        try XCTSkip("Test requires macOS")
#endif

        try binaryTargetsFixture { fixturePath in
            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", fixturePath, "exe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertEqual(stdout, """
                    SwiftFramework()
                    Library(framework: SwiftFramework.SwiftFramework())

                    """)
            }

            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", fixturePath, "cexe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertMatch(stdout, .contains("<CLibrary: "))
            }

            do {
                let invalidPath = fixturePath.appending(component: "SwiftFramework.xcframework")
                let (_, stderr) = try shFails(swiftPackage, "--package-path", fixturePath, "compute-checksum", invalidPath)
                XCTAssertMatch(stderr, .contains("error: unexpected file type; supported extensions are: zip"))

                let validPath = fixturePath.appending(component: "SwiftFramework.zip")
                let (stdout, _) = try sh(swiftPackage, "--package-path", fixturePath, "compute-checksum", validPath)
                XCTAssertEqual(stdout.spm_chomp(), "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158")
            }
        }
    }

    func testArchCustomization() throws {
        #if !os(macOS)
        try XCTSkip("Test requires macOS")
        #endif

        try withTemporaryDirectory { tmpDir in
            let packagePath = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            // delete any files generated
            for entry in try localFileSystem.getDirectoryContents(packagePath.appending(components: "Sources", "foo")) {
                try localFileSystem.removeFileTree(packagePath.appending(components: "Sources", "foo", entry))
            }
            try localFileSystem.writeFileContents(AbsolutePath("Sources/foo/main.m", relativeTo: packagePath)) {
                $0 <<< "int main() {}"
            }
            let archs = ["x86_64", "arm64"]

            for arch in archs {
                try sh(swiftBuild, "--package-path", packagePath, "--arch", arch)
                let fooPath = AbsolutePath(".build/\(arch)-apple-macosx/debug/foo", relativeTo: packagePath)
                XCTAssertFileExists(fooPath)
            }

            let args = [swiftBuild.pathString, "--package-path", packagePath.pathString] + archs.flatMap{ ["--arch", $0] }
            try _sh(args)

            let fooPath = AbsolutePath(".build/apple/Products/Debug/foo", relativeTo: packagePath)
            XCTAssertFileExists(fooPath)

            let objectsDir = AbsolutePath(".build/apple/Intermediates.noindex/foo.build/Debug/foo.build/Objects-normal", relativeTo: packagePath)
            for arch in archs {
                XCTAssertDirectoryExists(objectsDir.appending(component: arch))
            }
        }
    }
}
