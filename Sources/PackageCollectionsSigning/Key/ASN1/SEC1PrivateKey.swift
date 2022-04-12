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

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCrypto open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftCrypto project authors
// Licensed under Apache License v2.0
//
// See http://swift.org/LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of SwiftCrypto project authors
//
//===----------------------------------------------------------------------===//

import Foundation

// Source: https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/ASN1/SEC1PrivateKey.swift

extension ASN1 {
    // For private keys, SEC 1 uses:
    //
    // ECPrivateKey ::= SEQUENCE {
    //   version INTEGER { ecPrivkeyVer1(1) } (ecPrivkeyVer1),
    //   privateKey OCTET STRING,
    //   parameters [0] EXPLICIT ECDomainParameters OPTIONAL,
    //   publicKey [1] EXPLICIT BIT STRING OPTIONAL
    // }
    struct SEC1PrivateKey: ASN1Parseable {
        var algorithm: ASN1.RFC5480AlgorithmIdentifier?

        var privateKey: ASN1.ASN1OctetString

        var publicKey: ASN1.ASN1BitString?

        init(asn1Encoded rootNode: ASN1.ASN1Node) throws {
            self = try ASN1.sequence(rootNode) { nodes in
                let version = try Int(asn1Encoded: &nodes)
                guard version == 1 else {
                    throw ASN1Error.invalidASN1Object
                }

                let privateKey = try ASN1OctetString(asn1Encoded: &nodes)
                let parameters = try ASN1.optionalExplicitlyTagged(&nodes, tagNumber: 0, tagClass: .contextSpecific) { node in
                    try ASN1.ASN1ObjectIdentifier(asn1Encoded: node)
                }
                let publicKey = try ASN1.optionalExplicitlyTagged(&nodes, tagNumber: 1, tagClass: .contextSpecific) { node in
                    try ASN1.ASN1BitString(asn1Encoded: node)
                }

                return try .init(privateKey: privateKey, algorithm: parameters, publicKey: publicKey)
            }
        }

        private init(privateKey: ASN1.ASN1OctetString, algorithm: ASN1.ASN1ObjectIdentifier?, publicKey: ASN1.ASN1BitString?) throws {
            self.privateKey = privateKey
            self.publicKey = publicKey
            self.algorithm = try algorithm.map { algorithmOID in
                switch algorithmOID {
                case ASN1ObjectIdentifier.NamedCurves.secp256r1:
                    return .ecdsaP256
                case ASN1ObjectIdentifier.NamedCurves.secp384r1:
                    return .ecdsaP384
                case ASN1ObjectIdentifier.NamedCurves.secp521r1:
                    return .ecdsaP521
                default:
                    throw ASN1Error.invalidASN1Object
                }
            }
        }
    }
}
