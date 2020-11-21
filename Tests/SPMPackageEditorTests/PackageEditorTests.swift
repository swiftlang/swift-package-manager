/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import SPMTestSupport
import SourceControl

@testable import SPMPackageEditor

final class PackageEditorTests: XCTestCase {

    func testAddDependency() throws {
        let manifest = """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                ]
            )
            """

        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Package.swift",
            "/pkg/Sources/foo/source.swift",
            "/pkg/Sources/bar/source.swift",
            "/pkg/Tests/fooTests/source.swift",
            "end")

        let manifestPath = AbsolutePath("/pkg/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }
        try fs.createDirectory(.init("/pkg/repositories"), recursive: false)
        try fs.createDirectory(.init("/pkg/repo"), recursive: false)


        let provider = InMemoryGitRepositoryProvider()
        let repo = InMemoryGitRepository(path: .init("/pkg/repo"), fs: fs)
        try repo.writeFileContents(.init("/Package.swift"), bytes: .init(encodingAsUTF8: """
        // swift-tools-version:5.2
        import PackageDescription

        let package = Package(name: "repo")
        """))
        repo.commit()
        try repo.tag(name: "1.1.1")
        provider.add(specifier: .init(url: "http://www.githost.com/repo"), repository: repo)
        
        let context = try PackageEditorContext(
            manifestPath: AbsolutePath("/pkg/Package.swift"),
            repositoryManager: RepositoryManager(path: .init("/pkg/repositories"), provider: provider, fileSystem: fs),
            toolchain: Resources.default.toolchain,
            fs: fs
        )
        let editor = PackageEditor(context: context)

        try editor.addPackageDependency(url: "http://www.githost.com/repo.git", requirement: .exact("1.1.1"))

        let newManifest = try fs.readFileContents(manifestPath).cString
        XCTAssertEqual(newManifest, """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                    .package(name: "repo", url: "http://www.githost.com/repo.git", .exact("1.1.1")),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                ]
            )
            """)
    }

    func testAddTarget() throws {
        let manifest = """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                ]
            )
            """

        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Package.swift",
            "/pkg/Sources/foo/source.swift",
            "/pkg/Sources/bar/source.swift",
            "/pkg/Tests/fooTests/source.swift",
            "end")

        let manifestPath = AbsolutePath("/pkg/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }

        let context = try PackageEditorContext(
            manifestPath: AbsolutePath("/pkg/Package.swift"),
            repositoryManager: RepositoryManager(path: .init("/pkg/repositories"), provider: InMemoryGitRepositoryProvider()),
            toolchain: Resources.default.toolchain, fs: fs)
        let editor = PackageEditor(context: context)

        XCTAssertThrows(StringError("a target named 'foo' already exists")) {
            try editor.addTarget(name: "foo", type: .regular, includeTestTarget: true, dependencies: [])
        }

        try editor.addTarget(name: "baz", type: .regular, includeTestTarget: true, dependencies: [])
        try editor.addTarget(name: "qux", type: .regular, includeTestTarget: false, dependencies: ["foo", "baz"])
        try editor.addTarget(name: "IntegrationTests", type: .test, includeTestTarget: false, dependencies: [])

        let newManifest = try fs.readFileContents(manifestPath).cString
        XCTAssertEqual(newManifest, """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                    .target(
                        name: "baz",
                        dependencies: []),
                    .testTarget(
                        name: "bazTests",
                        dependencies: ["baz"]),
                    .target(
                        name: "qux",
                        dependencies: ["foo", "baz"]),
                    .testTarget(
                        name: "IntegrationTests",
                        dependencies: []),
                ]
            )
            """)

        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Sources/baz/baz.swift")))
        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Tests/bazTests/bazTests.swift")))
        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Sources/qux/qux.swift")))
        XCTAssertFalse(fs.exists(AbsolutePath("/pkg/Tests/quxTests")))
        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Tests/IntegrationTests/IntegrationTests.swift")))
    }

    func testToolsVersionTest() throws {
        let manifest = """
            // swift-tools-version:5.0
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                ]
            )
            """

        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Package.swift",
            "/pkg/Sources/foo/source.swift",
            "end")

        let manifestPath = AbsolutePath("/pkg/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }

        let context = try PackageEditorContext(
            manifestPath: AbsolutePath("/pkg/Package.swift"),
            repositoryManager: RepositoryManager(path: .init("/pkg/repositories"), provider: InMemoryGitRepositoryProvider()),
            toolchain: Resources.default.toolchain, fs: fs)
        let editor = PackageEditor(context: context)

        XCTAssertThrows(StringError("mechanical manifest editing operations are only supported for packages with swift-tools-version 5.2 and later")) {
            try editor.addTarget(name: "bar", type: .regular, includeTestTarget: true, dependencies: [])
        }
    }
}
