/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

protocol CertificatePolicy {
    /// Validates the given certificate chain.
    ///
    /// - Parameters:
    ///   - certChainPaths: Paths to each certificate in the chain. The certificate being verified must be the first element of the array,
    ///                     with its issuer the next element and so on, and the root CA certificate is last.
    ///   - callback: The callback to invoke when the result is available.
    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void)
}

// TODO: actual cert policies to be implemented later
struct NoopCertificatePolicy: CertificatePolicy {
    func validate(certChain: [Certificate], callback: @escaping (Result<Void, Error>) -> Void) {
        callback(.success(()))
    }
}
