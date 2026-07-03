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
import MultipartKit
import NIOCore
import Vapor

/// A single part of a parsed `multipart/form-data` publish request body.
///
/// Used as an intermediate representation for the four parts described in
/// §4.6 *Create a package release*:
///
/// | `name`                     | `contentType`              | Requirement |
/// | -------------------------- | -------------------------- | ----------- |
/// | `source-archive`           | `application/zip`          | REQUIRED    |
/// | `source-archive-signature` | `application/octet-stream` | OPTIONAL    |
/// | `metadata`                 | `application/json`         | OPTIONAL    |
/// | `metadata-signature`       | `application/octet-stream` | OPTIONAL    |
struct ParsedMultipartPart: Sendable {
    /// The `name` parameter from the part's `Content-Disposition` header
    /// (for example, `"source-archive"`).
    var name: String
    /// The value of the part's `Content-Type` header, if any.
    var contentType: String?
    /// The `filename` parameter from the part's `Content-Disposition`
    /// header, if any.
    var filename: String?
    /// The raw bytes of the part's body.
    var data: Data
}

/// Errors that can be thrown while parsing a publish multipart body.
enum MultipartParseError: Error, Sendable {
    /// The request's `Content-Type` header did not include a
    /// `boundary=...` parameter, so the body cannot be framed.
    case missingBoundary
    /// The multipart body was malformed and could not be decoded.
    case decodeFailed
}

/// Parses `multipart/form-data` request bodies for the publish endpoint
/// (§4.6 *Create a package release*).
///
/// The parser extracts the boundary from the request's `Content-Type`
/// header, drives MultipartKit's streaming `MultipartParser` over the
/// request body, and materializes each part as a ``ParsedMultipartPart``.
/// Higher layers (``PublishRoutes``) are responsible for interpreting the
/// parts (for example, verifying that a `source-archive` part is present
/// and translating failures into ``ProblemDetails`` responses).
enum PublishMultipartParser {
    /// Parses a publish request body into its constituent multipart parts.
    ///
    /// - Parameters:
    ///   - body: The raw request body bytes.
    ///   - contentType: The request's `Content-Type` header, which MUST
    ///     carry a `boundary=...` parameter per §4.6.
    /// - Returns: The parts in the order they appeared in the body. Parts
    ///   whose `Content-Disposition` header did not yield a `name` are
    ///   silently dropped.
    /// - Throws:
    ///   - ``MultipartParseError/missingBoundary`` if `contentType` does
    ///     not include a `boundary=...` parameter.
    ///   - ``MultipartParseError/decodeFailed`` if the body is malformed.
    static func parse(body: ByteBuffer, contentType: String) throws -> [ParsedMultipartPart] {
        guard let boundary = extractBoundary(from: contentType) else {
            throw MultipartParseError.missingBoundary
        }

        let collector = Collector()
        let parser = MultipartParser(boundary: boundary)
        parser.onHeader = collector.onHeader
        parser.onBody = collector.onBody
        parser.onPartComplete = collector.onPartComplete
        do {
            try parser.execute(body)
        } catch {
            throw MultipartParseError.decodeFailed
        }
        return collector.parts
    }

    private static func extractBoundary(from contentType: String) -> String? {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: contentType)
        return headers.contentType?.parameters["boundary"]
    }

    private final class Collector {
        var parts: [ParsedMultipartPart] = []
        private var headers = HTTPHeaders()
        private var body = Data()

        lazy var onHeader: (String, String) -> Void = { [weak self] name, value in
            self?.headers.add(name: name, value: value)
        }

        lazy var onBody: (inout ByteBuffer) -> Void = { [weak self] buffer in
            guard let self else { return }
            let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
            self.body.append(contentsOf: bytes)
        }

        lazy var onPartComplete: () -> Void = { [weak self] in
            guard let self else { return }
            guard let disposition = self.headers.contentDisposition, let name = disposition.name else {
                self.reset()
                return
            }
            self.parts.append(ParsedMultipartPart(
                name: name,
                contentType: self.headers.first(name: .contentType),
                filename: disposition.filename,
                data: self.body
            ))
            self.reset()
        }

        private func reset() {
            headers = HTTPHeaders()
            body = Data()
        }
    }
}
