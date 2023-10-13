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

import Foundation

public struct SourceControlURL: Codable, Equatable, Hashable, Sendable {
    private let underlying: URL?
    private let urlString: String

    public init(stringLiteral: String) {
        self.underlying = URL(string: stringLiteral)
        self.urlString = stringLiteral
    }

    public init(_ urlString: String) {
        self.underlying = URL(string: urlString)
        self.urlString = urlString
    }

    public init(_ url: URL) {
        self.underlying = url
        self.urlString = url.absoluteString
    }

    public var absoluteString: String {
        return self.urlString
    }

    public var lastPathComponent: String {
        return (self.urlString as NSString).lastPathComponent
    }

    public var url: URL? {
        return self.underlying
    }

    public var scheme: String? {
        return self.underlying?.scheme
    }
}

extension SourceControlURL: CustomStringConvertible {
    public var description: String {
        return self.urlString
    }
}

extension SourceControlURL: ExpressibleByStringInterpolation {
}

extension SourceControlURL: ExpressibleByStringLiteral {
}
