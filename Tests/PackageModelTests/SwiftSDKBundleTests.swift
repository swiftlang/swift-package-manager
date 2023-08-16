//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageModel
import SPMTestSupport
import XCTest

import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import protocol TSCBasic.FileSystem
import class TSCBasic.InMemoryFileSystem

private let testArtifactID = "test-artifact"

private let targetTriple = try! Triple("aarch64-unknown-linux")

private let jsonEncoder = JSONEncoder()

private func generateBundleFiles(bundle: MockBundle) throws -> [(String, ByteString)] {
    try [
        (
            "\(bundle.path)/info.json",
            ByteString("""
            {
                "artifacts" : {
                    \(bundle.artifacts.map {
                            """
                            "\($0.id)" : {
                                "type" : "swiftSDK",
                                "version" : "0.0.1",
                                "variants" : [
                                    {
                                        "path" : "\($0.id)/\(targetTriple.triple)",
                                        "supportedTriples" : \($0.supportedTriples.map(\.tripleString))
                                    }
                                ]
                            }
                            """
                        }.joined(separator: ",\n")
                    )
                },
                "schemaVersion" : "1.0"
            }
            """.utf8)
        ),

    ] + bundle.artifacts.map {
        (
            "\(bundle.path)/\($0.id)/\(targetTriple.tripleString)/swift-sdk.json",
            ByteString(try generateSwiftSDKMetadata(jsonEncoder).utf8)
        )
    }
}

private func generateSwiftSDKMetadata(_ encoder: JSONEncoder) throws -> String {
    try """
    {
        "schemaVersion": "4.0",
        "targetTriples": \(
            String(
                bytes: encoder.encode([
                    targetTriple.tripleString: SwiftSDKMetadataV4.TripleProperties(sdkRootPath: "sdk")
                ]),
                encoding: .utf8
            )!
        )
    }
    """
}

private struct MockBundle {
    let name: String
    let path: String
    let artifacts: [MockArtifact]
}

private struct MockArtifact {
    let id: String
    let supportedTriples: [Triple]
}

private func generateTestFileSystem(bundleArtifacts: [MockArtifact]) throws -> (some FileSystem, [MockBundle], AbsolutePath) {
    let bundles = bundleArtifacts.enumerated().map { (i, artifacts) in
        let bundleName = "test\(i).artifactbundle"
        return MockBundle(name: "test\(i).artifactbundle", path: "/\(bundleName)", artifacts: [artifacts])
    }


    let fileSystem = try InMemoryFileSystem(
        files: Dictionary(
            uniqueKeysWithValues: bundles.flatMap {
                try generateBundleFiles(bundle: $0)
            }
        )
    )

    let swiftSDKsDirectory = try AbsolutePath(validating: "/sdks")
    try fileSystem.createDirectory(fileSystem.tempDirectory)
    try fileSystem.createDirectory(swiftSDKsDirectory)

    return (fileSystem, bundles, swiftSDKsDirectory)
}

private let arm64Triple = try! Triple("arm64-apple-macosx13.0")
let i686Triple = try! Triple("i686-apple-macosx13.0")

final class SwiftSDKBundleTests: XCTestCase {
    func testInstall() async throws {
        let system = ObservabilitySystem.makeForTesting()

        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [
                .init(id: testArtifactID, supportedTriples: [arm64Triple]),
                .init(id: testArtifactID, supportedTriples: [arm64Triple])
            ]
        )

        let archiver = MockArchiver()

        try SwiftSDKBundle.install(
            bundlePathOrURL: bundles[0].path,
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem,
            archiver,
            system.topScope
        )

        let invalidPath = "foobar"
        do {
            try SwiftSDKBundle.install(
                bundlePathOrURL: "foobar",
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem,
                archiver,
                system.topScope
            )

            XCTFail("Function expected to throw")
        } catch {
            guard let error = error as? SwiftSDKError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case .invalidBundleName(let bundleName):
                XCTAssertEqual(bundleName, invalidPath)
            default:
                XCTFail("Unexpected error value")
            }
        }

        do {
            try SwiftSDKBundle.install(
                bundlePathOrURL: bundles[0].path,
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem,
                archiver,
                system.topScope
            )

            XCTFail("Function expected to throw")
        } catch {
            guard let error = error as? SwiftSDKError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case .swiftSDKBundleAlreadyInstalled(let installedBundleName):
                XCTAssertEqual(bundles[0].name, installedBundleName)
            default:
                XCTFail("Unexpected error value")
            }
        }

        do {
            try SwiftSDKBundle.install(
                bundlePathOrURL: bundles[1].path,
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem,
                archiver,
                system.topScope
            )

             XCTFail("Function expected to throw")
         } catch {
            guard let error = error as? SwiftSDKError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case .swiftSDKArtifactAlreadyInstalled(let installedBundleName, let newBundleName, let artifactID):
                XCTAssertEqual(bundles[0].name, installedBundleName)
                XCTAssertEqual(bundles[1].name, newBundleName)
                XCTAssertEqual(artifactID, testArtifactID)
            default:
                XCTFail("Unexpected error value")
            }
        }
    }

    func testList() async throws {
        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [
                .init(id: "\(testArtifactID)1", supportedTriples: [arm64Triple]),
                .init(id: "\(testArtifactID)2", supportedTriples: [i686Triple])
            ]
        )
        let system = ObservabilitySystem.makeForTesting()

        for bundle in bundles {
            try SwiftSDKBundle.install(
                bundlePathOrURL: bundle.path,
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem,
                MockArchiver(),
                system.topScope
            )
        }

        let validBundles = try SwiftSDKBundle.getAllValidBundles(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: fileSystem,
            observabilityScope: system.topScope
        )

        XCTAssertEqual(validBundles.count, bundles.count)
    }

    func testBundleSelection() async throws {
        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [
                .init(id: "\(testArtifactID)1", supportedTriples: [arm64Triple]),
                .init(id: "\(testArtifactID)2", supportedTriples: [i686Triple])
            ]
        )
        let system = ObservabilitySystem.makeForTesting()

        for bundle in bundles {
            try SwiftSDKBundle.install(
                bundlePathOrURL: bundle.path,
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem,
                MockArchiver(),
                system.topScope
            )
        }

        let sdk = try SwiftSDKBundle.selectBundle(
            fromBundlesAt: swiftSDKsDirectory,
            fileSystem: fileSystem,
            matching: "\(testArtifactID)1",
            hostTriple: Triple("arm64-apple-macosx14.0"),
            observabilityScope: system.topScope
        )

        XCTAssertEqual(sdk.targetTriple, targetTriple)
    }
}
