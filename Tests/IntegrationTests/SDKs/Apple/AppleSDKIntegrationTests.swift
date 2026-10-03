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

import Basics
import Foundation
import Testing
import _InternalTestSupport

/// Verifies that cross-compiling for non-macOS Apple platforms with `--triple` using Swift Build produces binaries
/// for the requested platform, as recorded in the Mach-O `LC_BUILD_VERSION` load command.
@Suite(
    .tags(
        .TestSize.large,
        .Feature.SDK.Apple,
        .Feature.CommandLineArguments.Triple,
    ),
    .requireHostOS(.macOS),
)
struct AppleSDKIntegrationTests {
    struct Destination: Sendable, CustomTestStringConvertible {
        /// The value passed to `--triple`.
        var triple: String
        /// The platform name printed by `vtool -show-build`.
        var expectedPlatform: String
        /// The expected minimum OS version recorded in the binary.
        var expectedMinOS: String

        var testDescription: String { triple }
    }

    static let iOSDestinations = [
        Destination(triple: "arm64-apple-ios17.0", expectedPlatform: "IOS", expectedMinOS: "17.0"),
        Destination(triple: "arm64-apple-ios17.0-simulator", expectedPlatform: "IOSSIMULATOR", expectedMinOS: "17.0"),
    ]

    static let visionOSDestinations = [
        Destination(triple: "arm64-apple-xros1.0", expectedPlatform: "VISIONOS", expectedMinOS: "1.0"),
        Destination(triple: "arm64-apple-xros1.0-simulator", expectedPlatform: "VISIONOSSIMULATOR", expectedMinOS: "1.0"),
        // LLVM also accepts `visionos` as an alias of `xros`.
        Destination(triple: "arm64-apple-visionos2.0", expectedPlatform: "VISIONOS", expectedMinOS: "2.0"),
    ]

    static let driverKitDestinations = [
        Destination(triple: "arm64-apple-driverkit21.0", expectedPlatform: "DRIVERKIT", expectedMinOS: "21.0"),
        Destination(triple: "x86_64-apple-driverkit21.0", expectedPlatform: "DRIVERKIT", expectedMinOS: "21.0"),
    ]

    @Test(
        .requiresAppleSDKs("iphoneos", "iphonesimulator"),
        arguments: iOSDestinations,
    )
    func swiftLibraryForiOS(destination: Destination) async throws {
        try await Self.buildAndVerify(
            fixtureName: "ValidLayouts/SingleModule/Library",
            destination: destination,
        )
    }

    @Test(
        .requiresAppleSDKs("xros", "xrsimulator"),
        arguments: visionOSDestinations,
    )
    func swiftLibraryForVisionOS(destination: Destination) async throws {
        try await Self.buildAndVerify(
            fixtureName: "ValidLayouts/SingleModule/Library",
            destination: destination,
        )
    }

    /// Swift does not support DriverKit, so this uses a C-only package.
    @Test(
        .requiresAppleSDKs("driverkit"),
        arguments: driverKitDestinations,
    )
    func cLibraryForDriverKit(destination: Destination) async throws {
        try await Self.buildAndVerify(
            fixtureName: "CFamilyTargets/CLibrarySources",
            destination: destination,
        )
    }

    private static func buildAndVerify(
        fixtureName: String,
        destination: Destination,
    ) async throws {
        try await fixture(name: fixtureName) { fixturePath in
            let output = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--triple", destination.triple],
                buildSystem: .swiftbuild,
            )
            #expect(output.stdout.contains("Build complete"))

            let objects = try await objectFiles(in: fixturePath.appending(".build"))
            try #require(!objects.isEmpty, "No object files were produced")
            for object in objects {
                let buildVersion = try await AsyncProcess.checkNonZeroExit(
                    args: "/usr/bin/xcrun", "vtool", "-show-build", object.pathString
                )
                let platforms = Self.fields(named: "platform", in: buildVersion)
                let minOSes = Self.fields(named: "minos", in: buildVersion)
                #expect(platforms == [destination.expectedPlatform], "Unexpected platform for \(object)")
                #expect(minOSes == [destination.expectedMinOS], "Unexpected minimum OS version for \(object)")
            }
        }
    }

    /// Returns all Mach-O object files in `directory`, excluding module caches.
    private static func objectFiles(in directory: AbsolutePath) async throws -> [AbsolutePath] {
        let output = try await AsyncProcess.checkNonZeroExit(
            args: "/usr/bin/find", directory.pathString, "-name", "*.o", "-not", "-path", "*/ModuleCache/*"
        )
        return try output.split(whereSeparator: \.isNewline).map { try AbsolutePath(validating: String($0)) }
    }

    /// Extracts the values of e.g. `platform IOS` lines from `vtool -show-build` output.
    private static func fields(named name: String, in output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count == 2, components[0] == name else { return nil }
            return String(components[1])
        }
    }
}
