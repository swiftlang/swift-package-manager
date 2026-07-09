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

import Foundation

/// JSON coders configured for the registry wire format defined by the Swift
/// Package Registry Service Specification: `Date`s are ISO 8601 timestamps and
/// URLs are emitted without escaped slashes.
///
/// ``PackageRelease`` and the response bodies that embed it carry this
/// contract, so every site that encodes or decodes them must agree on the
/// same strategy. Routing through these shared coders keeps that agreement in
/// one place instead of re-stating it at each call site.
extension JSONEncoder {
    static var registry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var registry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
