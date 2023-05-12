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
import PackageModel
import SPMTestSupport
import XCTest

import struct TSCBasic.ByteString
import class TSCBasic.InMemoryFileSystem

private let testArtifactID = "test-artifact"

private func generateInfoJSON(artifacts: [String: [Triple]]) -> String {
    """
    {
        "artifacts" : {
            \(artifacts.map {
                    """
                    "\($0)" : {
                        "type" : "swiftSDK",
                        "version" : "0.0.1",
                        "variants" : [
                            {
                                "path" : "\($0)/aarch64-unknown-linux",
                                "supportedTriples" : \($1.map(\.tripleString))
                            }
                        ]
                    }
                    """
                }.joined(separator: ",\n")
            )
        },
        "schemaVersion" : "1.0"
    }
    """
}

private struct MockBundle {
    let name: String
    let path: String
    let artifacts: [String: Triple]
}

private func generateTestFileSystem(bundleArtifacts: [[String: Triple]]) throws -> (some FileSystem, [MockBundle], AbsolutePath) {
    let bundles = bundleArtifacts.enumerated().map { (i, artifacts) in
        let bundleName = "test\(i).artifactbundle"
        return MockBundle(name: "test\(i).artifactbundle", path: "/\(bundleName)", artifacts: artifacts)
    }

    let fileSystem = InMemoryFileSystem(
        files: Dictionary(uniqueKeysWithValues: bundles.map {
            (
                "\($0.path)/info.json",
                ByteString(
                    encodingAsUTF8: generateInfoJSON(artifacts: $0.artifacts)
                )
            )
        })
    )

    let swiftSDKsDirectory = try AbsolutePath(validating: "/sdks")
    try fileSystem.createDirectory(fileSystem.tempDirectory)
    try fileSystem.createDirectory(swiftSDKsDirectory)

    return (fileSystem, bundles, swiftSDKsDirectory)
}

let arm64Triple = try! Triple("arm64-apple-macosx13.0")
let i686Triple = try! Triple("i686-apple-macosx13.0")

final class SwiftSDKBundleTests: XCTestCase {
    func testInstall() async throws {
        let system = ObservabilitySystem.makeForTesting()

        let (fileSystem, bundles, swiftSDKsDirectory) = try generateTestFileSystem(
            bundleArtifacts: [arm64Triple, arm64Triple]
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
            guard let error = error as? DestinationError else {
                XCTFail("Unexpected error type")
                return
            }

            print(error)
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
            guard let error = error as? DestinationError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case .destinationBundleAlreadyInstalled(let installedBundleName):
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
            guard let error = error as? DestinationError else {
                XCTFail("Unexpected error type")
                return
            }

            switch error {
            case .destinationArtifactAlreadyInstalled(let installedBundleName, let newBundleName, let artifactID):
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
            bundleArtifacts: [arm64Triple, i686Triple]
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
}
