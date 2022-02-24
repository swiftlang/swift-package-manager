/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageGraph
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import Xcodeproj
import XCTest

class GenerateXcodeprojTests: XCTestCase {
    func testBuildXcodeprojPath() {
        let outdir = AbsolutePath("/path/to/project")
        let projectName = "Bar"
        let xcodeprojPath = XcodeProject.makePath(outputDir: outdir, projectName: projectName)
        let expectedPath = AbsolutePath("/path/to/project/Bar.xcodeproj")
        XCTAssertEqual(xcodeprojPath, expectedPath)
    }

    func testXcodebuildCanParseIt() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try testWithTemporaryDirectory { dstdir in
            let packagePath = dstdir.appending(component: "foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModuleName")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "source.swift"), bytes: "")

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModuleName"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)
            try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, dstdir.appending(component: projectName + ".xcodeproj"))

            // We can only validate this on OS X.
            // Don't allow TOOLCHAINS to be overriden here, as it breaks the test below.
            let output = try Process.checkNonZeroExit(
                args: "env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.pathString).spm_chomp()

            XCTAssertMatch(output, .contains("""
             Information about project "DummyProjectName":
                 Targets:
                     DummyModuleName

                 Build Configurations:
                     Debug
                     Release

                 If no build configuration is specified and -scheme is not passed then "Release" is used.

                 Schemes:
                     Foo-Package
             """))
        }
    }

    func testXcconfigOverrideValidatesPath() throws {
        try testWithTemporaryDirectory { dstdir in
            let packagePath = dstdir.appending(component: "Bar")
            let modulePath = packagePath.appending(components: "Sources", "Bar")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "bar.swift"), bytes: "")

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Bar",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "Bar"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/doesntexist"))
            do {
                _ = try xcodeProject(
                    xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                    graph: graph,
                    extraDirs: [],
                    extraFiles: [],
                    options: options,
                    fileSystem: localFileSystem,
                    observabilityScope: observability.topScope
                )
                XCTFail("Project generation should have failed")
            } catch ProjectGenerationError.xcconfigOverrideNotFound(let path) {
                XCTAssertEqual(options.xcconfigOverrides, path)
            } catch {
                XCTFail("Project generation shouldn't have had another error")
            }
        }
    }

    func testGenerateXcodeprojWithInvalidModuleNames() throws {
        try testWithTemporaryDirectory { dstdir in
            let packagePath = dstdir.appending(component: "Bar")
            let modulePath = packagePath.appending(components: "Sources", "Modules")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "example.swift"), bytes: "")

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Modules",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "Modules"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            _ = try xcodeProject(
                xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"),
                graph: graph, extraDirs: [], extraFiles: [],
                options: XcodeprojOptions(), fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: .contains("Target 'Modules' conflicts with required framework filenames, rename this target to avoid conflicts."),
                    severity: .warning
                )
            }
        }
    }

    func testGenerateXcodeprojWithoutGitRepo() throws {
        try testWithTemporaryDirectory { dstdir in
            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "a.txt"), bytes: "dummy_data")

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)
            let project = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == "a.txt" })
        }
    }

    func testGenerateXcodeprojWithDotFiles() throws {
        try testWithTemporaryDirectory { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: ".a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)
            let project = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == ".a.txt" })
        }
    }

    func testGenerateXcodeprojWithRootFiles() throws {
        try testWithTemporaryDirectory { dstdir in
            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)
            let project = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            XCTAssertTrue(project.mainGroup.subitems.contains { $0.path == "a.txt" })

            let projectWithoutExtraFiles = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(addExtraFiles: false),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )
            XCTAssertFalse(projectWithoutExtraFiles.mainGroup.subitems.contains { $0.path == "a.txt" })
        }
    }

    func testGenerateXcodeprojWithNonSourceFilesInSourceDirectories() throws {
        try testWithTemporaryDirectory { tmpdir in

            let packagePath = tmpdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")
            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(modulePath.appending(component: "a.txt"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: tmpdir, projectName: projectName)
            let project = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            let sources = project.mainGroup.subitems[1] as? Xcode.Group
            let dummyModule = sources?.subitems[0] as? Xcode.Group
            let aTxt = dummyModule?.subitems[0]

            XCTAssertEqual(aTxt?.path, "a.txt")
        }
    }

    func testGenerateXcodeprojWithFilesIgnoredByGit() throws {
        try testWithTemporaryDirectory { dstdir in

            let packagePath = dstdir.appending(component: "Foo")
            let modulePath = packagePath.appending(components: "Sources", "DummyModule")

            try makeDirectories(modulePath)
            try localFileSystem.writeFileContents(modulePath.appending(component: "dummy.swift"), bytes: "dummy_data")

            initGitRepo(packagePath, addFile: false)
            // Add a .gitignore
            try localFileSystem.writeFileContents(packagePath.appending(component: ".gitignore"), bytes: "ignored_file")
            try localFileSystem.writeFileContents(modulePath.appending(component: "ignored_file"), bytes: "dummy_data")
            try localFileSystem.writeFileContents(packagePath.appending(component: "ignored_file"), bytes: "dummy_data")

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: packagePath,
                        targets: [
                            TargetDescription(name: "DummyModule"),
                        ])
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            let projectName = "DummyProjectName"
            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)
            let project = try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            let sources = project.mainGroup.subitems[1] as? Xcode.Group
            let dummyModule = sources?.subitems[0] as? Xcode.Group

            XCTAssertEqual(dummyModule?.subitems.count, 1)
            XCTAssertFalse(project.mainGroup.subitems.contains { $0.path == "ignored_file" })
        }
    }

    func testGenerateXcodeprojWarnsConditionalTargetDependencies() throws {
        try testWithTemporaryDirectory { dstdir in
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

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: localFileSystem,
                manifests: [
                    Manifest.createRootManifest(
                        name: "Foo",
                        path: fooPackagePath,
                        dependencies: [
                            .fileSystem(path: barPackagePath)
                        ],
                        targets: [
                            TargetDescription(name: "Foo", dependencies: [
                                .product(name: "Bar", package: "Bar", condition: .init(platformNames: ["ios"]))
                            ]),
                        ]),
                    Manifest.createLocalSourceControlManifest(
                        name: "Bar",
                        path: barPackagePath,
                        products: [
                            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar1"])
                        ],
                        targets: [
                            TargetDescription(name: "Bar1", dependencies: [
                                .target(name: "Bar2", condition: .init(config: "debug"))
                            ]),
                            TargetDescription(name: "Bar2"),
                        ])
                ],
                observabilityScope: observability.topScope
            )

            let outpath = XcodeProject.makePath(outputDir: dstdir, projectName: "Foo")
            try XcodeProject.generate(
                projectName: "Foo",
                xcodeprojPath: outpath,
                graph: graph,
                options: XcodeprojOptions(),
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            testDiagnostics(observability.diagnostics) { result in
                result.check(
                    diagnostic: .regex("""
                        Xcode project generation does not support conditional target dependencies, so the generated \
                        project might not build successfully. The offending targets are: (Foo, Bar1|Bar1, Foo).
                        """),
                    severity: .warning)
            }
        }
    }

    func testGenerateXcodeprojDeprecation() throws {
        try fixture(name: "DependencyResolution/External/Simple/Foo") { fixturePath in
            let (_, stderr) = try SwiftPMProduct.SwiftPackage.execute(["generate-xcodeproj"], packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("'generate-xcodeproj' is no longer needed and will be deprecated soon"))
        }
    }
}
