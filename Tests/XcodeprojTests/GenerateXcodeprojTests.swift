/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import TestSupport
import PackageDescription
import PackageGraph
import PackageModel
@testable import Xcodeproj
import Utility
import XCTest

class GenerateXcodeprojTests: XCTestCase {
    func testXcodebuildCanParseIt() {
      #if os(macOS)
        mktmpdir { dstdir in
            let fileSystem = InMemoryFileSystem(emptyFiles: "/Sources/DummyModuleName/source.swift")

            let graph = try loadMockPackageGraph(["/": Package(name: "Foo")], root: "/", in: fileSystem)

            let projectName = "DummyProjectName"
            let outpath = try Xcodeproj.generate(outputDir: dstdir, projectName: projectName, graph: graph, options: XcodeprojOptions())

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, dstdir.appending(component: projectName + ".xcodeproj"))

            // We can only validate this on OS X.
            // Don't allow TOOLCHAINS to be overriden here, as it breaks the test below.
            let output = try popen(["env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.asString]).chomp()

            let expectedOutput = "Information about project \"DummyProjectName\":\n    Targets:\n        DummyModuleName\n\n    Build Configurations:\n        Debug\n        Release\n\n    If no build configuration is specified and -scheme is not passed then \"Debug\" is used.\n\n    Schemes:\n        DummyProjectName\n".chomp()

            XCTAssertEqual(output, expectedOutput)
        }
      #endif
    }

    func testXcconfigOverrideValidatesPath() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: "/Bar/bar.swift")
        let graph = try loadMockPackageGraph(["/Bar": Package(name: "Bar")], root: "/Bar", in: fileSystem)

        let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/doesntexist"))
        do {
            _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                                 graph: graph, extraDirs: [], options: options, fileSystem: fileSystem)
            XCTFail("Project generation should have failed")
        } catch ProjectGenerationError.xcconfigOverrideNotFound(let path) {
            XCTAssertEqual(options.xcconfigOverrides, path)
        } catch {
            XCTFail("Project generation shouldn't have had another error")
        }
    }

    func testGenerateXcodeprojWithInvalidModuleNames() throws {
        let moduleName = "Modules"
        let warningStream = BufferedOutputByteStream()
        let fileSystem = InMemoryFileSystem(emptyFiles: "/Sources/\(moduleName)/example.swift")
        let graph = try loadMockPackageGraph(["/Sources": Package(name: moduleName)], root: "/Sources", in: fileSystem)

        _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                             graph: graph, extraDirs: [], options: XcodeprojOptions(), fileSystem: fileSystem,
                             warningStream: warningStream)

        let warnings = warningStream.bytes.asReadableString
        XCTAssertTrue(warnings.contains("warning: Target '\(moduleName)' conflicts with required framework filenames, rename this target to avoid conflicts."))
    }

    static var allTests = [
        ("testXcodebuildCanParseIt", testXcodebuildCanParseIt),
        ("testXcconfigOverrideValidatesPath", testXcconfigOverrideValidatesPath),
        ("testGenerateXcodeprojWithInvalidModuleNames", testGenerateXcodeprojWithInvalidModuleNames),
    ]
}
