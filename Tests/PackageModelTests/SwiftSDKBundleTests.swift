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
            ByteString(json: """
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
            """)
        ),

    ] + bundle.artifacts.map {
        (
            "\(bundle.path)/\($0.id)/\(targetTriple.tripleString)/swift-sdk.json",
            ByteString(json: try generateSwiftSDKMetadata(jsonEncoder))
        )
    }
}

private func generateSwiftSDKMetadata(_ encoder: JSONEncoder) throws -> SerializedJSON {
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
        let bundleName = "test\(i).\(artifactBundleExtension)"
        return MockBundle(name: "test\(i).\(artifactBundleExtension)", path: "/\(bundleName)", artifacts: [artifacts])
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

        var output = [SwiftSDKBundleStore.Output]()
        let store = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: fileSystem,
            observabilityScope: system.topScope,
            outputHandler: {
                output.append($0)
            }
        )

        try await store.install(bundlePathOrURL: bundles[0].path, archiver)

        let invalidPath = "foobar"
        do {
            try await store.install(bundlePathOrURL: invalidPath, archiver)

            XCTFail("Function expected to throw")
        } catch {
            guard let error = error as? SwiftSDKError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case let .invalidBundleArchive(archivePath):
                XCTAssertEqual(archivePath, AbsolutePath.root.appending(invalidPath))
            default:
                XCTFail("Unexpected error value")
            }
        }

        do {
            try await store.install(bundlePathOrURL: bundles[0].path, archiver)

            XCTFail("Function expected to throw")
        } catch {
            guard let error = error as? SwiftSDKError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case let .swiftSDKArtifactAlreadyInstalled(installedBundleName, newBundleName, artifactID):
                XCTAssertEqual(bundles[0].name, installedBundleName)
                XCTAssertEqual(newBundleName, "test0.\(artifactBundleExtension)")
                XCTAssertEqual(artifactID, testArtifactID)
            default:
                XCTFail("Unexpected error value")
            }
        }

        do {
            try await store.install(bundlePathOrURL: bundles[1].path, archiver)

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

        XCTAssertEqual(output, [])
    }

    func testList() async throws {
        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [
                .init(id: "\(testArtifactID)2", supportedTriples: [i686Triple]),
                .init(id: "\(testArtifactID)1", supportedTriples: [arm64Triple]),
            ]
        )
        let system = ObservabilitySystem.makeForTesting()
        let archiver = MockArchiver()

        var output = [SwiftSDKBundleStore.Output]()
        let store = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: fileSystem,
            observabilityScope: system.topScope,
            outputHandler: {
                output.append($0)
            }
        )

        for bundle in bundles {
            try await store.install(bundlePathOrURL: bundle.path, archiver)
        }

        let validBundles = try store.allValidBundles

        XCTAssertEqual(validBundles.count, bundles.count)

        XCTAssertEqual(validBundles.sortedArtifactIDs, ["\(testArtifactID)1", "\(testArtifactID)2"])
        XCTAssertEqual(output, [])
    }

    func testBundleSelection() async throws {
        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [
                .init(id: "\(testArtifactID)1", supportedTriples: [arm64Triple]),
                .init(id: "\(testArtifactID)2", supportedTriples: [i686Triple])
            ]
        )
        let system = ObservabilitySystem.makeForTesting()

        var output = [SwiftSDKBundleStore.Output]()
        let store = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: fileSystem,
            observabilityScope: system.topScope,
            outputHandler: {
                output.append($0)
            }
        )

        for bundle in bundles {
            try await store.install(bundlePathOrURL: bundle.path, MockArchiver())
        }

        let sdk = try store.selectBundle(
            matching: "\(testArtifactID)1",
            hostTriple: Triple("arm64-apple-macosx14.0")
        )

        XCTAssertEqual(sdk.targetTriple, targetTriple)
        XCTAssertEqual(output, [])
    }
}
