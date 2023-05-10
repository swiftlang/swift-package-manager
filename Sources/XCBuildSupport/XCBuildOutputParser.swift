//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import class TSCUtility.JSONMessageStreamingParser
import protocol TSCUtility.JSONMessageStreamingParserDelegate

/// Protocol for the parser delegate to get notified of parsing events.
public protocol XCBuildOutputParserDelegate: AnyObject {

    /// Called for each message parsed.
    func xcBuildOutputParser(_ parser: XCBuildOutputParser, didParse message: XCBuildMessage)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func xcBuildOutputParser(_ parser: XCBuildOutputParser, didFailWith error: Error)
}

/// Parser for XCBuild output.
public final class XCBuildOutputParser {

    /// The underlying JSON message parser.
    private var jsonParser: JSONMessageStreamingParser<XCBuildOutputParser>!

    /// Whether the parser is in a failing state.
    private var hasFailed: Bool

    /// Delegate to notify of parsing events.
    public weak var delegate: XCBuildOutputParserDelegate? = nil

    /// Initializes the parser with a delegate to notify of parsing events.
    /// - Parameters:
    ///     - delegate: Delegate to notify of parsing events.
    public init(delegate: XCBuildOutputParserDelegate) {
        self.hasFailed = false
        self.delegate = delegate
        self.jsonParser = JSONMessageStreamingParser<XCBuildOutputParser>(delegate: self)
    }

    /// Parse the next bytes of the Swift compiler JSON output.
    /// - Note: If a parsing error is encountered, the delegate will be notified and the parser won't accept any further
    ///   input.
    public func parse<C>(bytes: C) where C: Collection, C.Element == UInt8 {
        guard !hasFailed else {
            return
        }

        jsonParser.parse(bytes: bytes)
    }
}

extension XCBuildOutputParser: JSONMessageStreamingParserDelegate {
    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didParse message: XCBuildMessage
    ) {
        guard !hasFailed else {
            return
        }

        delegate?.xcBuildOutputParser(self, didParse: message)
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didParseRawText text: String
    ) {
        // Don't do anything with raw text.
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didFailWith error: Error
    ) {
        delegate?.xcBuildOutputParser(self, didFailWith: error)
    }
}
