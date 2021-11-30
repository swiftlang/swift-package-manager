/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import PackageModel
import TSCUtility

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

public enum PackageFingerprintStorageError: Error, Equatable {
    case conflict(given: Fingerprint, existing: Fingerprint)
    case notFound
}
