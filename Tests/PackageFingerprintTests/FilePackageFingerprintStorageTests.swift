//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import struct Foundation.URL
@testable import PackageFingerprint
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

final class FilePackageFingerprintStorageTests: XCTestCase {
    func testHappyCase() throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/fingerprints")
        let storage = FilePackageFingerprintStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)
        let registryURL = URL(string: "https://example.packages.com")!
        let sourceControlURL = URL(string: "https://example.com/mona/LinkedList.git")!

        // Add fingerprints for mona.LinkedList
        let package = PackageIdentity.plain("mona.LinkedList")
        try storage.put(package: package, version: Version("1.0.0"), fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"))
        try storage.put(package: package, version: Version("1.0.0"), fingerprint: .init(origin: .sourceControl(sourceControlURL), value: "gitHash-1.0.0"))
        try storage.put(package: package, version: Version("1.1.0"), fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.1.0"))
        // Fingerprint for another package
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        try storage.put(package: otherPackage, version: Version("1.0.0"), fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"))

        // A checksum file should have been created for each package
        XCTAssertTrue(mockFileSystem.exists(storage.directoryPath.appending(component: package.fingerprintFilename)))
        XCTAssertTrue(mockFileSystem.exists(storage.directoryPath.appending(component: otherPackage.fingerprintFilename)))

        // Fingerprints should be saved
        do {
            let fingerprints = try storage.get(package: package, version: Version("1.0.0"))
            XCTAssertEqual(2, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.0.0", fingerprints[.registry]?.value)

            XCTAssertEqual(sourceControlURL, fingerprints[.sourceControl]?.origin.url)
            XCTAssertEqual("gitHash-1.0.0", fingerprints[.sourceControl]?.value)
        }

        do {
            let fingerprints = try storage.get(package: package, version: Version("1.1.0"))
            XCTAssertEqual(1, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.1.0", fingerprints[.registry]?.value)
        }

        do {
            let fingerprints = try storage.get(package: otherPackage, version: Version("1.0.0"))
            XCTAssertEqual(1, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.0.0", fingerprints[.registry]?.value)
        }
    }

    func testNotFound() throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/fingerprints")
        let storage = FilePackageFingerprintStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)
        let registryURL = URL(string: "https://example.packages.com")!

        let package = PackageIdentity.plain("mona.LinkedList")
        try storage.put(package: package, version: Version("1.0.0"), fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"))

        // No fingerprints found for the version
        XCTAssertThrowsError(try storage.get(package: package, version: Version("1.1.0"))) { error in
            guard case PackageFingerprintStorageError.notFound = error else {
                return XCTFail("Expected PackageFingerprintStorageError.notFound, got \(error)")
            }
        }

        // No fingerprints found for the package
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        XCTAssertThrowsError(try storage.get(package: otherPackage, version: Version("1.0.0"))) { error in
            guard case PackageFingerprintStorageError.notFound = error else {
                return XCTFail("Expected PackageFingerprintStorageError.notFound, got \(error)")
            }
        }
    }

    func testSingleFingerprintPerKind() throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/fingerprints")
        let storage = FilePackageFingerprintStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)
        let registryURL = URL(string: "https://example.packages.com")!

        let package = PackageIdentity.plain("mona.LinkedList")
        // Write registry checksum for v1.0.0
        try storage.put(package: package, version: Version("1.0.0"), fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"))

        // Writing for the same version and kind but different checksum should fail
        XCTAssertThrowsError(try storage.put(package: package, version: Version("1.0.0"),
                                             fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0-1"))) { error in
            guard case PackageFingerprintStorageError.conflict = error else {
                return XCTFail("Expected PackageFingerprintStorageError.conflict, got \(error)")
            }
        }

        // Writing for the same version and kind and same checksum should not fail
        XCTAssertNoThrow(try storage.put(package: package, version: Version("1.0.0"),
                                         fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0")))
    }
}

private extension PackageFingerprintStorage {
    func get(package: PackageIdentity,
             version: Version) throws -> [Fingerprint.Kind: Fingerprint] {
        return try tsc_await {
            self.get(package: package,
                     version: version,
                     observabilityScope: ObservabilitySystem.NOOP,
                     callbackQueue: .sharedConcurrent,
                     callback: $0)
        }
    }

    func put(package: PackageIdentity,
             version: Version,
             fingerprint: Fingerprint) throws {
        return try tsc_await {
            self.put(package: package,
                     version: version,
                     fingerprint: fingerprint,
                     observabilityScope: ObservabilitySystem.NOOP,
                     callbackQueue: .sharedConcurrent,
                     callback: $0)
        }
    }
}
