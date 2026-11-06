//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

enum RegistryHTTPTransportError: Error, CustomStringConvertible, Equatable {
    case unsupportedURL(String)
    case unsupportedScheme(String)
    case timedOut(String)
    case connectionClosed
    case tooManyRedirects(String)

    var description: String {
        switch self {
        case .unsupportedURL(let url):
            return "'\(url)' is not a valid HTTP URL."
        case .unsupportedScheme(let url):
            return "'\(url)' cannot be requested over mutual TLS because it is not an 'https' URL."
        case .timedOut(let url):
            return "The request to '\(url)' timed out."
        case .connectionClosed:
            return "The connection closed before the response was complete."
        case .tooManyRedirects(let url):
            return "The request to '\(url)' was redirected too many times."
        }
    }
}
