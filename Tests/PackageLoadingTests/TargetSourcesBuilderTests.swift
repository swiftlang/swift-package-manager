/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageModel
import PackageLoading
import SPMTestSupport
import TSCBasic
import XCTest

class TargetSourcesBuilderTests: XCTestCase {
    func testBasicFileContentsComputation() throws {
        let target = try TargetDescription(
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

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5,
            fileSystem: fs,
            observabilityScope: observability.topScope
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

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testDirectoryWithExt() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: ["some2"],
            sources: nil,
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/some2/hello.swift",
            "/Hello.something/hello.txt",
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5_3,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let contents = builder.computeContents().map{ $0.pathString }.sorted()

        XCTAssertEqual(contents, [
            "/Hello.something",
        ])

        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testBasicRuleApplication() throws {
        let target = try TargetDescription(
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

        build(target: target, additionalFileRules: [somethingRule], toolsVersion: .v5, fs: fs) { _, _, _, _, _, _, _, _  in
            // No diagnostics
        }
    }

    func testDoesNotErrorWithAdditionalFileRules() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: [],
            sources: nil,
            resources: [],
            publicHeadersPath: nil,
            type: .regular
        )

        let files = [
            "/Foo.swift",
            "/Bar.swift",
            "/Baz.something"
        ]

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: files)

        let somethingRule = FileRuleDescription(
            rule: .compile,
            toolsVersion: .v5_5,
            fileTypes: ["something"]
        )

        build(target: target, additionalFileRules: [somethingRule], toolsVersion: .v5_5, fs: fs) { sources, _, _, _, _, _, _, _  in
            XCTAssertEqual(
                sources.paths.map(\.pathString).sorted(),
                files.sorted()
            )
        }
    }

    func testResourceConflicts() throws {
        // Conflict between processed resources.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Resources")
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/foo.txt",
                "/Resources/Sub/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(diagnostic: "multiple resources named 'foo.txt' in target 'Foo'", severity: .error, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'Resources/foo.txt'", severity: .info, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'Resources/Sub/foo.txt'", severity: .info, metadata: expectedMetadata)
            }
        }

        // Conflict between processed and copied resources.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Processed"),
                .init(rule: .copy, path: "Copied/foo.txt"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Processed/foo.txt",
                "/Copied/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(diagnostic: "multiple resources named 'foo.txt' in target 'Foo'", severity: .error, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'Processed/foo.txt'", severity: .info, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'Copied/foo.txt'", severity: .info, metadata: expectedMetadata)
            }
        }

        // No conflict between processed and copied in sub-path resources.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Processed"),
                .init(rule: .copy, path: "Copied"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Processed/foo.txt",
                "/Copied/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, _, _, _, diagnostics in
                // No diagnostics
            }
        }

        // Conflict between copied directory resources.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .copy, path: "A/Copy"),
                .init(rule: .copy, path: "B/Copy"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/Copy/foo.txt",
                "/B/Copy/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(diagnostic: "multiple resources named 'Copy' in target 'Foo'", severity: .error, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'A/Copy'", severity: .info, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'B/Copy'", severity: .info, metadata: expectedMetadata)
            }
        }

        // Conflict between processed localizations.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "A"),
                .init(rule: .process, path: "B"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/en.lproj/foo.txt",
                "/B/EN.lproj/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(diagnostic: "multiple resources named 'en.lproj/foo.txt' in target 'Foo'", severity: .error, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'A/en.lproj/foo.txt'", severity: .info, metadata: expectedMetadata)
                diagnostics.checkUnordered(diagnostic: "found 'B/EN.lproj/foo.txt'", severity: .info, metadata: expectedMetadata)
            }
        }

        // Conflict between processed localizations and copied resources.

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "A"),
                .init(rule: .copy, path: "B/en.lproj"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/A/EN.lproj/foo.txt",
                "/B/en.lproj/foo.txt"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(
                    diagnostic: "resource 'B/en.lproj' in target 'Foo' conflicts with other localization directories",
                    severity: .error,
                    metadata: expectedMetadata
                )
            }
        }
    }

    func testLocalizationDirectoryIgnoredOn5_2() throws {
        let target = try TargetDescription(name: "Foo")

        let fs = InMemoryFileSystem(emptyFiles:
            "/en.lproj/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_2, fs: fs) { _, resources, _, _, _, _, _, _ in
            XCTAssert(resources.isEmpty)
            // No diagnostics
        }
    }

    func testLocalizationDirectorySubDirectory() throws {
        let target = try TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Processed"),
            .init(rule: .copy, path: "Copied")
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Processed/en.lproj/sub/Localizable.strings",
            "/Copied/en.lproj/sub/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
            expectedMetadata.targetName = target.name
            diagnostics.check(
                diagnostic: "localization directory 'Processed/en.lproj' in target 'Foo' contains sub-directories, which is forbidden",
                severity: .error,
                metadata: expectedMetadata
            )
        }
    }

    func testExplicitLocalizationInLocalizationDirectory() throws {
        let target = try TargetDescription(name: "Foo", resources: [
            .init(rule: .process, path: "Resources", localization: .base),
        ])

        let fs = InMemoryFileSystem(emptyFiles:
            "/Resources/en.lproj/Localizable.strings"
        )

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
            expectedMetadata.targetName = target.name
            diagnostics.check(
                diagnostic: .contains("""
                    resource 'Resources/en.lproj/Localizable.strings' in target 'Foo' is in a localization directory \
                    and has an explicit localization declaration
                    """),
                severity: .error,
                metadata: expectedMetadata
            )
        }
    }

    func testMissingDefaultLocalization() throws {
        let target = try TargetDescription(name: "Foo", resources: [
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

        build(target: target, defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
            expectedMetadata.targetName = target.name
            diagnostics.check(
                diagnostic: .contains("resource 'Icon.png' in target 'Foo' is missing the default localization 'fr'"),
                severity: .warning,
                metadata: expectedMetadata
            )
        }
    }

    func testLocalizedAndUnlocalizedResources() throws {
        let target = try TargetDescription(name: "Foo", resources: [
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

        build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
            expectedMetadata.targetName = target.name
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Localizable.strings' in target 'Foo' has both localized and un-localized variants"),
                severity: .warning,
                metadata: expectedMetadata
            )
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Storyboard.storyboard' in target 'Foo' has both localized and un-localized variants"),
                severity: .warning,
                metadata: expectedMetadata
            )
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Image.png' in target 'Foo' has both localized and un-localized variants"),
                severity: .warning,
                metadata: expectedMetadata
            )
            diagnostics.checkUnordered(
                diagnostic: .contains("resource 'Icon.png' in target 'Foo' has both localized and un-localized variants"),
                severity: .warning,
                metadata: expectedMetadata
            )
        }
    }

    func testLocalizedResources() throws {
        let target = try TargetDescription(name: "Foo", resources: [
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

        build(target: target, defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, resources, _,  _, _, _, _, diagnostics in
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

    func testLocalizedImage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/fr.lproj/Image.png",
            "/Foo/es.lproj/Image.png"
        )

        build(target: try TargetDescription(name: "Foo"), defaultLocalization: "fr", toolsVersion: .v5_3, fs: fs) { _, resources, _, _, _, _, _, diagnostics in
            XCTAssertEqual(Set(resources), [
                Resource(rule: .process, path: AbsolutePath("/Foo/fr.lproj/Image.png"), localization: "fr"),
                Resource(rule: .process, path: AbsolutePath("/Foo/es.lproj/Image.png"), localization: "es"),
            ])
        }
    }

    func testInfoPlistResource() throws {
        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .process, path: "Resources"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/Processed/Info.plist"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(
                    diagnostic: .contains("resource 'Resources/Processed/Info.plist' in target 'Foo' is forbidden"),
                    severity: .error,
                    metadata: expectedMetadata
                )
            }
        }

        do {
            let target = try TargetDescription(name: "Foo", resources: [
                .init(rule: .copy, path: "Resources/Copied/Info.plist"),
            ])

            let fs = InMemoryFileSystem(emptyFiles:
                "/Resources/Copied/Info.plist"
            )

            build(target: target, toolsVersion: .v5_3, fs: fs) { _, _, _, _, identity, location, path, diagnostics in
                var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: identity, location: location, path: path)
                expectedMetadata.targetName = target.name
                diagnostics.check(
                    diagnostic: .contains("resource 'Resources/Copied/Info.plist' in target 'Foo' is forbidden"),
                    severity: .error,
                    metadata: expectedMetadata
                )
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
        checker: (Sources, [Resource], [AbsolutePath], [AbsolutePath], PackageIdentity, String, AbsolutePath, DiagnosticsTestResult) -> ()
    ) {
        let observability = ObservabilitySystem.makeForTesting()
        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "/test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: defaultLocalization,
            additionalFileRules: additionalFileRules,
            toolsVersion: toolsVersion,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        do {
            let (sources, resources, headers, others) = try builder.run()

            testDiagnostics(observability.diagnostics, file: file, line: line) { diagnostics in
                checker(sources, resources, headers, others, builder.packageIdentity, builder.packageLocation, builder.packagePath, diagnostics)
            }
        } catch {
            XCTFail(error.localizedDescription, file: file, line: line)
        }
    }
    
    func testMissingExclude() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: ["fakeDir", "../../fileOutsideRoot.py"],
            sources: nil,
            resources: [],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/Foo.swift",
            "/Bar.swift"
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "/test",
            packagePath: .init("/test"),
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: builder.packageIdentity, location: builder.packageLocation, path: builder.packagePath)
            expectedMetadata.targetName = target.name
            result.checkUnordered(diagnostic: "Invalid Exclude '/fileOutsideRoot.py': File not found.", severity: .warning, metadata: expectedMetadata)
            result.checkUnordered(diagnostic: "Invalid Exclude '/fakeDir': File not found.", severity: .warning, metadata: expectedMetadata)
        }
    }
    
    func testMissingResource() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: [],
            sources: nil,
            resources: [.init(rule: .copy, path: "../../../Fake.txt"),
                        .init(rule: .process, path: "NotReal")],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/Foo.swift",
            "/Bar.swift"
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "/test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        _ = try builder.run()

        testDiagnostics(observability.diagnostics) { result in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: builder.packageIdentity, location: builder.packageLocation, path: builder.packagePath)
            expectedMetadata.targetName = target.name
            result.checkUnordered(diagnostic: "Invalid Resource '../../../Fake.txt': File not found.", severity: .warning, metadata: expectedMetadata)
            result.checkUnordered(diagnostic: "Invalid Resource 'NotReal': File not found.", severity: .warning, metadata: expectedMetadata)
        }
    }
    
    func testMissingSource() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: [],
            sources: ["InvalidPackage.swift",
                      "DoesNotExist.swift",
                      "../../Tests/InvalidPackageTests/InvalidPackageTests.swift"],
            resources: [],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/Foo.swift",
            "/Bar.swift"
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "/test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: builder.packageIdentity, location: builder.packageLocation, path: builder.packagePath)
            expectedMetadata.targetName = target.name
            result.checkUnordered(diagnostic: "Invalid Source '/InvalidPackage.swift': File not found.", severity: .warning, metadata: expectedMetadata)
            result.checkUnordered(diagnostic: "Invalid Source '/DoesNotExist.swift': File not found.", severity: .warning, metadata: expectedMetadata)
            result.checkUnordered(diagnostic: "Invalid Source '/Tests/InvalidPackageTests/InvalidPackageTests.swift': File not found.", severity: .warning, metadata: expectedMetadata)
        }
    }

    func testXcodeSpecificResourcesAreNotIncludedByDefault() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: [],
            sources: ["File.swift"],
            resources: [],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/File.swift",
            "/Foo.xcdatamodel"
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "/test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            toolsVersion: .v5_5,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        _ = try builder.run()

        testDiagnostics(observability.diagnostics) { result in
            var expectedMetadata = ObservabilityMetadata.packageMetadata(identity: builder.packageIdentity, location: builder.packageLocation, path: builder.packagePath)
            expectedMetadata.targetName = target.name
            result.check(diagnostic: "found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target\n    /Foo.xcdatamodel\n", severity: .warning, metadata: expectedMetadata)
        }
    }

    func testDocCFilesDoNotCauseWarningOutsideXCBuild() throws {
        let target = try TargetDescription(
            name: "Foo",
            path: nil,
            exclude: [],
            sources: ["File.swift"],
            resources: [],
            publicHeadersPath: nil,
            type: .regular
        )

        let fs = InMemoryFileSystem()
        fs.createEmptyFiles(at: .root, files: [
            "/File.swift",
            "/Foo.docc"
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let builder = TargetSourcesBuilder(
            packageIdentity: .plain("test"),
            packageLocation: "test",
            packagePath: .root,
            target: target,
            path: .root,
            defaultLocalization: nil,
            additionalFileRules: FileRuleDescription.swiftpmFileTypes,
            toolsVersion: .v5_5,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        _ = try builder.run()

        XCTAssertNoDiagnostics(observability.diagnostics)
    }
}
