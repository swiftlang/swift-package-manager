/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import TestSupport
import PackageGraph
import PackageModel
import SourceControl
@testable import Xcodeproj
import SPMUtility
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
            let graph = loadPackageGraph(root: "/", fs: fileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: "/",
                        url: "/",
                        targets: [
                            TargetDescription(name: "DummyModuleName"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, dstdir.appending(component: projectName + ".xcodeproj"))

            // We can only validate this on OS X.
            // Don't allow TOOLCHAINS to be overriden here, as it breaks the test below.
            let output = try Process.checkNonZeroExit(
                args: "env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.description).spm_chomp()

            XCTAssertTrue(output.hasPrefix("""
               Information about project "DummyProjectName":
                   Targets:
                       DummyModuleName

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
        let fileSystem = InMemoryFileSystem(emptyFiles: "/Bar/Sources/Bar/bar.swift")
        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(root: "/Bar", fs: fileSystem, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    targets: [
                        TargetDescription(name: "Bar"),
                    ])
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/doesntexist"))
        do {
            _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                                 graph: graph, extraDirs: [], extraFiles: [], options: options, fileSystem: fileSystem, diagnostics: diagnostics)
            XCTFail("Project generation should have failed")
        } catch ProjectGenerationError.xcconfigOverrideNotFound(let path) {
            XCTAssertEqual(options.xcconfigOverrides, path)
        } catch {
            XCTFail("Project generation shouldn't have had another error")
        }
    }

    func testGenerateXcodeprojWithInvalidModuleNames() throws {
        let warningStream = BufferedOutputByteStream()
        let fileSystem = InMemoryFileSystem(
            emptyFiles: "/Bar/Sources/Modules/example.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(root: "/Bar", fs: fileSystem, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Modules",
                    path: "/Bar",
                    url: "/Bar",
                    targets: [
                        TargetDescription(name: "Modules"),
                    ])
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        _ = try xcodeProject(
            xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
            graph: graph, extraDirs: [], extraFiles: [],
            options: XcodeprojOptions(), fileSystem: fileSystem,
            diagnostics: diagnostics, warningStream: warningStream)

        let warnings = warningStream.bytes.description
        XCTAssertMatch(warnings, .contains("warning: Target 'Modules' conflicts with required framework filenames, rename this target to avoid conflicts."))
    }

    func testGenerateXcodeprojWithoutGitRepo() {
        mktmpdir { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "a.txt"), bytes: "dummy_data")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                root: packagePath.description, fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.description,
                        url: packagePath.description,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            let project = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == "a.txt" })
        }
    }

    func testGenerateXcodeprojWithDotFiles() {
        mktmpdir { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: ".a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                root: packagePath.description, fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.description,
                        url: packagePath.description,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            let project = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == ".a.txt" })
        }
    }

    func testGenerateXcodeprojWithRootFiles() {
        mktmpdir { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                root: packagePath.description, fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.description,
                        url: packagePath.description,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            let project = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            XCTAssertTrue(project.mainGroup.subitems.contains { $0.path == "a.txt" })

            let projectWithoutExtraFiles = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(addExtraFiles: false), diagnostics: diagnostics)
            XCTAssertFalse(projectWithoutExtraFiles.mainGroup.subitems.contains { $0.path == "a.txt" })
        }
    }

    func testGenerateXcodeprojWithNonSourceFilesInSourceDirectories() {
        mktmpdir { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(modulePath.appending(component: "a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                root: packagePath.description, fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.description,
                        url: packagePath.description,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            let project = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            let sources = project.mainGroup.subitems[1] as? Xcode.Group
            let dummyModule = sources?.subitems[0] as? Xcode.Group
            let aTxt = dummyModule?.subitems[0]

            XCTAssertEqual(aTxt?.path, "a.txt")
        }
    }

    func testGenerateXcodeprojWithFilesIgnoredByGit() {
        mktmpdir { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")

            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)
            // Add a .gitignore
            try localFileSystem.writeFileContents(packagePath.appending(component: ".gitignore"), bytes: "ignored_file")
            try localFileSystem.writeFileContents(modulePath.appending(component: "ignored_file"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "ignored_file"), bytes: "dummy_data")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(
                root: packagePath.description, fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.description,
                        url: packagePath.description,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let projectName = "DummyProjectName"
            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)
            let project = try Xcodeproj.generate(projectName: projectName, xcodeprojPath: outpath, graph: graph, options: XcodeprojOptions(), diagnostics: diagnostics)

            let sources = project.mainGroup.subitems[1] as? Xcode.Group
            let dummyModule = sources?.subitems[0] as? Xcode.Group

            XCTAssertEqual(dummyModule?.subitems.count, 1)
            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == "ignored_file" })
        }
    }
}
