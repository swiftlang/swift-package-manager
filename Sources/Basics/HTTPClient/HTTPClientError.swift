//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case badResponseStatusCode(Int)
    case circuitBreakerTriggered
    case responseTooLarge(Int64)
    case downloadError(String)
}
