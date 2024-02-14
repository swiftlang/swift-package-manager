//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import SPMTestSupport
import XCTest

class ResourcesTests: XCTestCase {
    func testSimpleResources() throws {
        try fixture(name: "Resources/Simple") { fixturePath in
            var executables = ["SwiftyResource"]

            // Objective-C module requires macOS
            #if os(macOS)
            executables.append("SeaResource")
            executables.append("CPPResource")
            #endif

            for execName in executables {
                let (output, _) = try executeSwiftRun(fixturePath, execName)
                XCTAssertTrue(output.contains("foo"), output)
            }
        }
    }

    func testLocalizedResources() throws {
        try fixture(name: "Resources/Localized") { fixturePath in
            try executeSwiftBuild(fixturePath)

            let exec = AbsolutePath(".build/debug/exe", relativeTo: fixturePath)
            // Note: <rdar://problem/59738569> Source from LANG and -AppleLanguages on command line for Linux resources
            let output = try Process.checkNonZeroExit(args: exec.pathString, "-AppleLanguages", "(en_US)")
            XCTAssertEqual(output, """
                ¡Hola Mundo!
                Hallo Welt!
                Bonjour le monde !

                """)
        }
    }

    func testResourcesInMixedClangPackage() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try fixture(name: "Resources/Simple") { fixturePath in
            XCTAssertBuilds(fixturePath, extraArgs: ["--target", "MixedClangResource"])
        }
    }

    func testMovedBinaryResources() throws {
        try fixture(name: "Resources/Moved") { fixturePath in
            var executables = ["SwiftyResource"]

            // Objective-C module requires macOS
            #if os(macOS)
            executables.append("SeaResource")
            #endif

            let binPath = try AbsolutePath(validating:
                executeSwiftBuild(fixturePath, configuration: .Release, extraArgs: ["--show-bin-path"]).stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )

            for execName in executables {
                _ = try executeSwiftBuild(fixturePath, configuration: .Release, extraArgs: ["--product", execName])

                try withTemporaryDirectory(prefix: execName) { tmpDirPath in
                    defer {
                        // Unblock and remove the tmp dir on deinit.
                        try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                        try? localFileSystem.removeFileTree(tmpDirPath)
                    }

                    let destBinPath = tmpDirPath.appending(component: execName)
                    // Move the binary
                    try localFileSystem.move(from: binPath.appending(component: execName), to: destBinPath)
                    // Move the resources
                    try localFileSystem
                        .getDirectoryContents(binPath)
                        .filter { $0.contains(execName) && $0.hasSuffix(".bundle") || $0.hasSuffix(".resources") }
                        .forEach { try localFileSystem.move(from: binPath.appending(component: $0), to: tmpDirPath.appending(component: $0)) }
                    // Run the binary
                    let output = try Process.checkNonZeroExit(args: destBinPath.pathString)
                    XCTAssertTrue(output.contains("foo"))
                }
            }
        }
    }

    func testSwiftResourceAccessorDoesNotCauseInconsistentImportWarning() throws {
        try fixture(name: "Resources/FoundationlessClient/UtilsWithFoundationPkg") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                Xswiftc: ["-warnings-as-errors"]
            )
        }
    }

    func testResourceBundleInClangPackageWhenRunningSwiftTest() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try fixture(name: "Resources/Simple") { fixturePath in
            XCTAssertSwiftTest(fixturePath, extraArgs: ["--filter", "ClangResourceTests"])
        }
    }

    func testResourcesEmbeddedInCode() throws {
        try fixture(name: "Resources/EmbedInCodeSimple") { fixturePath in
            let result = try executeSwiftRun(fixturePath, "EmbedInCodeSimple")
            XCTAssertEqual(result.stdout, "hello world\n\n")
        }
    }

    func testResourcesOutsideOfTargetCanBeIncluded() throws {
        try testWithTemporaryDirectory { tmpPath in
            let packageDir = tmpPath.appending(components: "MyPackage")

            let manifestFile = packageDir.appending("Package.swift")
            try localFileSystem.createDirectory(manifestFile.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(
                manifestFile,
                string: """
                // swift-tools-version: 5.11
                import PackageDescription
                let package = Package(name: "MyPackage",
                    targets: [
                        .executableTarget(
                            name: "exec",
                            resources: [.copy("../resources")]
                        )
                    ])
                """)

            let targetSourceFile = packageDir.appending(components: "Sources", "exec", "main.swift")
            try localFileSystem.createDirectory(targetSourceFile.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(targetSourceFile, string: """
            import Foundation
            print(Bundle.module.resourcePath ?? "<empty>")
            """)

            let resource = packageDir.appending(components: "Sources", "resources", "best.txt")
            try localFileSystem.createDirectory(resource.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(resource, string: "best")

            let (_, stderr) = try executeSwiftBuild(packageDir)
            // Filter some unrelated output that could show up on stderr.
            let filteredStderr = stderr.components(separatedBy: "\n").filter { !$0.contains("[logging]") }.joined(separator: "\n")
            XCTAssertEqual(filteredStderr, "", "unexpectedly received error output: \(stderr)")

            let builtProductsDir = packageDir.appending(components: [".build", "debug"])
            // On Apple platforms, it's going to be `.bundle` and elsewhere `.resources`.
            let potentialResourceBundleName = try XCTUnwrap(localFileSystem.getDirectoryContents(builtProductsDir).filter { $0.hasPrefix("MyPackage_exec.") }.first)
            let resourcePath = builtProductsDir.appending(components: [potentialResourceBundleName, "resources", "best.txt"])
            XCTAssertTrue(localFileSystem.exists(resourcePath), "resource file wasn't copied by the build")
            let contents = try String(contentsOfFile: resourcePath.pathString)
            XCTAssertEqual(contents, "best", "unexpected resource contents: \(contents)")
        }
    }
}
