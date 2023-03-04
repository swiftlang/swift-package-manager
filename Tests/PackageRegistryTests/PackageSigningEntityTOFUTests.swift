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
@testable import PackageRegistry
import PackageSigning
import SPMTestSupport
import TSCBasic
import XCTest

import struct TSCUtility.Version

final class PackageSigningEntityTOFUTests: XCTestCase {
    func testSigningEntitySeenForTheFirstTime() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Package doesn't have any recorded signer.
        // It should be ok to assign one.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        )

        // `signingEntity` meets requirement to be used for TOFU
        // (i.e., it's .recognized), so it should be saved to storage.
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[signingEntity], [version])
    }

    func testNilSigningEntityShouldNotBeSaved() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Package doesn't have any recorded signer.
        // It should be ok to continue not to have one.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: .none
            )
        )

        // `signingEntity` is nil, so it should not be saved to storage.
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertTrue(signedVersions.isEmpty)
    }

    func testUnrecognizedSigningEntityShouldNotBeSaved() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.unrecognized(
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Package doesn't have any recorded signer.
        // It should be ok to continue not to have one.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        )

        // `signingEntity` is not .recognized, so it should not be saved to storage.
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertTrue(signedVersions.isEmpty)
    }

    func testSigningEntityMatchesStorageForSameVersion() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [signingEntity: [version]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has "J. Appleseed" as signer for package version.
        // Signer remaining the same should be ok.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        )
    }

    func testSigningEntityDoesNotMatchStorageForSameVersion_strictMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: [version]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has "J. Smith" as signer for package version.
        // The given signer "J. Appleseed" is different so it should fail.
        XCTAssertThrowsError(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        ) { error in
            guard case RegistryError.signingEntityForReleaseChanged(_, _, _, let previous) = error else {
                return XCTFail("Expected RegistryError.signingEntityForReleaseChanged, got '\(error)'")
            }
            XCTAssertEqual(previous, existingSigner)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], [version])
    }

    func testSigningEntityDoesNotMatchStorageForSameVersion_warnMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: [version]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.warn // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let observability = ObservabilitySystem.makeForTesting()

        // Storage has "J. Smith" as signer for package version.
        // The given signer "J. Appleseed" is different, but because
        // of .warn mode, no error is thrown.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], [version])
    }

    func testSigningEntityMatchesStorageForDifferentVersion() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let existingVersion = Version("2.0.0")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [signingEntity: [existingVersion]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has "J. Appleseed" as signer for package.
        // Signer remaining the same should be ok.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        )

        // Storage should be updated with version 1.1.1 added
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[signingEntity], [existingVersion, version])
    }

    func testSigningEntityDoesNotMatchStorageForDifferentVersion_strictMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let existingVersion = Version("2.0.0")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: [existingVersion]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has "J. Smith" as signer for package.
        // The given signer "J. Appleseed" is different so it should fail.
        XCTAssertThrowsError(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        ) { error in
            guard case RegistryError.signingEntityForPackageChanged(_, _, let previous) = error else {
                return XCTFail("Expected RegistryError.signingEntityForPackageChanged, got '\(error)'")
            }
            XCTAssertEqual(previous, existingSigner)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], [existingVersion])
    }

    func testSigningEntityDoesNotMatchStorageForDifferentVersion_warnMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let existingVersion = Version("2.0.0")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: [existingVersion]]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.warn // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let observability = ObservabilitySystem.makeForTesting()

        // Storage has "J. Smith" as signer for package.
        // The given signer "J. Appleseed" is different, but because
        // of .warn mode, no error is thrown.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], [existingVersion])
    }

    func testNilSigningEntityWhenStorageHasNewerSignedVersions() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let existingVersions = Set([Version("1.5.0"), Version("2.0.0")])
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: existingVersions]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has versions 1.5.0 and 2.0.0 signed. The given version 1.1.1 is
        // "older" than both, and we allow nil signer in this case, assuming
        // this is before package started being signed.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: .none
            )
        )

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], existingVersions)
    }

    func testNilSigningEntityWhenStorageHasOlderSignedVersions_strictMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.6.1")
        let existingVersions = Set([Version("1.5.0"), Version("2.0.0")])
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: existingVersions]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has versions 1.5.0 and 2.0.0 signed. The given version 1.6.1 is
        // "newer" than 1.5.0, which we don't allow, because we assume from 1.5.0
        // onwards all versions are signed.
        XCTAssertThrowsError(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: .none
            )
        ) { error in
            guard case RegistryError.signingEntityForPackageChanged(_, let latest, let previous) = error else {
                return XCTFail("Expected RegistryError.signingEntityForPackageChanged, got '\(error)'")
            }
            XCTAssertNil(latest)
            XCTAssertEqual(previous, existingSigner)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], existingVersions)
    }

    func testNilSigningEntityWhenStorageHasOlderSignedVersions_warnMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.6.1")
        let existingVersions = Set([Version("1.5.0"), Version("2.0.0")])
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: existingVersions]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.warn // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let observability = ObservabilitySystem.makeForTesting()

        // Storage has versions 1.5.0 and 2.0.0 signed. The given version 1.6.1 is
        // "newer" than 1.5.0, which we don't allow, because we assume from 1.5.0
        // onwards all versions are signed. However, because of .warn mode,
        // no error is thrown.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: .none,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], existingVersions)
    }

    func testNilSigningEntityWhenStorageHasOlderSignedVersionsInDifferentMajorVersion() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("2.0.0")
        let existingVersions = Set([Version("1.5.0"), Version("3.0.0")])
        let existingSigner = SigningEntity.recognized(
            type: .adp,
            name: "J. Smith",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = MockPackageSigningEntityStorage(
            [package.underlying: [existingSigner: existingVersions]]
        )
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // Storage has versions 1.5.0 and 3.0.0 signed. The given version 2.0.0 is
        // "newer" than 1.5.0, but in a different major version (i.e., 1.x vs. 2.x).
        // We allow this with the assumption that package signing might not have
        // begun until a later 2.x version, so until we encounter a signed 2.x version,
        // we assume none of them is signed.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: .none
            )
        )

        // Storage should not be updated
        let signedVersions = try tsc_await { callback in
            signingEntityStorage.get(
                package: package.underlying,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(signedVersions.count, 1)
        XCTAssertEqual(signedVersions[existingSigner], existingVersions)
    }

    func testWriteConflictsWithStorage_strictMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = WriteConflictSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // This triggers a storage write conflict
        XCTAssertThrowsError(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity
            )
        ) { error in
            guard case RegistryError.signingEntityForReleaseChanged = error else {
                return XCTFail("Expected RegistryError.signingEntityForReleaseChanged, got '\(error)'")
            }
        }
    }

    func testWriteConflictsWithStorage_warnMode() throws {
        let package = PackageIdentity.plain("mona.LinkedList").registry!
        let version = Version("1.1.1")
        let signingEntity = SigningEntity.recognized(
            type: .adp,
            name: "J. Appleseed",
            organizationalUnit: nil,
            organization: nil
        )

        let signingEntityStorage = WriteConflictSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.warn // intended for this test; don't change

        let tofu = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let observability = ObservabilitySystem.makeForTesting()

        // This triggers a storage write conflict, but
        // because of .warn mode, no error is thrown.
        XCTAssertNoThrow(
            try tofu.validate(
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }
    }
}

extension PackageSigningEntityTOFU {
    fileprivate func validate(
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        observabilityScope: ObservabilityScope? = nil
    ) throws {
        try tsc_await {
            self.validate(
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: observabilityScope ?? ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }
}

private class WriteConflictSigningEntityStorage: PackageSigningEntityStorage {
    func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[SigningEntity: Set<Version>], Error>) -> Void
    ) {
        callback(.success([:]))
    }

    func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let existing = SigningEntity.unrecognized(
            name: "xxx-\(signingEntity.name ?? "")",
            organizationalUnit: nil,
            organization: nil
        )
        callback(.failure(PackageSigningEntityStorageError.conflict(
            package: package,
            version: version,
            given: signingEntity,
            existing: existing
        )))
    }
}

extension SigningEntity {
    var name: String? {
        switch self {
        case .recognized(_, let name, _, _):
            return name
        case .unrecognized(let name, _, _):
            return name
        }
    }
}
