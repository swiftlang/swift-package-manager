/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph
import PackageDescription
import TestSupport
@testable import Xcodeproj

class PackageGraphTests: XCTestCase {
    func testBasics() throws {
      let fs = InMemoryFileSystem(emptyFiles:
          "/Foo/foo.swift",
          "/Foo/Tests/FooTests/fooTests.swift",
          "/Bar/Sources/Bar/bar.swift",
          "/Bar/Sources/Sea/include/Sea.h",
          "/Bar/Sources/Sea/Sea.c",
          "/Bar/Sources/Sea2/include/Sea2.h",
          "/Bar/Sources/Sea2/include/module.modulemap",
          "/Bar/Sources/Sea2/Sea2.c",
          "/Bar/Tests/BarTests/barTests.swift",
          "/Overrides.xcconfig"
      )

        let g = try loadMockPackageGraph([
            "/Foo": Package(name: "Foo"),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
        ], root: "/Bar", in: fs)

        var options = XcodeprojOptions()
        options.xcconfigOverrides = AbsolutePath("/Overrides.xcconfig")
        
        let project = try xcodeProject(xcodeprojPath: AbsolutePath.root.appending(component: "xcodeproj"), graph: g, extraDirs: [], options: options, fileSystem: fs)

        XcodeProjectTester(project) { result in
            result.check(projectDir: "Bar")

            result.check(references:
                "Package.swift",
                "Configs/Overrides.xcconfig",
                "Sources/Foo/foo.swift",
                "Sources/Sea2/Sea2.c",
                "Sources/Sea2/include/Sea2.h",
                "Sources/Sea2/include/module.modulemap",
                "Sources/Bar/bar.swift",
                "Sources/Sea/Sea.c",
                "Sources/Sea/include/Sea.h",
                "Sources/Sea/include/module.modulemap",
                "Tests/BarTests/barTests.swift",
                "Products/Foo.framework",
                "Products/Sea2.framework",
                "Products/Bar.framework",
                "Products/Sea.framework",
                "Products/BarTests.xctest"
            )

            XCTAssertNil(project.buildSettings.xcconfigFileRef)

            XCTAssertEqual(project.buildSettings.common.SDKROOT, "macosx")
            XCTAssertEqual(project.buildSettings.common.SUPPORTED_PLATFORMS!, ["macosx", "iphoneos", "iphonesimulator", "appletvos", "appletvsimulator", "watchos", "watchsimulator"])

            result.check(target: "Foo") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: [])
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
                XCTAssertNil(targetResult.target.buildSettings.common.SDKROOT)
            }

            result.check(target: "Bar") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.LD_RUNPATH_SEARCH_PATHS ?? [], ["$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"])
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "Sea") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.MODULEMAP_FILE ?? "", "xcodeproj/GeneratedModuleMap/Sea/module.modulemap")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "Sea2") { targetResult in
                targetResult.check(productType: .framework)
                targetResult.check(dependencies: ["Foo"])
                XCTAssertEqual(targetResult.commonBuildSettings.MODULEMAP_FILE ?? "", "Bar/Sources/Sea2/include/module.modulemap")
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }

            result.check(target: "BarTests") { targetResult in
                targetResult.check(productType: .unitTest)
                targetResult.check(dependencies: ["Foo", "Bar"])
                XCTAssertEqual(targetResult.commonBuildSettings.LD_RUNPATH_SEARCH_PATHS ?? [], ["@loader_path/../Frameworks"])
                XCTAssertEqual(targetResult.target.buildSettings.xcconfigFileRef?.path, "../Overrides.xcconfig")
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}

private func XcodeProjectTester(_ project: Xcode.Project, _ result: (XcodeProjectResult) -> Void) {
    result(XcodeProjectResult(project))
}

private class XcodeProjectResult {
    let project: Xcode.Project
    let targetMap: [String: Xcode.Target]

    init(_ project: Xcode.Project) {
        self.project = project
        self.targetMap = Dictionary(items: project.targets.map { target -> (String, Xcode.Target) in (target.name, target) })
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
        init(_ target: Xcode.Target) {
            self.target = target
        }

        func check(productType: Xcode.Target.ProductType, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(target.productType, productType, file: file, line: line)
        }

        func check(dependencies: [String], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(target.dependencies.map{$0.target.name}, dependencies, file: file, line: line)
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
        if path.characters.first == "/" {
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
