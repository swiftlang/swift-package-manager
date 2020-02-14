/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import SPMTestSupport

import TSCBasic
import PackageModel
import PackageLoading

class TargetSourcesBuilderTests: XCTestCase {
    func testBasicFileContentsComputation() throws {
        let target = TargetDescription(
            name: "Foo",
            path: nil,
            exclude: ["some2"],
            sources: nil,
            resources: [
                .init(rule: .copy, path: "some/path/toBeCopied")
            ],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/Foo.swift",
            "/Bar.swift",
            "/some/path.swift",
            "/some2/path2.swift",
            "/.some2/hello.swift",
            "/Hello.something/hello.txt",
            "/file",
            "/path/to/file.xcodeproj/pbxproj",
            "/path/to/somefile.txt",
            "/some/path/toBeCopied/cool/hello.swift",
        ])

        let diags = DiagnosticsEngine()

        let builder = TargetSourcesBuilder(
            packageName: "",
            packagePath: .root,
            target: target,
            path: .root,
            toolsVersion: .v5,
            fs: fs,
            diags: diags
        )

        let contents = builder.computeContents().map{ $0.pathString }.sorted()

        XCTAssertEqual(contents, [
            "/Bar.swift",
            "/Foo.swift",
            "/Hello.something/hello.txt",
            "/file",
            "/path/to/somefile.txt",
            "/some/path.swift",
            "/some/path/toBeCopied",
        ])

        XCTAssertNoDiagnostics(diags)
    }

    func testBasicRuleApplication() throws {
        let target = TargetDescription(
            name: "Foo",
            path: nil,
            exclude: ["some2"],
            sources: nil,
            resources: [
                .init(rule: .process, path: "path"),
                .init(rule: .copy, path: "some/path/toBeCopied"),
            ],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/Foo.swift",
            "/Bar.swift",
            "/some/path.swift",
            "/some2/path2.swift",
            "/.some2/hello.swift",
            "/Hello.something/hello.txt",
            "/file",
            "/path/to/file.xcodeproj/pbxproj",
            "/path/to/somefile.txt",
            "/path/to/somefile2.txt",
            "/some/path/toBeCopied/cool/hello.swift",
        ])

        let diags = DiagnosticsEngine()

        let somethingRule = FileRuleDescription(
            rule: .processResource,
            toolsVersion: .minimumRequired,
            fileTypes: ["something"])

        let builder = TargetSourcesBuilder(
            packageName: "",
            packagePath: .root,
            target: target,
            path: .root,
            additionalFileRules: [somethingRule],
            toolsVersion: .v5,
            fs: fs,
            diags: diags
        )

        let contents = try builder.run()
        print(contents)
        XCTAssertNoDiagnostics(diags)
    }
}
