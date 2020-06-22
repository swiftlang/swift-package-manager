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
  #if os(macOS)
    // FIXME: This is failing right now.
    func DISABLED_testBinaryTargets() throws {
        try binaryTargetsFixture { prefix in
            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", prefix, "exe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertEqual(stdout, """
                    SwiftFramework()
                    Library(framework: SwiftFramework.SwiftFramework())

                    """)
            }

            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", prefix, "cexe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertMatch(stdout, .contains("<CLibrary: "))
            }

            do {
                let invalidPath = prefix.appending(component: "SwiftFramework.xcframework")
                let (_, stderr) = try shFails(swiftPackage, "--package-path", prefix, "compute-checksum", invalidPath)
                XCTAssertMatch(stderr, .contains("error: unexpected file type; supported extensions are: zip"))

                let validPath = prefix.appending(component: "SwiftFramework.zip")
                let (stdout, _) = try sh(swiftPackage, "--package-path", prefix, "compute-checksum", validPath)
                XCTAssertEqual(stdout.spm_chomp(), "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158")
            }
        }
    }

    func testArchCustomization() throws {
        try withTemporaryDirectory { tmpDir in
            let foo = tmpDir.appending(component: "foo")
            try localFileSystem.createDirectory(foo)
            try sh(swiftPackage, "--package-path", foo, "init", "--type", "executable")

            try localFileSystem.removeFileTree(foo.appending(RelativePath("Sources/foo/main.swift")))
            try localFileSystem.writeFileContents(foo.appending(RelativePath("Sources/foo/main.m"))) {
                $0 <<< "int main() {}"
            }
            let archs = ["x86_64", "x86_64h"]

            for arch in archs {
                try sh(swiftBuild, "--package-path", foo, "--arch", arch)
                let fooPath = foo.appending(RelativePath(".build/\(arch)-apple-macosx/debug/foo"))
                XCTAssertFileExists(fooPath)
            }

            let args = [swiftBuild.pathString, "--package-path", foo.pathString] + archs.flatMap{ ["--arch", $0] }
            try _sh(args)

            let fooPath = foo.appending(RelativePath(".build/apple/Products/Debug/foo"))
            XCTAssertFileExists(fooPath)

            let objectsDir = foo.appending(RelativePath(".build/apple/Intermediates.noindex/foo.build/Debug/foo.build/Objects-normal"))
            for arch in archs {
                XCTAssertDirectoryExists(objectsDir.appending(component: arch))
            }
        }
    }
  #endif
}
