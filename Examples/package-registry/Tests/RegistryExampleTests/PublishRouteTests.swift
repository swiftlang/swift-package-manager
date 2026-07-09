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
import Vapor
import VaporTesting
import ZIPFoundation
@testable import RegistryExample

@Suite("Publish endpoint")
struct PublishRouteTests {
    @Test func `happy path: stores release, returns 201 + Location`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body = publishMultipartBody(zip: zip, metadata: #"{"repositoryURLs":["https://github.com/exampleregistry/HelloWorld"]}"#)
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: body
            ) { res async in
                #expect(res.status == .created)
                #expect(res.headers.first(name: .location)?.hasSuffix("/exampleregistry/HelloWorld/1.0.0") == true)
                #expect(res.headers.first(name: "Content-Version") == "1")
            }
        }
    }

    // MARK: route-level parameter validation

    @Test func `malformed scope returns 400`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body = publishMultipartBody(zip: zip, metadata: nil)
            try await app.testing().test(
                .PUT, "/bad..scope/HelloWorld/1.0.0", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid package scope"))
            }
        }
    }

    @Test func `malformed name returns 400`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body = publishMultipartBody(zip: zip, metadata: nil)
            try await app.testing().test(
                .PUT, "/exampleregistry/bad..name/1.0.0", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid package name"))
            }
        }
    }

    @Test func `malformed version returns 400`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body = publishMultipartBody(zip: zip, metadata: nil)
            try await app.testing().test(
                .PUT, "/exampleregistry/HelloWorld/not-a-version", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func `empty request body returns 422`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: ByteBuffer()
            ) { res async in
                #expect(res.status == .unprocessableEntity)
                #expect(res.body.string.contains("request body missing"))
            }
        }
    }

    // MARK: PublishError → ProblemDetails mapping

    @Test func `duplicate publish returns 409 problem+json`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body = publishMultipartBody(zip: zip, metadata: nil)
            try await app.testing().test(
                .PUT, "/exampleregistry/HelloWorld/1.0.0", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .created)
            }
            try await app.testing().test(
                .PUT, "/exampleregistry/HelloWorld/1.0.0", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .conflict)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `missing source-archive part returns 422 problem+json`() async throws {
        try await withRegistryApp { app in
            let body = MultipartBuilder.body(parts: [
                .init(name: "metadata", data: Data("{}".utf8), contentType: "application/json")
            ])
            try await app.testing().test(
                .PUT, "/exampleregistry/HelloWorld/1.0.0", headers: publishHeaders(), body: body
            ) { res async in
                #expect(res.status == .unprocessableEntity)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `concurrent publishes: one wins, the other 409s`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let body1 = publishMultipartBody(zip: zip, metadata: nil)
            let body2 = publishMultipartBody(zip: zip, metadata: nil)
            async let first = publishStatus(app, body: body1)
            async let second = publishStatus(app, body: body2)
            let statuses: Set<HTTPResponseStatus> = [try await first, try await second]
            #expect(statuses.contains(.created))
            #expect(statuses.contains(.conflict))
        }
    }
}

func publishStatus(_ app: Application, body: ByteBuffer) async throws -> HTTPResponseStatus {
    try await withCheckedThrowingContinuation { continuation in
        Task {
            do {
                try await app.testing().test(
                    .PUT, "/exampleregistry/HelloWorld/1.0.0", headers: publishHeaders(), body: body
                ) { res async in
                    continuation.resume(returning: res.status)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

func publishHeaders(signatureFormat: String? = nil) -> HTTPHeaders {
    var h = HTTPHeaders()
    h.replaceOrAdd(name: .contentType, value: MultipartBuilder.contentTypeHeader)
    h.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+json")
    if let signatureFormat {
        h.replaceOrAdd(name: "X-Swift-Package-Signature-Format", value: signatureFormat)
    }
    return h
}

func publishMultipartBody(zip: Data, metadata: String?) -> ByteBuffer {
    var parts: [MultipartBuilder.Part] = [
        .init(
            name: "source-archive",
            data: zip,
            contentType: "application/zip",
            filename: "source.zip"
        )
    ]
    if let metadata {
        parts.append(.init(
            name: "metadata",
            data: Data(metadata.utf8),
            contentType: "application/json"
        ))
    }
    return MultipartBuilder.body(parts: parts)
}

func signedPublishBody(
    zip: Data,
    metadata: String?,
    archiveSignature: Data?,
    metadataSignature: Data?
) -> ByteBuffer {
    var parts: [MultipartBuilder.Part] = [
        .init(
            name: "source-archive",
            data: zip,
            contentType: "application/zip",
            filename: "source.zip"
        )
    ]
    if let archiveSignature {
        parts.append(.init(
            name: "source-archive-signature",
            data: archiveSignature,
            contentType: "application/octet-stream"
        ))
    }
    if let metadata {
        parts.append(.init(
            name: "metadata",
            data: Data(metadata.utf8),
            contentType: "application/json"
        ))
    }
    if let metadataSignature {
        parts.append(.init(
            name: "metadata-signature",
            data: metadataSignature,
            contentType: "application/octet-stream"
        ))
    }
    return MultipartBuilder.body(parts: parts)
}

func makeHelloWorldZip() throws -> Data {
    try makeZip(entries: [
        "HelloWorld-1.0.0/Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"HelloWorld\")",
        "HelloWorld-1.0.0/Sources/HelloWorld/HelloWorld.swift": "public enum HelloWorld {}",
    ])
}