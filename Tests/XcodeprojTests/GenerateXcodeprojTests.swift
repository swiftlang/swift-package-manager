/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import SPMTestSupport
import PackageGraph
import PackageModel
import SourceControl
import Xcodeproj
import TSCUtility
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
            let packagePath = dstdir.appending(component: "foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModuleName")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "source.swift"), bytes: "")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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
                args: "env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.pathString).spm_chomp()

            XCTAssertTrue(output.contains("""
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
        mktmpdir { dstdir in
            let packagePath = dstdir.appending(component: "Bar")
            let modulePath = packagePath.appending(components: "Sources", "Bar")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "bar.swift"), bytes: "")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Bar",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
                        targets: [
                            TargetDescription(name: "Bar"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/doesntexist"))
            do {
                _ = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                                     graph: graph, extraDirs: [], extraFiles: [], options: options, fileSystem: localFileSystem, diagnostics: diagnostics)
                XCTFail("Project generation should have failed")
            } catch ProjectGenerationError.xcconfigOverrideNotFound(let path) {
                XCTAssertEqual(options.xcconfigOverrides, path)
            } catch {
                XCTFail("Project generation shouldn't have had another error")
            }
        }
    }

    func testGenerateXcodeprojWithInvalidModuleNames() throws {
        mktmpdir { dstdir in
            let packagePath = dstdir.appending(component: "Bar")
            let modulePath = packagePath.appending(components: "Sources", "Modules")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "example.swift"), bytes: "")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Modules",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
                        targets: [
                            TargetDescription(name: "Modules"),
                        ])
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let warningStream = BufferedOutputByteStream()
            _ = try xcodeProject(
                xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                graph: graph, extraDirs: [], extraFiles: [],
                options: XcodeprojOptions(), fileSystem: localFileSystem,
                diagnostics: diagnostics, warningStream: warningStream)

            let warnings = warningStream.bytes.description
            XCTAssertMatch(warnings, .contains("warning: Target 'Modules' conflicts with required framework filenames, rename this target to avoid conflicts."))
        }
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
                fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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
                fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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
                fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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
                fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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
                fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: packagePath.pathString,
                        url: packagePath.pathString,
                        packageKind: .root,
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

    func testGenerateXcodeprojWarnsConditionalTargetDependencies() {
        mktmpdir { dstdir in
            let fooPackagePath = dstdir.appending(component: "Foo")
            let fooTargetPath = fooPackagePath.appending(components: "Sources", "Foo")
            try makeDirectories(fooTargetPath)
            try localFileSystem.writeFileContents(fooTargetPath.appending(component: "Sources.swift"), bytes: "")

            let barPackagePath = dstdir.appending(component: "Bar")
            let bar1TargetPath = barPackagePath.appending(components: "Sources", "Bar1")
            try makeDirectories(bar1TargetPath)
            try localFileSystem.writeFileContents(bar1TargetPath.appending(component: "Sources.swift"), bytes: "")
            let bar2TargetPath = barPackagePath.appending(components: "Sources", "Bar2")
            try makeDirectories(bar2TargetPath)
            try localFileSystem.writeFileContents(bar2TargetPath.appending(component: "Sources.swift"), bytes: "")

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(fs: localFileSystem, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: fooPackagePath.pathString,
                        url: fooPackagePath.pathString,
                        dependencies: [
                            PackageDependencyDescription(name: "Bar", url: barPackagePath.pathString, requirement: .localPackage)
                        ],
                        targets: [
                            TargetDescription(name: "Foo", dependencies: [
                                .product(name: "Bar", package: "Bar", condition: .init(platformNames: ["ios"]))
                            ]),
                        ]),
                    Manifest.createV4Manifest(
                        name: "Bar",
                        path: barPackagePath.pathString,
                        url: barPackagePath.pathString,
                        packageKind: .remote,
                        products: [
                            ProductDescription(name: "Bar", targets: ["Bar1"])
                        ],
                        targets: [
                            TargetDescription(name: "Bar1", dependencies: [
                                .target(name: "Bar2", condition: .init(config: "debug"))
                            ]),
                            TargetDescription(name: "Bar2"),
                        ])
                ]
            )

            let outpath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: "Foo")
            try Xcodeproj.generate(
                projectName: "Foo",
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                diagnostics: diagnostics)

            DiagnosticsEngineTester(diagnostics) { result in
                result.check(
                    diagnostic: .regex("""
                        Xcode project generation does not support conditional target dependencies, so the generated \
                        project might not build successfully. The offending targets are: (Foo, Bar1|Bar1, Foo).
                        """),
                    behavior: .warning)
            }
        }
    }
}
