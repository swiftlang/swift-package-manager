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

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import X509
@_implementationOnly import SwiftASN1
#else
import X509
import SwiftASN1
#endif

enum Certificates {
    static let appleRootsRaw = [
        PackageResources.AppleComputerRootCertificate_cer,
        PackageResources.AppleIncRootCertificate_cer,
        PackageResources.AppleRootCA_G2_cer,
        PackageResources.AppleRootCA_G3_cer,
    ]

    static let appleRoots = Self.appleRootsRaw.compactMap {
        try? Certificate(derEncoded: $0)
    }

    static let wwdrIntermediatesRaw = [
        PackageResources.AppleWWDRCAG2_cer,
        PackageResources.AppleWWDRCAG3_cer,
        PackageResources.AppleWWDRCAG4_cer,
        PackageResources.AppleWWDRCAG5_cer,
        PackageResources.AppleWWDRCAG6_cer,
        PackageResources.AppleWWDRCAG7_cer,
        PackageResources.AppleWWDRCAG8_cer,
    ]

    static let wwdrIntermediates = Self.wwdrIntermediatesRaw.compactMap {
        try? Certificate(derEncoded: $0)
    }
}

enum CertificateStores {
    static let defaultTrustRoots = Certificates.appleRoots
}
