//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SourceControl
import _InternalTestSupport
import XCTest

final class PackageDescription6_0LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_0
    }

    func testPackageContextGitStatus() async throws {
        let content = """
                import PackageDescription
                let package = Package(name: "\\(Context.gitInformation?.hasUncommittedChanges == true)")
                """

        try await loadRootManifestWithBasicGitRepository(manifestContent: content) { manifest, observability in
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(manifest.displayName, "true")
        }
    }

    func testPackageContextGitTag() async throws {
        let content = """
                import PackageDescription
                let package = Package(name: "\\(Context.gitInformation?.currentTag ?? "")")
                """

        try await loadRootManifestWithBasicGitRepository(manifestContent: content) { manifest, observability in
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(manifest.displayName, "lunch")
        }
    }

    func testPackageContextGitCommit() async throws {
        let content = """
                import PackageDescription
                let package = Package(name: "\\(Context.gitInformation?.currentCommit ?? "")")
                """

        try await loadRootManifestWithBasicGitRepository(manifestContent: content) { manifest, observability in
            XCTAssertNoDiagnostics(observability.diagnostics)

            let repo = GitRepository(path: manifest.path.parentDirectory)
            let currentRevision = try repo.getCurrentRevision()
            XCTAssertEqual(manifest.displayName, currentRevision.identifier)
        }
    }

    func testSwiftLanguageModesPerTarget() async throws {
        let content = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    defaultLocalization: "fr",
                    products: [],
                    targets: [
                        .target(
                            name: "Foo",
                            swiftSettings: [
                                .swiftLanguageMode(.v5)
                            ]
                        ),
                        .target(
                            name: "Bar",
                            swiftSettings: [
                                .swiftLanguageVersion(.v6)
                            ]
                        )
                    ]
                )
                """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(validationDiagnostics)

            // Verify the manifest structure
            XCTAssertEqual(manifest.targets.count, 2)
            XCTAssertEqual(manifest.targets[0].name, "Foo")
            XCTAssertEqual(manifest.targets[1].name, "Bar")

            // Check for deprecation warnings (only present in compilation-based loader)
            if loader == nil {
                testDiagnostics(observability.diagnostics) { result in
                    result.checkUnordered(diagnostic: .contains("'swiftLanguageVersion' is deprecated: renamed to 'swiftLanguageMode(_:_:)'"), severity: .warning)
                }
            }

            return manifest
        }
    }

    func testSwiftLanguageModesPackageLevel() async throws {
        // Test the new swiftLanguageModes parameter name (6.0+)
        let contentWithNewName = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    swiftLanguageModes: [.v5, .v6]
                )
                """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                contentWithNewName,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.swiftLanguageVersions, [.v5, .v6])

            return manifest
        }

        // Test the deprecated swiftLanguageVersions parameter name (still valid)
        let contentWithOldName = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    swiftLanguageVersions: [.v4, .v5]
                )
                """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                contentWithOldName,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.swiftLanguageVersions, [.v4, .v5])

            // Check for deprecation warning (only present in compilation-based loader)
            if loader == nil {
                testDiagnostics(observability.diagnostics) { result in
                    result.checkUnordered(diagnostic: .contains("'swiftLanguageVersions' is deprecated"), severity: .warning)
                }
            }

            return manifest
        }
    }

    private func loadRootManifestWithBasicGitRepository(
        manifestContent: String, 
        validator: (Manifest, TestingObservability) throws -> ()
    ) async throws {
        let observability = ObservabilitySystem.makeForTesting()

        try await testWithTemporaryDirectory { tmpdir in
            let manifestPath = tmpdir.appending(component: Manifest.filename)
            try localFileSystem.writeFileContents(manifestPath, string: manifestContent)
            try localFileSystem.writeFileContents(tmpdir.appending("best.txt"), string: "best")

            let repo = GitRepository(path: tmpdir)
            try repo.create()
            try repo.stage(file: manifestPath.pathString)
            try repo.commit(message: "best")
            try repo.tag(name: "lunch")

            let manifest = try await manifestLoader.load(
                manifestPath: manifestPath,
                packageKind: .root(tmpdir),
                toolsVersion: self.toolsVersion,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )

            try validator(manifest, observability)
        }
    }
}
