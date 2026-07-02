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
import NIOHTTP1
import Vapor

enum MultipartBuilder {
    static let boundary = "test-boundary-0xABCDEF"

    static func body(parts: [Part]) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        for part in parts {
            buffer.writeString("--\(boundary)\r\n")
            buffer.writeString("Content-Disposition: form-data; name=\"\(part.name)\"")
            if let filename = part.filename {
                buffer.writeString("; filename=\"\(filename)\"")
            }
            buffer.writeString("\r\n")
            if let contentType = part.contentType {
                buffer.writeString("Content-Type: \(contentType)\r\n")
            }
            buffer.writeString("\r\n")
            buffer.writeBytes(part.data)
            buffer.writeString("\r\n")
        }
        buffer.writeString("--\(boundary)--\r\n")
        return buffer
    }

    static var contentTypeHeader: String {
        "multipart/form-data; boundary=\"\(boundary)\""
    }

    struct Part {
        var name: String
        var data: Data
        var contentType: String?
        var filename: String?
    }
}