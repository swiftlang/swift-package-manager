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
    func testBuildXcodeprojPath() {
        let outdir = AbsolutePath("/path/to/project")
        let projectName = "Bar"
        let xcodeprojPath = Xcodeproj.buildXcodeprojPath(outputDir: outdir, projectName: projectName)
        let expectedPath = AbsolutePath("/path/to/project/Bar.xcodeproj")
        XCTAssertEqual(xcodeprojPath, expectedPath)
    }
    
    func testXcodebuildCanParseIt() {
      #if os(macOS)
        mktmpdir { dstdir in
            let fileSystem = InMemoryFileSystem(emptyFiles: "/Sources/DummyModuleName/source.swift")

            let diagnostics = DiagnosticsEngine()
            let graph = loadMockPackageGraph(["/": Package(name: "Foo")], root: "/", diagnostics: diagnostics, in: fileSystem)
            XCTAssertFalse(diagnostics.hasErrors)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, dstdir.appending(component: projectName + ".xcodeproj"))

            // We can only validate this on OS X.
            // Don't allow TOOLCHAINS to be overriden here, as it breaks the test below.
            let output = try Process.checkNonZeroExit(
                args: "env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.asString).chomp()

            XCTAssertTrue(output.hasPrefix("""
               Information about project "DummyProjectName":
                   Targets:
                       DummyModuleName
                       Foo
                       FooPackageDescription

                   Build Configurations:
                       Debug
                       Release
               
                   If no build configuration is specified and -scheme is not passed then "Release" is used.
               
                   Schemes:
                       Foo-Package
               """), output)
        }
      #endif
    }

    func testXcconfigOverrideValidatesPath() throws {
        let diagnostics = DiagnosticsEngine()
        let fileSystem = InMemoryFileSystem(emptyFiles: "/Bar/bar.swift")
        let graph = loadMockPackageGraph(["/Bar": Package(name: "Bar")], root: "/Bar", diagnostics: diagnostics, in: fileSystem)
        XCTAssertFalse(diagnostics.hasErrors)

        let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/doesntexist"))
        do {
            _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                                 graph: graph, extraDirs: [], options: options, fileSystem: fileSystem, diagnostics: diagnostics)
            XCTFail("Project generation should have failed")
        } catch ProjectGenerationError.xcconfigOverrideNotFound(let path) {
            XCTAssertEqual(options.xcconfigOverrides, path)
        } catch {
            XCTFail("Project generation shouldn't have had another error")
        }
    }

    func testGenerateXcodeprojWithInvalidModuleNames() throws {
        let diagnostics = DiagnosticsEngine()
        let moduleName = "Modules"
        let warningStream = BufferedOutputByteStream()
        let fileSystem = InMemoryFileSystem(emptyFiles: "/Sources/\(moduleName)/example.swift")
        let graph = loadMockPackageGraph(["/Sources": Package(name: moduleName)], root: "/Sources", diagnostics: diagnostics, in: fileSystem)
        XCTAssertFalse(diagnostics.hasErrors)

        _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                             graph: graph, extraDirs: [], options: XcodeprojOptions(), fileSystem: fileSystem, diagnostics: diagnostics,
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
