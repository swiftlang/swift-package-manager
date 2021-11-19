/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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
        let storage = FilePackageFingerprintStorage(customFileSystem: mockFileSystem)
        let registryURL = Foundation.URL(string: "https://example.packages.com")!
        let sourceControlURL = Foundation.URL(string: "https://example.com/mona/LinkedList.git")!

        // Add fingerprints for mona.LinkedList
        let package = PackageIdentity.plain("mona.LinkedList")
        try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"),
                                                callback: callback) }
        try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                fingerprint: .init(origin: .sourceControl(sourceControlURL), value: "gitHash-1.0.0"),
                                                callback: callback) }
        try tsc_await { callback in storage.put(package: package, version: Version("1.1.0"),
                                                fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.1.0"),
                                                callback: callback) }
        // Fingerprint for another package
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        try tsc_await { callback in storage.put(package: otherPackage, version: Version("1.0.0"),
                                                fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"),
                                                callback: callback) }

        // A checksum file should have been created for each package
        XCTAssertTrue(mockFileSystem.exists(storage.directory.appending(component: package.fingerprintFilename)))
        XCTAssertTrue(mockFileSystem.exists(storage.directory.appending(component: otherPackage.fingerprintFilename)))

        // Fingerprints should be saved
        do {
            let fingerprints = try tsc_await { callback in storage.get(package: package, version: Version("1.0.0"), callback: callback) }
            XCTAssertEqual(2, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.0.0", fingerprints[.registry]?.value)

            XCTAssertEqual(sourceControlURL, fingerprints[.sourceControl]?.origin.url)
            XCTAssertEqual("gitHash-1.0.0", fingerprints[.sourceControl]?.value)
        }

        do {
            let fingerprints = try tsc_await { callback in storage.get(package: package, version: Version("1.1.0"), callback: callback) }
            XCTAssertEqual(1, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.1.0", fingerprints[.registry]?.value)
        }

        do {
            let fingerprints = try tsc_await { callback in storage.get(package: otherPackage, version: Version("1.0.0"), callback: callback) }
            XCTAssertEqual(1, fingerprints.count)

            XCTAssertEqual(registryURL, fingerprints[.registry]?.origin.url)
            XCTAssertEqual("checksum-1.0.0", fingerprints[.registry]?.value)
        }
    }

    func testNotFound() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageFingerprintStorage(customFileSystem: mockFileSystem)
        let registryURL = Foundation.URL(string: "https://example.packages.com")!

        let package = PackageIdentity.plain("mona.LinkedList")
        try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"),
                                                callback: callback) }

        // No fingerprints found for the version
        XCTAssertThrowsError(try tsc_await { callback in storage.get(package: package, version: Version("1.1.0"), callback: callback) }) { error in
            guard case PackageFingerprintStorageError.notFound = error else {
                return XCTFail("Expected PackageFingerprintStorageError.notFound, got \(error)")
            }
        }

        // No fingerprints found for the packagge
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        XCTAssertThrowsError(try tsc_await { callback in storage.get(package: otherPackage, version: Version("1.0.0"), callback: callback) }) { error in
            guard case PackageFingerprintStorageError.notFound = error else {
                return XCTFail("Expected PackageFingerprintStorageError.notFound, got \(error)")
            }
        }
    }

    func testSingleFingerprintPerKind() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageFingerprintStorage(customFileSystem: mockFileSystem)
        let registryURL = Foundation.URL(string: "https://example.packages.com")!

        let package = PackageIdentity.plain("mona.LinkedList")
        // Write registry checksum for v1.0.0
        try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"),
                                                callback: callback) }

        // Writing for the same version and kind but different checksum should fail
        XCTAssertThrowsError(try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                                     fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0-1"),
                                                                     callback: callback) }) { error in
            guard case PackageFingerprintStorageError.conflict = error else {
                return XCTFail("Expected PackageFingerprintStorageError.conflict, got \(error)")
            }
        }

        // Writing for the same version and kind and same checksum should not fail
        XCTAssertNoThrow(try tsc_await { callback in storage.put(package: package, version: Version("1.0.0"),
                                                                 fingerprint: .init(origin: .registry(registryURL), value: "checksum-1.0.0"),
                                                                 callback: callback) })
    }
}

private extension PackageFingerprintStorage {
    func get(package: PackageIdentity,
             version: Version,
             callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void)
    {
        self.get(package: package,
                 version: version,
                 observabilityScope: ObservabilitySystem.NOOP,
                 callbackQueue: .sharedConcurrent,
                 callback: callback)
    }

    func put(package: PackageIdentity,
             version: Version,
             fingerprint: Fingerprint,
             callback: @escaping (Result<Void, Error>) -> Void)
    {
        self.put(package: package,
                 version: version,
                 fingerprint: fingerprint,
                 observabilityScope: ObservabilitySystem.NOOP,
                 callbackQueue: .sharedConcurrent,
                 callback: callback)
    }
}
