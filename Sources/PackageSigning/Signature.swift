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

import struct Foundation.Data

public struct Signature {
    public let data: Data
    public let format: SignatureFormat
    public let certificate: Certificate

    public init(data: Data, format: SignatureFormat) {
        // TODO: decode `data` by `format`, then construct `signedBy` from signing cert
        fatalError("TO BE IMPLEMENTED")
    }
}

public enum SignatureFormat: String {
    case cms_1_0_0 = "cms-1.0.0"
}

// MARK: - SigningEntity is the entity that generated the signature

extension Signature {
    public var signedBy: SigningEntity {
        SigningEntity(certificate: self.certificate)
    }
}

public struct SigningEntity {
    public let type: SigningEntityType?
    public let id: String?
    public let name: String?
    public let organization: String?

    public var isRecognized: Bool {
        self.type != nil
    }

    init(certificate: Certificate) {
        // TODO: extract id, name, organization, etc. from cert
        fatalError("TO BE IMPLEMENTED")
    }
}

public enum SigningEntityType {
    case adp // Apple Developer Program
}
