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

import Dispatch
import Foundation

import Basics

public struct Signer {
    public init() {
    }

    public func sign(
        _ content: Data,
        with identity: SigningIdentity,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        fatalError("TO BE IMPLEMENTED")
    }
    
    public func isValidSignature(
        _ signature: Data,
        for content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        fatalError("TO BE IMPLEMENTED")
    }
}

public enum SignatureFormat: String {
    case cms_1_0_0 = "cms-1.0.0"
}

public struct PrivateKey {
}

public struct Certificate {
}

public struct SigningIdentity {
    public let key: PrivateKey
    public let certificate: Certificate
    
    public init(key: PrivateKey, certificate: Certificate) {
        self.key = key
        self.certificate = certificate
    }
}

public struct Signature {
    public let data: Data
    public let format: SignatureFormat
    public let certificate: Certificate
    
    public var signedBy: SigningEntity {
        SigningEntity(certificate: self.certificate)
    }

    public init(data: Data, format: SignatureFormat) {
        // TODO: decode `data` by `format`, then construct `signedBy` from signing cert
        fatalError("TO BE IMPLEMENTED")
    }
    
    public struct SigningEntity {
        // TODO: properties (e.g., name?, id?, type?)
        
        init(certificate: Certificate) {
        }
    }
}
