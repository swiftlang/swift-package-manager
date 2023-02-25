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
@testable import PackageSigning
import SPMTestSupport
import TSCBasic
import XCTest

import struct TSCUtility.Version

final class FilePackageSigningEntityStorageTests: XCTestCase {
    func testHappyCase() throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath(path: "/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        // Record signing entities for mona.LinkedList
        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity(type: nil, name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let davinci = SigningEntity(type: nil, name: "L. da Vinci", organizationalUnit: nil, organization: nil)
        try storage.put(package: package, version: Version("1.0.0"), signingEntity: davinci)
        try storage.put(package: package, version: Version("1.1.0"), signingEntity: davinci)
        try storage.put(package: package, version: Version("2.0.0"), signingEntity: appleseed)
        // Record signing entity for another package
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        try storage.put(package: otherPackage, version: Version("1.0.0"), signingEntity: appleseed)

        // A data file should have been created for each package
        XCTAssertTrue(mockFileSystem.exists(storage.directoryPath.appending(component: package.signedVersionsFilename)))
        XCTAssertTrue(
            mockFileSystem
                .exists(storage.directoryPath.appending(component: otherPackage.signedVersionsFilename))
        )

        // Signed versions should be saved
        do {
            let signedVersions = try storage.get(package: package)
            XCTAssertEqual(signedVersions.count, 2)
            XCTAssertEqual(signedVersions[davinci], [Version("1.0.0"), Version("1.1.0")])
            XCTAssertEqual(signedVersions[appleseed], [Version("2.0.0")])
        }

        do {
            let signedVersions = try storage.get(package: otherPackage)
            XCTAssertEqual(signedVersions.count, 1)
            XCTAssertEqual(signedVersions[appleseed], [Version("1.0.0")])
        }
    }

    func testSingleFingerprintPerKind() throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath(path: "/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity(type: nil, name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let davinci = SigningEntity(type: nil, name: "L. da Vinci", organizationalUnit: nil, organization: nil)
        let version = Version("1.0.0")
        try storage.put(package: package, version: version, signingEntity: davinci)

        // Writing different signing entities for the same version should fail
        XCTAssertThrowsError(try storage.put(package: package, version: version, signingEntity: appleseed)) { error in
            guard case PackageSigningEntityStorageError.conflict = error else {
                return XCTFail("Expected PackageSigningEntityStorageError.conflict, got \(error)")
            }
        }
    }
}

extension PackageSigningEntityStorage {
    fileprivate func get(package: PackageIdentity) throws -> [SigningEntity: Set<Version>] {
        try tsc_await {
            self.get(
                package: package,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: $0
            )
        }
    }

    fileprivate func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity
    ) throws {
        try tsc_await {
            self.put(
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: $0
            )
        }
    }
}
