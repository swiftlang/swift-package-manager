//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
import PackageModel
import PackageModelSyntax
import SPMTestSupport
@_spi(FixItApplier) import SwiftIDEUtils
import SwiftParser
import SwiftSyntax
import XCTest

func assertManifestRefactor(
    _ originalManifest: SourceFileSyntax,
    expectedManifest: SourceFileSyntax,
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: (SourceFileSyntax) throws -> [SourceEdit]
) rethrows {
    let edits = try operation(originalManifest)
    let editedManifestSource = FixItApplier.apply(edits: edits, to: originalManifest)

    let editedManifest = Parser.parse(source: editedManifestSource)
    assertStringsEqualWithDiff(
        editedManifest.description,
        expectedManifest.description,
        file: file,
        line: line
    )
}

class ManifestEditTests: XCTestCase {
    static let swiftSystemURL: SourceControlURL = "https://github.com/apple/swift-system.git"
    static let swiftSystemPackageDependency = PackageDependency.remoteSourceControl(
            identity: PackageIdentity(url: swiftSystemURL),
            nameForTargetDependencyResolutionOnly: nil,
            url: swiftSystemURL,
            requirement: .branch("main"), productFilter: .nothing
        )

    func testAddPackageDependencyExistingComma() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
                ]
            )
            """, expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ]
            )
            """) { manifest in
                try AddPackageDependency.addPackageDependency(
                    Self.swiftSystemPackageDependency,
                    to: manifest,
                    manifestDirectory: try! AbsolutePath(validating: "/")
                )
            }
    }

    func testAddPackageDependencyExistingNoComma() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1")
                ]
            )
            """, expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ]
            )
            """) { manifest in
                try AddPackageDependency.addPackageDependency(
                    Self.swiftSystemPackageDependency,
                    to: manifest,
                    manifestDirectory: try! AbsolutePath(validating: "/")
                )
            }
    }

    func testAddPackageDependencyExistingAppended() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1")
                ] + []
            )
            """, expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ] + []
            )
            """) { manifest in
                try AddPackageDependency.addPackageDependency(
                    Self.swiftSystemPackageDependency,
                    to: manifest,
                    manifestDirectory: try! AbsolutePath(validating: "/")
                )
        }
    }

    func testAddPackageDependencyExistingEmpty() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages",
                dependencies: [ ]
            )
            """,
            expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ]
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: manifest,
                manifestDirectory: try! AbsolutePath(validating: "/")
            )
        }
    }

    func testAddPackageDependencyNoExistingAtEnd() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages"
            )
            """, 
            expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ]
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: manifest,
                manifestDirectory: try! AbsolutePath(validating: "/")
            )
        }
    }

    func testAddPackageDependencyNoExistingMiddle() throws {
        try assertManifestRefactor("""
            let package = Package(
                name: "packages",
                targets: []
            )
            """,
            expectedManifest: """
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", .branch("main")),
                ],
                targets: []
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: manifest,
                manifestDirectory: try! AbsolutePath(validating: "/")
            )
        }
    }

    func testAddPackageDependencyErrors() {
        XCTAssertThrows(
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: """
                let package: Package = .init(
                    name: "packages"
                )
                """,
                manifestDirectory: try! AbsolutePath(validating: "/")
            )
        ) { (error: ManifestEditError) in
            if case .cannotFindPackage = error {
                return true
            } else {
                return false
            }
        }

        XCTAssertThrows(
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: """
                let package = Package(
                    name: "packages",
                    dependencies: blah
                )
                """,
                manifestDirectory: try! AbsolutePath(validating: "/")
            )
        ) { (error: ManifestEditError) in
            if case .cannotFindArrayLiteralArgument(argumentName: "dependencies", node: _) = error {
                return true
            } else {
                return false
            }
        }
    }
}


// FIXME: Copy-paste from _SwiftSyntaxTestSupport

/// Asserts that the two strings are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
public func assertStringsEqualWithDiff(
    _ actual: String,
    _ expected: String,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected {
        return
    }

    failStringsEqualWithDiff(
        actual,
        expected,
        message,
        additionalInfo: additionalInfo(),
        file: file,
        line: line
    )
}

/// Asserts that the two data are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
public func assertDataEqualWithDiff(
    _ actual: Data,
    _ expected: Data,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected {
        return
    }

    // NOTE: Converting to `Stirng` here looses invalid UTF8 sequence difference,
    // but at least we can see something is different.
    failStringsEqualWithDiff(
        String(decoding: actual, as: UTF8.self),
        String(decoding: expected, as: UTF8.self),
        message,
        additionalInfo: additionalInfo(),
        file: file,
        line: line
    )
}

/// `XCTFail` with `diff`-style output.
public func failStringsEqualWithDiff(
    _ actual: String,
    _ expected: String,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let stringComparison: String

    // Use `CollectionDifference` on supported platforms to get `diff`-like line-based output. On
    // older platforms, fall back to simple string comparison.
    if #available(macOS 10.15, *) {
        let actualLines = actual.components(separatedBy: .newlines)
        let expectedLines = expected.components(separatedBy: .newlines)

        let difference = actualLines.difference(from: expectedLines)

        var result = ""

        var insertions = [Int: String]()
        var removals = [Int: String]()

        for change in difference {
            switch change {
            case .insert(let offset, let element, _):
                insertions[offset] = element
            case .remove(let offset, let element, _):
                removals[offset] = element
            }
        }

        var expectedLine = 0
        var actualLine = 0

        while expectedLine < expectedLines.count || actualLine < actualLines.count {
            if let removal = removals[expectedLine] {
                result += "–\(removal)\n"
                expectedLine += 1
            } else if let insertion = insertions[actualLine] {
                result += "+\(insertion)\n"
                actualLine += 1
            } else {
                result += " \(expectedLines[expectedLine])\n"
                expectedLine += 1
                actualLine += 1
            }
        }

        stringComparison = result
    } else {
        // Fall back to simple message on platforms that don't support CollectionDifference.
        stringComparison = """
        Expected:
        \(expected)

        Actual:
        \(actual)
        """
    }

    var fullMessage = """
        \(message.isEmpty ? "Actual output does not match the expected" : message)
        \(stringComparison)
        """
    if let additional = additionalInfo() {
        fullMessage = """
        \(fullMessage)
        \(additional)
        """
    }
    XCTFail(fullMessage, file: file, line: line)
}
