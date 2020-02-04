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
            "/Hello.something",
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

        let somethingRule = FileRuleDescription(
            rule: .processResource,
            toolsVersion: .minimumRequired,
            fileTypes: ["something"])

        build(target: target, additionalFileRules: [somethingRule], toolsVersion: .v5, fs: fs) { _, _, _ in
            // No diagnostics
        }
    }

    func testResourceConflicts() throws {
        // Conflict between processed resources.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Resources")
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/foo.txt",
                "/Resources/Sub/foo.txt"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                diagnostics.check(diagnostic: "multiple resources named 'foo.txt' in target 'Foo'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "found 'Resources/foo.txt'", behavior: .note)
                diagnostics.checkUnordered(diagnostic: "found 'Resources/Sub/foo.txt'", behavior: .note)
            }
        }

        // Conflict between processed and copied resources.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Processed"),
                .init(rule: .copy, path: "Copied/foo.txt"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Processed/foo.txt",
                "/Copied/foo.txt"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                diagnostics.check(diagnostic: "multiple resources named 'foo.txt' in target 'Foo'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "found 'Processed/foo.txt'", behavior: .note)
                diagnostics.checkUnordered(diagnostic: "found 'Copied/foo.txt'", behavior: .note)
            }
        }

        // No conflict between processed and copied in sub-path resources.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Processed"),
                .init(rule: .copy, path: "Copied"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Processed/foo.txt",
                "/Copied/foo.txt"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                // No diagnostics
            }
        }

        // Conflict between copied directory resources.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .copy, path: "A/Copy"),
                .init(rule: .copy, path: "B/Copy"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/Copy/foo.txt",
                "/B/Copy/foo.txt"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                diagnostics.check(diagnostic: "multiple resources named 'Copy' in target 'Foo'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "found 'A/Copy'", behavior: .note)
                diagnostics.checkUnordered(diagnostic: "found 'B/Copy'", behavior: .note)
            }
        }
    }

    func testInfoPlistResource() {
        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Resources"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/Processed/Info.plist"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                diagnostics.check(
                    diagnostic: .contains("resource 'Resources/Processed/Info.plist' in target 'Foo' is forbidden"),
                    behavior: .error)
            }
        }

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .copy, path: "Resources/Copied/Info.plist"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/Copied/Info.plist"
            )

            build(target: target, toolsVersion: .vNext, fs: fs) { _, _, diagnostics in
                diagnostics.check(
                    diagnostic: .contains("resource 'Resources/Copied/Info.plist' in target 'Foo' is forbidden"),
                    behavior: .error)
            }
        }
    }

    func build(
        target: TargetDescription,
        additionalFileRules: [FileRuleDescription] = [],
        toolsVersion: ToolsVersion,
        fs: FileSystem,
        file: StaticString = #file,
        line: UInt = #line,
        checker: (Sources, [Resource], DiagnosticsEngineResult) -> ()
    ) {
        let diagnostics = DiagnosticsEngine()
        let builder = TargetSourcesBuilder(
            packageName: "",
            packagePath: .root,
            target: target,
            path: .root,
            additionalFileRules: additionalFileRules,
            toolsVersion: toolsVersion,
            fs: fs,
            diags: diagnostics
        )

        do {
            let (sources, resources) = try builder.run()

            DiagnosticsEngineTester(diagnostics, file: file, line: line) { diagnostics in
                checker(sources, resources, diagnostics)
            }
        } catch {
            XCTFail(error.localizedDescription, file: file, line: line)
        }
    }
}
