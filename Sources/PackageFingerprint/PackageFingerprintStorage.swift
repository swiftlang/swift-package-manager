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
import Dispatch
import PackageModel

public protocol PackageFingerprintStorage {
    func get(package: PackageIdentity,
             version: Version,
             observabilityScope: ObservabilityScope,
             callbackQueue: DispatchQueue,
             callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void)

    func put(package: PackageIdentity,
             version: Version,
             fingerprint: Fingerprint,
             observabilityScope: ObservabilityScope,
             callbackQueue: DispatchQueue,
             callback: @escaping (Result<Void, Error>) -> Void)
}

public extension PackageFingerprintStorage {
    func get(package: PackageIdentity,
             version: Version,
             kind: Fingerprint.Kind,
             observabilityScope: ObservabilityScope,
             callbackQueue: DispatchQueue,
             callback: @escaping (Result<Fingerprint, Error>) -> Void) {
        self.get(package: package, version: version, observabilityScope: observabilityScope, callbackQueue: callbackQueue) { result in
            callback(result.tryMap { fingerprints in
                guard let fingerprint = fingerprints[kind] else {
                    throw PackageFingerprintStorageError.notFound
                }
                return fingerprint
            })
        }
    }
}

public enum PackageFingerprintStorageError: Error, Equatable, CustomStringConvertible {
    case conflict(given: Fingerprint, existing: Fingerprint)
    case notFound
    
    public var description: String {
        switch self {
        case .conflict(let given, let existing):
            return "Fingerprint \(given) is different from previously recorded value \(existing)"
        case .notFound:
            return "Not found"
        }
    }
}
