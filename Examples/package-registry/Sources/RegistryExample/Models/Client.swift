//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct Client: Sendable, Equatable {
    /// User the client belongs to
    public let user: User
    /// The root CA + ID string that uniquely identifies the client
    public let id: ID

    /// A client makes authenticated requests on behalf of the user
    ///
    /// - Parameters:
    ///   - user: User the client belongs to
    ///   - id: The root CA + ID string that uniquely identifies the client
    public init(user: User, id: ID) {
        self.user = user
        self.id = id
    }

    public struct ID: Hashable, Sendable {
        /// An enum of the accepted root CAs for this registry
        public let rootCertificateAuthority: RootCertificateAuthority
        /// The ID of the client in the context of the root CA
        public let value: String

        ///
        /// - Parameters:
        ///   - rootCertificateAuthority: An enum of the accepted root CAs for this registry
        ///   - value: The ID of the client in the context of the root CA
        public init(rootCertificateAuthority: RootCertificateAuthority, value: String) {
            self.rootCertificateAuthority = rootCertificateAuthority
            self.value = value
        }
    }
}