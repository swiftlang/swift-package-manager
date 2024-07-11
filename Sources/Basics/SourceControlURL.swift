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
    private let urlString: String

    public init(stringLiteral: String) {
        self.urlString = stringLiteral
    }

    public init(_ urlString: String) {
        self.urlString = urlString
    }

    public init(_ url: URL) {
        self.urlString = url.absoluteString
    }

    /// Initialize with string, returning nil if the URL is not https://domain or git@domain
    ///
    /// The following URL are valid
    /// e.g. https://github.com/apple/swift
    /// e.g. git@github.com:apple/swift
    public init?(absoluteString url: String) {
        guard let regex = try? NSRegularExpression(pattern: "^(?:https://|git@)", options: .caseInsensitive) else {
            return nil
        }

        if regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)) != nil {
            self.init(url)
        } else {
            return nil
        }
    }

    public var absoluteString: String {
        self.urlString
    }

    public var lastPathComponent: String {
        (self.urlString as NSString).lastPathComponent
    }

    public var url: URL? {
        URL(string: self.urlString)
    }
}

extension SourceControlURL: CustomStringConvertible {
    public var description: String {
        self.urlString
    }
}

extension SourceControlURL: ExpressibleByStringInterpolation {}

extension SourceControlURL: ExpressibleByStringLiteral {}
