//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import Basics
import PackageModel
@testable import PackageSigning
import _InternalTestSupport
import Testing

import struct TSCUtility.Version

struct FilePackageSigningEntityStorageTests {
    @Test
    func happyCase() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        // Record signing entities for mona.LinkedList
        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit 1",
            organization: "SwiftPM Test"
        )
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit 2",
            organization: "SwiftPM Test"
        )
        try storage.put(
            package: package,
            version: Version("1.0.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )
        try storage.put(
            package: package,
            version: Version("1.1.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://bar.com"))
        )
        try storage.put(
            package: package,
            version: Version("2.0.0"),
            signingEntity: appleseed,
            origin: .registry(URL("http://foo.com"))
        )
        // Record signing entity for another package
        let otherPackage = PackageIdentity.plain("other.LinkedList")
        try storage.put(
            package: otherPackage,
            version: Version("1.0.0"),
            signingEntity: appleseed,
            origin: .registry(URL("http://foo.com"))
        )

        // A data file should have been created for each package
        #expect(mockFileSystem.exists(storage.directoryPath.appending(component: package.signedVersionsFilename)))
        #expect(mockFileSystem
            .exists(storage.directoryPath.appending(component: otherPackage.signedVersionsFilename)))

        // Signed versions should be saved
        do {
            let packageSigners = try storage.get(package: package)
            #expect(packageSigners.expectedSigner == nil)
            #expect(packageSigners.signers.count == 2)
            #expect(packageSigners.signers[davinci]?.versions == [Version("1.0.0"), Version("1.1.0")])
            #expect(packageSigners.signers[davinci]?.origins == [.registry(URL("http://foo.com")), .registry(URL("http://bar.com"))])
            #expect(packageSigners.signers[appleseed]?.versions == [Version("2.0.0")])
            #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://foo.com"))])
        }

        do {
            let packageSigners = try storage.get(package: otherPackage)
            #expect(packageSigners.expectedSigner == nil)
            #expect(packageSigners.signers.count == 1)
            #expect(packageSigners.signers[appleseed]?.versions == [Version("1.0.0")])
            #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://foo.com"))])
        }
    }

    @Test
    func putDifferentSigningEntityShouldConflict() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit 1",
            organization: "SwiftPM Test"
        )
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit 2",
            organization: "SwiftPM Test"
        )
        let version = Version("1.0.0")
        try storage.put(
            package: package,
            version: version,
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        // Writing different signing entities for the same version should fail
        #expect {
            try storage.put(
                package: package,
                version: version,
                signingEntity: appleseed,
                origin: .registry(URL("http://foo.com"))
            )
        } throws: { error in
            guard case PackageSigningEntityStorageError.conflict = error else {
                Issue.record("Expected PackageSigningEntityStorageError.conflict, got \(error)")
                return false
            }
            return true
        }
        // await XCTAssertAsyncThrowsError(try storage.put(
        //     package: package,
        //     version: version,
        //     signingEntity: appleseed,
        //     origin: .registry(URL("http://foo.com"))
        // )) { error in
        //     guard case PackageSigningEntityStorageError.conflict = error else {
        //         Issue.record("Expected PackageSigningEntityStorageError.conflict, got \(error)")
        //         return
        //     }
        // }
    }

    @Test
    func putSameSigningEntityShouldNotConflict() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit",
            organization: "SwiftPM Test"
        )
        let version = Version("1.0.0")
        try storage.put(
            package: package,
            version: version,
            signingEntity: appleseed,
            origin: .registry(URL("http://foo.com"))
        )

        // Writing same signing entity for version should be ok
        try storage.put(
            package: package,
            version: version,
            signingEntity: appleseed,
            origin: .registry(URL("http://bar.com")) // origin is different and should be added
        )

        let packageSigners = try storage.get(package: package)
        #expect(packageSigners.expectedSigner == nil)
        #expect(packageSigners.signers.count == 1)
        #expect(packageSigners.signers[appleseed]?.versions == [Version("1.0.0")])
        #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://foo.com")), .registry(URL("http://bar.com"))])
    }

    @Test
    func putUnrecognizedSigningEntityShouldError() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.unrecognized(name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let version = Version("1.0.0")

        #expect {
            try storage.put(
                package: package,
                version: version,
                signingEntity: appleseed,
                origin: .registry(URL("http://bar.com")) // origin is different and should be added
            )
        } throws: { error in
            guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
                Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
                return false
            }
            return true
        }
        // await XCTAssertAsyncThrowsError(try storage.put(
        //     package: package,
        //     version: version,
        //     signingEntity: appleseed,
        //     origin: .registry(URL("http://bar.com")) // origin is different and should be added
        // )) { error in
        //     guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
        //         Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
        //         return
        //     }
        // }
    }

    @Test
    func addDifferentSigningEntityShouldNotConflict() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit 1",
            organization: "SwiftPM Test"
        )
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit 2",
            organization: "SwiftPM Test"
        )
        let version = Version("1.0.0")
        try storage.put(
            package: package,
            version: version,
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        // Adding different signing entity for the same version should not fail
        try storage.add(
            package: package,
            version: version,
            signingEntity: appleseed,
            origin: .registry(URL("http://bar.com"))
        )

        let packageSigners = try storage.get(package: package)
        #expect(packageSigners.expectedSigner == nil)
        #expect(packageSigners.signers.count == 2)
        #expect(packageSigners.signers[appleseed]?.versions == [Version("1.0.0")])
        #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://bar.com"))])
        #expect(packageSigners.signers[davinci]?.versions == [Version("1.0.0")])
        #expect(packageSigners.signers[davinci]?.origins == [.registry(URL("http://foo.com"))])
        #expect(packageSigners.signingEntities(of: Version("1.0.0")) == [appleseed, davinci])
    }

    @Test
    func addUnrecognizedSigningEntityShouldError() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.unrecognized(name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit",
            organization: "SwiftPM Test"
        )
        let version = Version("1.0.0")
        try storage.put(
            package: package,
            version: version,
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        #expect {
            try storage.add(
                package: package,
                version: version,
                signingEntity: appleseed,
                origin: .registry(URL("http://bar.com"))
            )
        } throws: { error in
            guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
                Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
                return false
            }
            return true
        }
        // await XCTAssertAsyncThrowsError(try storage.add(
        //     package: package,
        //     version: version,
        //     signingEntity: appleseed,
        //     origin: .registry(URL("http://bar.com"))
        // )) { error in
        //     guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
        //         Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
        //         return
        //     }
        // }
    }

    @Test
    func changeSigningEntityFromVersion() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit 1",
            organization: "SwiftPM Test"
        )
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit 2",
            organization: "SwiftPM Test"
        )
        try storage.put(
            package: package,
            version: Version("1.0.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        // Sets package's expectedSigner and add package version signer
        try storage.changeSigningEntityFromVersion(
            package: package,
            version: Version("1.5.0"),
            signingEntity: appleseed,
            origin: .registry(URL("http://bar.com"))
        )

        let packageSigners = try storage.get(package: package)
        #expect(packageSigners.expectedSigner?.signingEntity == appleseed)
        #expect(packageSigners.expectedSigner?.fromVersion == Version("1.5.0"))
        #expect(packageSigners.signers.count == 2)
        #expect(packageSigners.signers[appleseed]?.versions == [Version("1.5.0")])
        #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://bar.com"))])
        #expect(packageSigners.signers[davinci]?.versions == [Version("1.0.0")])
        #expect(packageSigners.signers[davinci]?.origins == [.registry(URL("http://foo.com"))])
    }

    @Test
    func changeSigningEntityFromVersion_unrecognizedSigningEntityShouldError() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.unrecognized(name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit",
            organization: "SwiftPM Test"
        )
        try storage.put(
            package: package,
            version: Version("1.0.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        #expect {
            try storage.changeSigningEntityFromVersion(
                package: package,
                version: Version("1.5.0"),
                signingEntity: appleseed,
                origin: .registry(URL("http://bar.com"))
            )
        } throws: { error in
            guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
                Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
                return false
            }
            return true
        }
    }

    @Test
    func changeSigningEntityForAllVersions() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: "SwiftPM Test Unit 1",
            organization: "SwiftPM Test"
        )
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit 2",
            organization: "SwiftPM Test"
        )
        try storage.put(
            package: package,
            version: Version("1.0.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )
        try storage.put(
            package: package,
            version: Version("2.0.0"),
            signingEntity: appleseed,
            origin: .registry(URL("http://bar.com"))
        )

        // Sets package's expectedSigner and remove all other signers
        try storage.changeSigningEntityForAllVersions(
            package: package,
            version: Version("1.5.0"),
            signingEntity: appleseed,
            origin: .registry(URL("http://bar.com"))
        )

        let packageSigners = try storage.get(package: package)
        #expect(packageSigners.expectedSigner?.signingEntity == appleseed)
        #expect(packageSigners.expectedSigner?.fromVersion == Version("1.5.0"))
        #expect(packageSigners.signers.count == 1)
        #expect(packageSigners.signers[appleseed]?.versions == [Version("1.5.0"), Version("2.0.0")])
        #expect(packageSigners.signers[appleseed]?.origins == [.registry(URL("http://bar.com"))])
    }

    @Test
    func changeSigningEntityForAllVersions_unrecognizedSigningEntityShouldError() async throws {
        let mockFileSystem = InMemoryFileSystem()
        let directoryPath = AbsolutePath("/signing")
        let storage = FilePackageSigningEntityStorage(fileSystem: mockFileSystem, directoryPath: directoryPath)

        let package = PackageIdentity.plain("mona.LinkedList")
        let appleseed = SigningEntity.unrecognized(name: "J. Appleseed", organizationalUnit: nil, organization: nil)
        let davinci = SigningEntity.recognized(
            type: .adp,
            name: "L. da Vinci",
            organizationalUnit: "SwiftPM Test Unit",
            organization: "SwiftPM Test"
        )
        try storage.put(
            package: package,
            version: Version("1.0.0"),
            signingEntity: davinci,
            origin: .registry(URL("http://foo.com"))
        )

        #expect {
            try storage.changeSigningEntityForAllVersions(
                package: package,
                version: Version("1.5.0"),
                signingEntity: appleseed,
                origin: .registry(URL("http://bar.com"))
            )
        } throws: { error in
            guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
                Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
                return false
            }
            return true
        }
        // await XCTAsserttAsyncThrowsError(try storage.changeSigningEntityForAllVersions(
        //     package: package,
        //     version: Version("1.5.0"),
        //     signingEntity: appleseed,
        //     origin: .registry(URL("http://bar.com"))
        // )) { error in
        //     guard case PackageSigningEntityStorageError.unrecognizedSigningEntity = error else {
        //         Issue.record("Expected PackageSigningEntityStorageError.unrecognizedSigningEntity but got \(error)")
        //         return
        //     }
        // }
    }
}

extension PackageSigningEntityStorage {
    fileprivate func get(package: PackageIdentity) throws -> PackageSigners {
        try self.get(
            package: package,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin
    ) throws {
        try self.put(
            package: package,
            version: version,
            signingEntity: signingEntity,
            origin: origin,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin
    ) throws {
        try self.add(
            package: package,
            version: version,
            signingEntity: signingEntity,
            origin: origin,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin
    ) throws {
        try self.changeSigningEntityFromVersion(
            package: package,
            version: version,
            signingEntity: signingEntity,
            origin: origin,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin
    ) throws {
        try self.changeSigningEntityForAllVersions(
            package: package,
            version: version,
            signingEntity: signingEntity,
            origin: origin,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }
}
