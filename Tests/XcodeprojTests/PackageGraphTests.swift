/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import PackageGraph
import SPMTestSupport
import PackageModel
import Xcodeproj

class PackageGraphTests: XCTestCase {
    func testBasics() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Foo/Tests/FooTests/fooTests.swift",
            "/Bar/Sources/Bar/bar.swift",
            "/Bar/Sources/Sea/include/Sea.h",
            "/Bar/Sources/Sea/Sea.c",
            "/Bar/Sources/Sea2/include/Sea2.h",
            "/Bar/Sources/Sea2/include/module.modulemap",
            "/Bar/Sources/Sea2/Sea2.c",
            "/Bar/Sources/Sea3/include/header.h",
            "/Bar/Sources/Sea3/Sea3.c",
            "/Bar/Tests/BarTests/barTests.swift",
            "/Overrides.xcconfig"
        )

        let diagnostics = DiagnosticsEngine()
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Foo", targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            settings: [
                                .init(tool: .swift, name: .define, value: ["CUSTOM"]),
                                .init(tool: .swift, name: .define, value: ["LINUX"], condition: .init(platformNames: ["linux"])),
                                .init(tool: .swift, name: .define, value: ["DMACOS"], condition: .init(platformNames: ["linux", "macos"], config: "debug")),
                            ]
                        ),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
                    dependencies: [
                        PackageDependencyDescription(name: "Foo", url: "/Foo", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                        TargetDescription(name: "BarTests", dependencies: ["Bar"], type: .test),
                        TargetDescription(name: "Sea", dependencies: ["Foo"]),
                        TargetDescription(name: "Sea2", dependencies: ["Foo"]),
                        TargetDescription(name: "Sea3", dependencies: ["Foo"]),
                    ]),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        let options = XcodeprojOptions(xcconfigOverrides: AbsolutePath("/Overrides.xcconfig"))

        let project = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"), graph: g, extraDirs: [], extraFiles: [], options: options, fileSystem: fs, diagnostics: diagnostics)

        XcodeProjectTester(project) { result in
            result.check(projectDir: "Bar")

            result.check(references:
                "Package.swift",
                "Configs/Overrides.xcconfig",
                "Sources/Sea3/Sea3.c",
                "Sources/Sea3/include/header.h",
                "Sources/Sea3/include/module.modulemap",
                "Sources/Sea2/Sea2.c",
                "Sources/Sea2/include/Sea2.h",
                "Sources/Sea2/include/module.modulemap",
                "Sources/Bar/bar.swift",
                "Sources/Sea/Sea.c",
                "Sources/Sea/include/Sea.h",
                "Tests/BarTests/barTests.swift",
                "Dependencies/Foo/Package.swift",
                "Dependencies/Foo/Foo/foo.swift",
                "Products/Foo.framework",
                "Products/Sea3.framework",
                "Products/Sea2.framework",
                "Products/Bar.framework",
                "Products/Sea.framework",
                "Products/BarTests.xctest"
            )

            XCTAssertNil(project.buildSettings.xcconfigFileRef)

            XCTAssertEqual(project.buildSettings.common.SDKROOT, "macosx")
            XCTAssertEqual(project.buildSettings.common.SUPPORTED_PLATFORMS!, ["macosx", "iphoneos", "iphonesimulator", "appletvos", "appletvsimulator", "watchos", "watchsimulator"])
            XCTAssertEqual(project.buildSettings.common.CLANG_ENABLE_OBJC_ARC, "YES")
            XCTAssertEqual(project.buildSettings.release.SWIFT_OPTIMIZATION_LEVEL, "-Owholemodule")
            XCTAssertEqual(project.buildSettings.debug.SWIFT_OPTIMIZATION_LEVEL, "-Onone")
            XCTAssertEqual(project.buildSettings.debug.SWIFT_ACTIVE_COMPILATION_CONDITIONS!, ["$(inherited)", "DEBUG"])
            XCTAssertEqual(project.buildSettings.common.SWIFT_ACTIVE_COMPILATION_CONDITIONS!, ["$(inherited)", "SWIFT_PACKAGE"])
            XCTAssertEqual(project.buildSettings.common.GCC_PREPROCESSOR_DEFINITIONS, ["$(inherited)", "SWIFT_PACKAGE=1"])

            result.check(target: "Foo") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: [])

                XCTAssertEqual(targetResult.target.buildSettings.common.SWIFT_ACTIVE_COMPILATION_CONDITIONS, ["$(inherited)", "CUSTOM"])
                XCTAssertEqual(targetResult.target.buildSettings.debug.SWIFT_ACTIVE_COMPILATION_CONDITIONS, ["DMACOS"])
                XCTAssertNil(targetResult.target.buildSettings.release.SWIFT_ACTIVE_COMPILATION_CONDITIONS)

                XCTAssertEqual(targetResult.commonBuildSettings.CURRENT_PROJECT_VERSION, "1")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_CFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_LDFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_SWIFT_FLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.SKIP_INSTALL, "YES")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
                XCTAssertNil(targetResult.target.buildSettings.common.SDKROOT)
            }

            result.check(target: "Bar") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.CURRENT_PROJECT_VERSION, "1")
                XCTAssertEqual(targetResult.commonBuildSettings.LD_RUNPATH_SEARCH_PATHS ?? [], ["$(inherited)", "$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"])
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_CFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_LDFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_SWIFT_FLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.SKIP_INSTALL, "YES")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "Sea") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.CURRENT_PROJECT_VERSION, "1")
                XCTAssertEqual(targetResult.commonBuildSettings.CLANG_ENABLE_MODULES, "YES")
                XCTAssertEqual(targetResult.commonBuildSettings.DEFINES_MODULE, "YES")
                XCTAssertEqual(targetResult.commonBuildSettings.MODULEMAP_FILE, nil)
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_CFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_LDFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_SWIFT_FLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.SKIP_INSTALL, "YES")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "Sea2") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertNil(targetResult.commonBuildSettings.CLANG_ENABLE_MODULES)
                XCTAssertEqual(targetResult.commonBuildSettings.CURRENT_PROJECT_VERSION, "1")
                XCTAssertEqual(targetResult.commonBuildSettings.DEFINES_MODULE, "NO")
                XCTAssertEqual(targetResult.commonBuildSettings.MODULEMAP_FILE, nil)
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_CFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_LDFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_SWIFT_FLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.SKIP_INSTALL, "YES")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "Sea3") { targetResult in
                targetResult.check(productType: .framework)
                XCTAssertNil(targetResult.commonBuildSettings.CLANG_ENABLE_MODULES)
                XCTAssertEqual(targetResult.commonBuildSettings.CURRENT_PROJECT_VERSION, "1")
                XCTAssertEqual(targetResult.commonBuildSettings.DEFINES_MODULE, "NO")
                XCTAssertEqual(targetResult.commonBuildSettings.MODULEMAP_FILE, nil)
            }

            result.check(target: "BarTests") { targetResult in
                targetResult.check(productType: .unitTest)
                targetResult.check(dependencies: ["Bar", "Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.LD_RUNPATH_SEARCH_PATHS ?? [], ["$(inherited)", "@loader_path/../Frameworks", "@loader_path/Frameworks"])
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_CFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_LDFLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.commonBuildSettings.OTHER_SWIFT_FLAGS?.first, "$(inherited)")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }
        }
    }

    func testAggregateTarget() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    products: [
                        ProductDescription(name: "Bar", type: .library(.dynamic), targets: ["Foo"])
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        let project = try xcodeProject(xcodeprojPath: AbsolutePath("/Foo/build").appending(component: "xcodeproj"), graph: g, extraDirs: [], extraFiles: [], options: XcodeprojOptions(), fileSystem: fs, diagnostics: diagnostics)
        XcodeProjectTester(project) { result in
            result.check(target: "Foo") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: [])
            }
            result.check(target: "Bar") { targetResult in
                targetResult.check(productType: nil)
                targetResult.check(dependencies: ["Foo"])
            }
        }
    }

    func testModulemap() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Bar/Sources/Sea/include/Sea.h",
            "/Bar/Sources/Sea/Sea.c",
            "/Bar/Sources/Sea2/include/Sea2.h",
            "/Bar/Sources/Sea2/include/module.modulemap",
            "/Bar/Sources/Sea2/Sea2.c",
            "/Bar/Sources/swift/main.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "Sea", dependencies: []),
                        TargetDescription(name: "Sea2", dependencies: []),
                        TargetDescription(name: "swift", dependencies: ["Sea", "Sea2"]),
                    ]),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

		let project = try xcodeProject(xcodeprojPath: AbsolutePath("/Bar/build").appending(component: "xcodeproj"), graph: g, extraDirs: [], extraFiles: [], options: XcodeprojOptions(), fileSystem: fs, diagnostics: diagnostics)
		XcodeProjectTester(project) { result in
      	    result.check(target: "swift") { targetResult in
      	        XCTAssertEqual(targetResult.target.buildSettings.common.OTHER_SWIFT_FLAGS ?? [], [
      	            "$(inherited)", "-Xcc",
      	            "-fmodule-map-file=$(SRCROOT)/Sources/Sea2/include/module.modulemap",
      	        ])
      	        XCTAssertEqual(targetResult.target.buildSettings.common.HEADER_SEARCH_PATHS ?? [], [
      	            "$(inherited)",
      	            "$(SRCROOT)/Sources/Sea2/include",
      	            "$(SRCROOT)/Sources/Sea/include",
      	        ])
      	    }
      	    result.check(target: "Sea") { targetResult in
      	        XCTAssertEqual(targetResult.target.buildSettings.common.MODULEMAP_FILE, nil)
      	    }
      	}
    }

    func testModuleLinkage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/HelperTool/main.swift",
            "/Pkg/Sources/Library/lib.swift",
            "/Pkg/Tests/LibraryTests/aTest.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let g = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Pkg",
                    path: "/Pkg",
                    url: "/Pkg",
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "HelperTool", dependencies: []),
                        TargetDescription(name: "Library", dependencies: []),
                        TargetDescription(name: "LibraryTests", dependencies: ["Library", "HelperTool"], type: .test),
                    ]),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        let project = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"), graph: g, extraDirs: [], extraFiles: [], options: XcodeprojOptions(), fileSystem: fs, diagnostics: diagnostics)

        XcodeProjectTester(project) { result in
            result.check(projectDir: "Pkg")
            result.check(target: "HelperTool") { targetResult in
                targetResult.check(productType: .executable)
                targetResult.check(dependencies: [])
                let linkPhases = targetResult.buildPhases.filter{ $0 is Xcode.FrameworksBuildPhase }
                XCTAssertEqual(linkPhases.count, 1)
                let linkedFiles = linkPhases.first!.files.map{ $0.fileRef!.path }
                XCTAssertEqual(linkedFiles, [])
            }
            result.check(target: "Library") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: [])
                let linkPhases = targetResult.buildPhases.filter{ $0 is Xcode.FrameworksBuildPhase }
                XCTAssertEqual(linkPhases.count, 1)
                let linkedFiles = linkPhases.first!.files.map{ $0.fileRef!.path }
                XCTAssertEqual(linkedFiles, [])
            }
            result.check(target: "LibraryTests") { targetResult in
                targetResult.check(productType: .unitTest)
                targetResult.check(dependencies: ["HelperTool", "Library"])
                let linkPhases = targetResult.buildPhases.filter{ $0 is Xcode.FrameworksBuildPhase }
                XCTAssertEqual(linkPhases.count, 1)
                let linkedFiles = linkPhases.first!.files.map{ $0.fileRef!.path }
                XCTAssertEqual(linkedFiles, ["Library.framework"])
            }
        }
    }

    func testSchemes() throws {
        let fs = InMemoryFileSystem(emptyFiles:
      	    "/Foo/Sources/a/main.swift",
      	    "/Foo/Sources/b/main.swift",
      	    "/Foo/Sources/c/main.swift",
      	    "/Foo/Sources/d/main.swift",
      	    "/Foo/Sources/libd/libd.swift",

      	    "/Foo/Tests/aTests/fooTests.swift",
      	    "/Foo/Tests/bcTests/fooTests.swift",
      	    "/Foo/Tests/dTests/fooTests.swift",
      	    "/Foo/Tests/libdTests/fooTests.swift",
      	    "/end"
      	)

        let diagnostics = DiagnosticsEngine()
        let graph = loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    url: "/Foo",
                    packageKind: .root,
                    targets: [
                        TargetDescription(name: "a"),
                        TargetDescription(name: "b", dependencies: ["a"]),
                        TargetDescription(name: "c", dependencies: ["a"]),
                        TargetDescription(name: "d", dependencies: ["b"]),
                        TargetDescription(name: "libd", dependencies: ["d"]),

                        TargetDescription(name: "aTests", dependencies: ["a"], type: .test),
                        TargetDescription(name: "bcTests", dependencies: ["b", "c"], type: .test),
                        TargetDescription(name: "dTests", dependencies: ["d"], type: .test),
                        TargetDescription(name: "libdTests", dependencies: ["libd"], type: .test),
                    ]),
            ]
        )
        XCTAssertNoDiagnostics(diagnostics)

        let generatedSchemes = SchemesGenerator(
            graph: graph,
            container: "Foo.xcodeproj",
            schemesDir: AbsolutePath("/Foo.xcodeproj/xcshareddata/xcschemes"),
            isCodeCoverageEnabled: true,
            fs: fs).buildSchemes()

        let schemes = Dictionary(uniqueKeysWithValues: generatedSchemes.map({ ($0.name, $0) }))

        XCTAssertEqual(generatedSchemes.count, 5)
        XCTAssertEqual(schemes["a"]?.testTargets.map({ $0.name }).sorted(), ["aTests"])
        XCTAssertEqual(schemes["a"]?.regularTargets.map({ $0.name }).sorted(), ["a"])

        XCTAssertEqual(schemes["b"]?.testTargets.map({ $0.name }).sorted(), ["aTests", "bcTests"])
        XCTAssertEqual(schemes["c"]?.testTargets.map({ $0.name }).sorted(), ["aTests", "bcTests"])
        XCTAssertEqual(schemes["d"]?.testTargets.map({ $0.name }).sorted(), ["aTests", "bcTests", "dTests"])

        XCTAssertEqual(schemes["Foo-Package"]?.testTargets.map({ $0.name }).sorted(), ["aTests", "bcTests", "dTests", "libdTests"])
        XCTAssertEqual(schemes["Foo-Package"]?.regularTargets.map({ $0.name }).sorted(), ["a", "b", "c", "d", "libd"])
    }

    func testSwiftVersion() throws {
        // FIXME: Unfortunately, we can't test 4.2 right now.
        for swiftVersion in ["3.0", "4.0", "4.2"] {
            let fs = InMemoryFileSystem(emptyFiles:
                "/Foo/Sources/a/main.swift",
                "/end"
            )

            let diagnostics = DiagnosticsEngine()
            let graph = loadPackageGraph(fs: fs, diagnostics: diagnostics,
                manifests: [
                    Manifest.createV4Manifest(
                        name: "Foo",
                        path: "/Foo",
                        url: "/Foo",
                        packageKind: .root,
                        swiftLanguageVersions: [SwiftLanguageVersion(string: swiftVersion)!],
                        targets: [
                            TargetDescription(name: "a"),
                        ]),
                ]
            )
            XCTAssertNoDiagnostics(diagnostics)

            let project = try xcodeProject(xcodeprojPath: AbsolutePath("/Foo").appending(component: "xcodeproj"), graph: graph, extraDirs: [], extraFiles: [], options: XcodeprojOptions(), fileSystem: fs, diagnostics: diagnostics)
            XCTAssertNoDiagnostics(diagnostics)

            XcodeProjectTester(project) { result in
                result.check(target: "a") { targetResult in
                    XCTAssertEqual(targetResult.target.buildSettings.common.SWIFT_VERSION, swiftVersion)
                }
            }
        }
    }
}

private func XcodeProjectTester(_ project: Xcode.Project, _ result: (XcodeProjectResult) -> Void) {
    result(XcodeProjectResult(project))
}

private class XcodeProjectResult {
    let project: Xcode.Project
    let targetMap: [String: Xcode.Target]

    init(_ project: Xcode.Project) {
        self.project = project
        self.targetMap = Dictionary(uniqueKeysWithValues: project.targets.map { target -> (String, Xcode.Target) in (target.name, target) })
    }

    func check(projectDir: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(project.projectDir, projectDir, file: file, line: line)
    }

    func check(target name: String, file: StaticString = #file, line: UInt = #line, _ body: ((TargetResult) -> Void)) {
        guard let target = targetMap[name] else {
            return XCTFail("Expected target not present \(self)", file: file, line: line)
        }
        body(TargetResult(target))
    }

    func check(references: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(recursiveRefPaths(project.mainGroup).sorted(), references.sorted(), file: file, line: line)
    }

    class TargetResult {
        let target: Xcode.Target
        var commonBuildSettings: Xcode.BuildSettingsTable.BuildSettings {
            return target.buildSettings.common
        }
        var buildPhases: [Xcode.BuildPhase] {
            return target.buildPhases
        }
        init(_ target: Xcode.Target) {
            self.target = target
        }

        func check(productType: Xcode.Target.ProductType?, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(target.productType, productType, file: file, line: line)
        }

        func check(dependencies: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(target.dependencies.map{$0.target.name}.sorted(), dependencies, file: file, line: line)
        }
    }
}

extension Xcode.Reference {
    /// Returns name of the reference if present otherwise last path component.
    var basename: String {
        if let name = name {
            return name
        }
        // If path is empty (root), Path basename API returns `.`
        if path.isEmpty {
            return ""
        }
        if path.first == "/" {
            return AbsolutePath(path).basename
        }
        return RelativePath(path).basename
    }
}

/// Returns array of paths from Xcode references.
private func recursiveRefPaths(_ ref: Xcode.Reference, parents: [Xcode.Reference] = []) -> [String] {
    if case let group as Xcode.Group = ref {
        return group.subitems.flatMap { recursiveRefPaths($0, parents: parents + [ref]) }
    }
    return [(parents + [ref]).filter{!$0.basename.isEmpty}.map{$0.basename}.joined(separator: "/")]
}
