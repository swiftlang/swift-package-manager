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
            defaultLocalization: nil,
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

    func testDirectoryWithExt() throws {
        let target = TargetDescription(
            name: "Foo",
            path: nil,
            exclude: ["some2"],
            sources: nil,
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/.some2/hello.swift",
            "/Hello.something/hello.txt",
        ])

        let diags = DiagnosticsEngine()

        let builder = TargetSourcesBuilder(
            packageName: "",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5_3,
            fs: fs,
            diags: diags
        )

        let contents = builder.computeContents().map{ $0.pathString }.sorted()

        XCTAssertEqual(contents, [
            "/Hello.something",
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

        build(target: target, additionalFileRules: [somethingRule], toolsVersion: .v5, fs: fs) { _, _, _, _ in
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
                diagnostics.check(diagnostic: "multiple resources named 'Copy' in target 'Foo'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "found 'A/Copy'", behavior: .note)
                diagnostics.checkUnordered(diagnostic: "found 'B/Copy'", behavior: .note)
            }
        }

        // Conflict between processed localizations.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "A"),
                .init(rule: .process, path: "B"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/en.lproj/foo.txt",
                "/B/EN.lproj/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
                diagnostics.check(diagnostic: "multiple resources named 'en.lproj/foo.txt' in target 'Foo'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "found 'A/en.lproj/foo.txt'", behavior: .note)
                diagnostics.checkUnordered(diagnostic: "found 'B/EN.lproj/foo.txt'", behavior: .note)
            }
        }

        // Conflict between processed localizations and copied resources.

        do {
            let target = TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "A"),
                .init(rule: .copy, path: "B/en.lproj"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/EN.lproj/foo.txt",
                "/B/en.lproj/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
                diagnostics.check(diagnostic: "resource 'B/en.lproj' in target 'Foo' conflicts with other localization directories", behavior: .error)
            }
        }
    }

    func testLocalizationDirectoryIgnoredOn5_2() {
        let target = TargetDescription(name: "Foo")

        let fs = InMemoryFileSystem(emptyFiles:
            "/en.lproj/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_2, fs: fs) { _, resources, _, _ in
            XCTAssert(resources.isEmpty)
            // No diagnostics
        }
    }

    func testLocalizationDirectorySubDirectory() {
        let target = TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Processed"),
            .init(rule: .copy, path: "Copied")
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Processed/en.lproj/sub/Localizable.strings",
            "/Copied/en.lproj/sub/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
            diagnostics.check(diagnostic: "localization directory 'Processed/en.lproj' in target 'Foo' contains sub-directories, which is forbidden", behavior: .error)
        }
    }

    func testExplicitLocalizationInLocalizationDirectory() {
        let target = TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Resources", localization: .base),
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Resources/en.lproj/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
            diagnostics.check(
                diagnostic: .contains("""
                    resource 'Resources/en.lproj/Localizable.strings' in target 'Foo' is in a localization directory \
                    and has an explicit localization declaration
                    """),
                behavior: .error)
        }
    }

    func testMissingDefaultLocalization() {
        let target = TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Resources"),
            .init(rule: .process, path: "Image.png", localization: .default),
            .init(rule: .process, path: "Icon.png", localization: .base),
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Resources/en.lproj/Localizable.strings",
            "/Resources/en.lproj/Icon.png",
            "/Resources/fr.lproj/Localizable.strings",
            "/Resources/fr.lproj/Sign.png",
            "/Resources/Base.lproj/Storyboard.storyboard",
            "/Image.png",
            "/Icon.png"
        )

        build(target: target, defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
            diagnostics.check(
                diagnostic: .contains("resource 'Icon.png' in target 'Foo' is missing the default localization 'fr'"),
                behavior: .warning)
        }
    }

    func testLocalizedAndUnlocalizedResources() {
        let target = TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Resources"),
            .init(rule: .process, path: "Image.png", localization: .default),
            .init(rule: .process, path: "Icon.png", localization: .base),
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Resources/en.lproj/Localizable.strings",
            "/Resources/Localizable.strings",
            "/Resources/Base.lproj/Storyboard.storyboard",
            "/Resources/Storyboard.storyboard",
            "/Resources/Image.png",
            "/Resources/Icon.png",
            "/Image.png",
            "/Icon.png"
        )

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Localizable.strings' in target 'Foo' has both localized and un-localized variants"),
                behavior: .warning)
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Storyboard.storyboard' in target 'Foo' has both localized and un-localized variants"),
                behavior: .warning)
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Image.png' in target 'Foo' has both localized and un-localized variants"),
                behavior: .warning)
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Icon.png' in target 'Foo' has both localized and un-localized variants"),
                behavior: .warning)
        }
    }

    func testLocalizedResources() {
        let target = TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Processed"),
            .init(rule: .copy, path: "Copied"),
            .init(rule: .process, path: "Other/Launch.storyboard", localization: .base),
            .init(rule: .process, path: "Other/Image.png", localization: .default),
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Processed/foo.txt",
            "/Processed/En-uS.lproj/Localizable.stringsdict",
            "/Processed/en-US.lproj/Localizable.strings",
            "/Processed/fr.lproj/Localizable.strings",
            "/Processed/fr.lproj/Localizable.stringsdict",
            "/Processed/Base.lproj/Storyboard.storyboard",
            "/Copied/en.lproj/Localizable.strings",
            "/Other/Launch.storyboard",
            "/Other/Image.png"
        )

        build(target: target, defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, resources,  _, diagnostics in
            XCTAssertEqual(Set(resources), [
                Resource(rule: .process, path: AbsolutePath("/Processed/foo.txt"), localization: nil),
                Resource(rule: .process, path: AbsolutePath("/Processed/En-uS.lproj/Localizable.stringsdict"), localization: "en-us"),
                Resource(rule: .process, path: AbsolutePath("/Processed/en-US.lproj/Localizable.strings"), localization: "en-us"),
                Resource(rule: .process, path: AbsolutePath("/Processed/fr.lproj/Localizable.strings"), localization: "fr"),
                Resource(rule: .process, path: AbsolutePath("/Processed/fr.lproj/Localizable.stringsdict"), localization: "fr"),
                Resource(rule: .process, path: AbsolutePath("/Processed/Base.lproj/Storyboard.storyboard"), localization: "Base"),
                Resource(rule: .copy, path: AbsolutePath("/Copied"), localization: nil),
                Resource(rule: .process, path: AbsolutePath("/Other/Launch.storyboard"), localization: "Base"),
                Resource(rule: .process, path: AbsolutePath("/Other/Image.png"), localization: "fr"),
            ])
        }
    }

    func testLocalizedImage() {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/fr.lproj/Image.png",
            "/Foo/es.lproj/Image.png"
        )

        build(target: TargetDescription(name: "Foo"), defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, resources, _, diagnostics in
            XCTAssertEqual(Set(resources), [
                Resource(rule: .process, path: AbsolutePath("/Foo/fr.lproj/Image.png"), localization: "fr"),
                Resource(rule: .process, path: AbsolutePath("/Foo/es.lproj/Image.png"), localization: "es"),
            ])
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
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

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, diagnostics in
                diagnostics.check(
                    diagnostic: .contains("resource 'Resources/Copied/Info.plist' in target 'Foo' is forbidden"),
                    behavior: .error)
            }
        }
    }

    func build(
        target: TargetDescription,
        defaultLocalization: String? = nil,
        additionalFileRules: [FileRuleDescription] = [],
        toolsVersion: ToolsVersion,
        fs: FileSystem,
        file: StaticString = #file,
        line: UInt = #line,
        checker: (Sources, [Resource], [AbsolutePath], DiagnosticsEngineResult) -> ()
    ) {
        let diagnostics = DiagnosticsEngine()
        let builder = TargetSourcesBuilder(
            packageName: "",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: defaultLocalization,
            additionalFileRules: additionalFileRules,
            toolsVersion: toolsVersion,
            fs: fs,
            diags: diagnostics
        )

        do {
            let (sources, resources, headers) = try builder.run()

            DiagnosticsEngineTester(diagnostics, file: file, line: line) { diagnostics in
                checker(sources, resources, headers, diagnostics)
            }
        } catch {
            XCTFail(error.localizedDescription, file: file, line: line)
        }
    }
}
