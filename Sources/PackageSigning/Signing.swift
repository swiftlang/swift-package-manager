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

import Basics

public struct SignatureProvider {
    public init() {}

    public func sign(
        _ content: Data,
        with identity: SigningIdentity,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        fatalError("TO BE IMPLEMENTED")
    }

    public func isValidSignature(
        _ signature: Data,
        for content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Bool {
        fatalError("TO BE IMPLEMENTED")
    }
}
