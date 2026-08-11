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

import Testing
import Foundation
import NIOCore
@testable import RegistryExample

@Suite("PublishMultipartParser")
struct PublishMultipartParserTests {
    @Test func `missing boundary parameter throws missingBoundary`() {
        let body = ByteBufferAllocator().buffer(string: "irrelevant")
        #expect(throws: MultipartParseError.missingBoundary) {
            _ = try PublishMultipartParser.parse(body: body, contentType: "multipart/form-data")
        }
    }

    @Test func `body with malformed headers after boundary throws decodeFailed`() {
        let boundary = "real-boundary"
        var buffer = ByteBufferAllocator().buffer(capacity: 128)
        buffer.writeString("--\(boundary)\r\n")
        buffer.writeString("not a valid header line without colon\r\n")
        buffer.writeString("\r\n")
        buffer.writeString("payload\r\n")
        buffer.writeString("--\(boundary)--\r\n")
        #expect(throws: MultipartParseError.decodeFailed) {
            _ = try PublishMultipartParser.parse(
                body: buffer,
                contentType: "multipart/form-data; boundary=\"\(boundary)\""
            )
        }
    }

    @Test func `part without a name is silently dropped`() throws {
        let boundary = "test-boundary-nameless"
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        buffer.writeString("--\(boundary)\r\n")
        buffer.writeString("Content-Disposition: form-data\r\n")
        buffer.writeString("\r\n")
        buffer.writeString("payload")
        buffer.writeString("\r\n")
        buffer.writeString("--\(boundary)--\r\n")

        let parts = try PublishMultipartParser.parse(
            body: buffer,
            contentType: "multipart/form-data; boundary=\"\(boundary)\""
        )
        #expect(parts.isEmpty)
    }

    @Test func `quoted boundary and mixed-case Content-Disposition are accepted`() throws {
        let boundary = "quoted-boundary"
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        buffer.writeString("--\(boundary)\r\n")
        buffer.writeString("CONTENT-DISPOSITION: form-data; name=\"metadata\"; filename=\"m.json\"\r\n")
        buffer.writeString("Content-Type: application/json\r\n")
        buffer.writeString("\r\n")
        buffer.writeString("{}")
        buffer.writeString("\r\n")
        buffer.writeString("--\(boundary)--\r\n")

        let parts = try PublishMultipartParser.parse(
            body: buffer,
            contentType: "multipart/form-data; boundary=\"\(boundary)\""
        )
        #expect(parts.count == 1)
        #expect(parts[0].name == "metadata")
        #expect(parts[0].filename == "m.json")
        #expect(parts[0].contentType == "application/json")
        #expect(String(decoding: parts[0].data, as: UTF8.self) == "{}")
    }
}