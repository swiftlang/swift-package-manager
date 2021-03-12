/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCrypto open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftCrypto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of SwiftCrypto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

// Source: https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/ASN1/SubjectPublicKeyInfo.swift

extension ASN1 {
    struct SubjectPublicKeyInfo: ASN1Parseable {
        var algorithmIdentifier: RFC5480AlgorithmIdentifier

        var key: ASN1.ASN1BitString

        init(asn1Encoded rootNode: ASN1.ASN1Node) throws {
            // The SPKI block looks like this:
            //
            // SubjectPublicKeyInfo  ::=  SEQUENCE  {
            //   algorithm         AlgorithmIdentifier,
            //   subjectPublicKey  BIT STRING
            // }
            self = try ASN1.sequence(rootNode) { nodes in
                let algorithmIdentifier = try ASN1.RFC5480AlgorithmIdentifier(asn1Encoded: &nodes)
                let key = try ASN1.ASN1BitString(asn1Encoded: &nodes)

                return SubjectPublicKeyInfo(algorithmIdentifier: algorithmIdentifier, key: key)
            }
        }

        private init(algorithmIdentifier: RFC5480AlgorithmIdentifier, key: ASN1.ASN1BitString) {
            self.algorithmIdentifier = algorithmIdentifier
            self.key = key
        }
    }

    enum RFC5480AlgorithmIdentifier: ASN1Parseable {
        case ecdsaP256
        case ecdsaP384
        case ecdsaP521

        init(asn1Encoded rootNode: ASN1.ASN1Node) throws {
            // The AlgorithmIdentifier block looks like this.
            //
            // AlgorithmIdentifier  ::=  SEQUENCE  {
            //   algorithm   OBJECT IDENTIFIER,
            //   parameters  ANY DEFINED BY algorithm OPTIONAL
            // }
            //
            // ECParameters ::= CHOICE {
            //   namedCurve         OBJECT IDENTIFIER
            //   -- implicitCurve   NULL
            //   -- specifiedCurve  SpecifiedECDomain
            // }
            //
            // We don't bother with helpers: we just try to decode it directly.
            self = try ASN1.sequence(rootNode) { nodes in
                let algorithmOID = try ASN1.ASN1ObjectIdentifier(asn1Encoded: &nodes)

                guard algorithmOID == ASN1ObjectIdentifier.AlgorithmIdentifier.idEcPublicKey else {
                    throw ASN1Error.invalidASN1Object
                }

                let curveNameOID = try ASN1.ASN1ObjectIdentifier(asn1Encoded: &nodes)

                switch curveNameOID {
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
