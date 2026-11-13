//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(FixItApplier) import SwiftIDEUtils
import SwiftParser
import SwiftSyntax
import Testing

@testable
import Commands

import struct TSCUtility.Version

struct ManifestRequirementEditorTests {
    private static let url = "https://github.com/example/foo.git"

    /// Wraps a single dependency element in a minimal manifest.
    private func manifest(_ dependency: String) -> String {
        """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "App",
            dependencies: [
                \(dependency),
            ],
            targets: [
                .target(name: "App", dependencies: [.product(name: "Foo", package: "foo")]),
            ]
        )
        """
    }

    private func rewrite(
        _ source: String,
        _ locator: DependencyLocator = .url(Self.url),
        to version: Version
    ) throws -> String {
        let syntax = Parser.parse(source: source)
        let edits = try ManifestRequirementEditor.raiseLowerBound(in: syntax, of: locator, to: version)
        return FixItApplier.apply(edits: edits, to: syntax)
    }

    private func expectRewrite(
        _ before: String,
        _ after: String,
        _ locator: DependencyLocator = .url(Self.url),
        to version: Version,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws {
        let result = try rewrite(manifest(before), locator, to: version)
        #expect(result == manifest(after), sourceLocation: sourceLocation)
    }

    @Test func from() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", from: "1.0.0")"#,
            #".package(url: "\#(Self.url)", from: "1.2.3")"#,
            to: "1.2.3"
        )
    }

    @Test func upToNextMajorFrom() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", .upToNextMajor(from: "1.0.0"))"#,
            #".package(url: "\#(Self.url)", .upToNextMajor(from: "1.2.3"))"#,
            to: "1.2.3"
        )
    }

    @Test func upToNextMinorFrom() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", .upToNextMinor(from: "1.2.0"))"#,
            #".package(url: "\#(Self.url)", .upToNextMinor(from: "1.2.3"))"#,
            to: "1.2.3"
        )
    }

    @Test func requirementLabelledUpToNextMajor() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", requirement: .upToNextMajor(from: "1.0.0"))"#,
            #".package(url: "\#(Self.url)", requirement: .upToNextMajor(from: "1.2.3"))"#,
            to: "1.2.3"
        )
    }

    @Test func exactLabel() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", exact: "1.0.0")"#,
            #".package(url: "\#(Self.url)", exact: "1.2.3")"#,
            to: "1.2.3"
        )
    }

    @Test func exactCall() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", .exact("1.0.0"))"#,
            #".package(url: "\#(Self.url)", .exact("1.2.3"))"#,
            to: "1.2.3"
        )
    }

    @Test func halfOpenRangeKeepsUpperBound() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", "1.0.0"..<"2.0.0")"#,
            #".package(url: "\#(Self.url)", "1.2.3"..<"2.0.0")"#,
            to: "1.2.3"
        )
    }

    @Test func halfOpenRangeExtendsUpperBound() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", "1.0.0"..<"1.5.0")"#,
            #".package(url: "\#(Self.url)", "1.5.0"..<"2.0.0")"#,
            to: "1.5.0"
        )
    }

    @Test func closedRangeKeepsUpperBound() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", "1.0.0"..."1.9.0")"#,
            #".package(url: "\#(Self.url)", "1.2.3"..."1.9.0")"#,
            to: "1.2.3"
        )
    }

    @Test func closedRangeExtendsUpperBound() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", "1.0.0"..."1.4.0")"#,
            #".package(url: "\#(Self.url)", "1.5.0"..."1.5.0")"#,
            to: "1.5.0"
        )
    }

    @Test func registryIdentifier() throws {
        try expectRewrite(
            #".package(id: "example.foo", from: "1.0.0")"#,
            #".package(id: "example.foo", from: "1.2.3")"#,
            .id("Example.Foo"),
            to: "1.2.3"
        )
    }

    @Test func urlVariantMatches() throws {
        try expectRewrite(
            #".package(url: "https://github.com/example/foo", from: "1.0.0")"#,
            #".package(url: "https://github.com/example/foo", from: "1.2.3")"#,
            .url("https://GitHub.com/example/foo.git/"),
            to: "1.2.3"
        )
    }

    @Test func legacyNameAndURL() throws {
        try expectRewrite(
            #".package(name: "Foo", url: "\#(Self.url)", from: "1.0.0")"#,
            #".package(name: "Foo", url: "\#(Self.url)", from: "1.2.3")"#,
            to: "1.2.3"
        )
    }

    @Test func lowerBoundAlreadySatisfiedProducesNoEdit() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", from: "1.3.0")"#,
            #".package(url: "\#(Self.url)", from: "1.3.0")"#,
            to: "1.2.3"
        )
    }

    @Test func dependencyInVariableOutsidePackage() throws {
        let source = """
            import PackageDescription

            let deps: [Package.Dependency] = [
                .package(url: "\(Self.url)", from: "1.0.0"),
            ]
            let package = Package(name: "App", dependencies: deps)
            """
        let expected = source.replacingOccurrences(of: #"from: "1.0.0""#, with: #"from: "1.2.3""#)
        #expect(try rewrite(source, to: "1.2.3") == expected)
    }

    @Test func preservesFormattingAndComments() throws {
        let source = """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "App",
                dependencies: [
                    .package(url: "https://github.com/example/bar.git", from: "3.0.0"), // keep bar
                    .package(
                        url: "\(Self.url)",   // the foo package
                        from:   "1.0.0" /* pinned for API */
                    ),
                ]
            )
            """
        let expected = source.replacingOccurrences(of: #"from:   "1.0.0""#, with: #"from:   "1.2.3""#)
        #expect(source != expected)
        #expect(try rewrite(source, to: "1.2.3") == expected)
    }

    @Test func dependencyNotFound() throws {
        #expect(throws: ManifestRequirementEditError.dependencyNotFound) {
            try rewrite(
                manifest(#".package(url: "https://github.com/example/other.git", from: "1.0.0")"#),
                to: "1.2.3"
            )
        }
    }

    @Test func ambiguousDependency() throws {
        let source = """
            import PackageDescription

            let package = Package(
                name: "App",
                dependencies: [
                    .package(url: "\(Self.url)", from: "1.0.0"),
                    .package(url: "https://github.com/example/foo", from: "1.1.0"),
                ]
            )
            """
        #expect(throws: ManifestRequirementEditError.ambiguousDependency) {
            try rewrite(source, to: "1.2.3")
        }
    }

    @Test func nonLiteralRequirement() throws {
        #expect(throws: ManifestRequirementEditError.nonLiteralRequirement) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", from: someVersion)"#), to: "1.2.3")
        }
    }

    @Test func branchIsUnsupported() throws {
        #expect(throws: ManifestRequirementEditError.unsupportedRequirement("branch")) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", branch: "main")"#), to: "1.2.3")
        }
    }

    @Test func unparseableLowerBoundIsUnsupported() throws {
        #expect(throws: ManifestRequirementEditError.unsupportedRequirement("1.0")) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", from: "1.0")"#), to: "1.2.3")
        }
        #expect(throws: ManifestRequirementEditError.unsupportedRequirement("latest")) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", "latest"..<"2.0.0")"#), to: "1.2.3")
        }
    }

    @Test func pathDependencyNeverMatches() throws {
        #expect(throws: ManifestRequirementEditError.dependencyNotFound) {
            try rewrite(manifest(#".package(path: "../foo")"#), .url("../foo"), to: "1.2.3")
        }
    }

    @Test func interpolatedVersionIsNonLiteral() throws {
        #expect(throws: ManifestRequirementEditError.nonLiteralRequirement) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", from: "\(major).0.0")"#), to: "1.2.3")
        }
    }

    @Test func sameDependencyInConditionalCompilationIsAmbiguous() throws {
        let source = """
            import PackageDescription

            #if os(Linux)
            let deps: [Package.Dependency] = [.package(url: "\(Self.url)", from: "1.0.0")]
            #else
            let deps: [Package.Dependency] = [.package(url: "\(Self.url)", from: "1.1.0")]
            #endif
            let package = Package(name: "App", dependencies: deps)
            """
        #expect(throws: ManifestRequirementEditError.ambiguousDependency) {
            try rewrite(source, to: "1.2.3")
        }
    }

    @Test func rangeLowerBoundAlreadySatisfiedProducesNoEdit() throws {
        let source = manifest(#".package(url: "\#(Self.url)", "1.3.0"..<"2.0.0")"#)
        let syntax = Parser.parse(source: source)
        let edits = try ManifestRequirementEditor.raiseLowerBound(in: syntax, of: .url(Self.url), to: "1.2.3")
        #expect(edits.isEmpty)
    }

    @Test func closedRangeWithVersionEqualToUpperBoundStaysValid() throws {
        try expectRewrite(
            #".package(url: "\#(Self.url)", "1.0.0"..."1.5.0")"#,
            #".package(url: "\#(Self.url)", "1.5.0"..."1.5.0")"#,
            to: "1.5.0"
        )
    }

    @Test func revisionIsUnsupported() throws {
        #expect(throws: ManifestRequirementEditError.unsupportedRequirement("revision")) {
            try rewrite(manifest(#".package(url: "\#(Self.url)", .revision("abc123"))"#), to: "1.2.3")
        }
    }
}
