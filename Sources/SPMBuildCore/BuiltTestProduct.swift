//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import struct PackageModel.PackageIdentity

/// Represents a test product which is built and is present on disk.
public struct BuiltTestProduct: Codable, Hashable {
    /// The test product name.
    public let productName: String

    /// The name of the "umbrella" test product (if any) which includes this test product
    public let umbrellaProductName: String?

    /// The path of the test binary.
    public let binaryPath: AbsolutePath

    /// The path of the artifact whose coverage mapping should be passed to `llvm-cov export`.
    ///
    /// For most build systems this is equal to ``binaryPath``. On SwiftBuild + non-Darwin,
    /// where ``binaryPath`` points at a thin `-test-runner` launcher, this points at the
    /// sibling shared library that actually holds the compiled test code (and therefore
    /// its coverage mapping).
    public let coverageBinaryPath: AbsolutePath

    /// The path to the package this product was declared in.
    public let packagePath: AbsolutePath

    /// The identity of the package this product was declared in, when
    /// known. Used by workspace-aware consumers (e.g. `swift test`'s
    /// xUnit aggregator) to attribute each test product to its owning
    /// workspace member.
    ///
    /// Optional so that older cached `BuiltTestProduct` values (from
    /// pre-workspace SwiftPM invocations that persisted this struct via
    /// `Codable`) still decode; consumers that require the identity
    /// should treat `nil` as "attribution unavailable" and fall back
    /// to their pre-workspace behavior.
    public let packageIdentity: PackageIdentity?

    /// The path of the test bundle.
    ///
    /// When the test product is not bundled (for instance, when using XCTest on
    /// non-Darwin targets), this path is equal to ``binaryPath``.
    public var bundlePath: AbsolutePath {
        // If the binary path is a test runner binary, return it as-is.
        guard !binaryPath.basenameWithoutExt.hasSuffix("test-runner") else {
            return binaryPath
        }
        // Go up the folder hierarchy until we find the .xctest bundle.
        let pathExtension = ".xctest"
        let hierarchySequence = sequence(first: binaryPath, next: { $0.isRoot ? nil : $0.parentDirectory })
        guard let bundlePath = hierarchySequence.first(where: { $0.basename.hasSuffix(pathExtension) }) else {
            fatalError("could not find test bundle path from '\(binaryPath)'")
        }

        return bundlePath
    }

    /// The path to the entry point source file (XCTMain.swift, LinuxMain.swift,
    /// etc.) used, if any.
    public let testEntryPointPath: AbsolutePath?

    /// Creates a new instance.
    /// - Parameters:
    ///   - productName: The test product name.
    ///   - binaryPath: The path of the test binary.
    ///   - packagePath: The path to the package this product was declared in.
    ///   - packageIdentity: The identity of the package this product was
    ///     declared in, when known. Defaults to `nil` for callers that
    ///     don't have identity information (e.g. legacy tests).
    ///   - mainSourceFilePath: The path to the main source file used, if any.
    ///   - coverageBinaryPath: The path of the artifact whose coverage mapping should be
    ///     fed to `llvm-cov`. Defaults to `binaryPath`; callers that build a test product
    ///     as a separate launcher + shared library should pass the shared library here.
    public init(
        productName: String,
        umbrellaProductName: String?,
        binaryPath: AbsolutePath,
        packagePath: AbsolutePath,
        packageIdentity: PackageIdentity? = nil,
        testEntryPointPath: AbsolutePath?,
        coverageBinaryPath: AbsolutePath? = nil,
    ) {
        self.productName = productName
        self.umbrellaProductName = umbrellaProductName
        self.binaryPath = binaryPath
        self.packagePath = packagePath
        self.packageIdentity = packageIdentity
        self.testEntryPointPath = testEntryPointPath
        self.coverageBinaryPath = coverageBinaryPath ?? binaryPath
    }
}
