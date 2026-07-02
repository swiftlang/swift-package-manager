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
@testable import RegistryExample

@Suite("End-to-end publish + retrieval")
struct EndToEndPublishTests {
    @Test func `publish then retrieve all endpoints through the Vapor app`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()

            let zip = try makeZip(entries: [
                "HelloWorld-1.0.0/Package.swift": "// swift-tools-version:5.9\nlet package = Package(name: \"HelloWorld\")",
                "HelloWorld-1.0.0/Package@swift-5.10.swift": "// swift-tools-version:5.10\nlet package = Package(name: \"HelloWorld\")",
                "HelloWorld-1.0.0/Sources/HelloWorld/HelloWorld.swift": "public enum HelloWorld {}",
            ])
            let body = publishMultipartBody(
                zip: zip,
                metadata: #"{"repositoryURLs":["https://github.com/exampleregistry/HelloWorld"]}"#
            )
            try await tester.test(.PUT, "/exampleregistry/HelloWorld/1.0.0", headers: publishHeaders(), body: body) { res async in
                #expect(res.status == .created)
            }

            try await tester.test(.GET, "/exampleregistry/HelloWorld", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"1.0.0\""))
            }

            try await tester.test(.GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"id\":\"exampleregistry.HelloWorld\""))
            }

            try await tester.test(.GET, "/exampleregistry/HelloWorld/1.0.0/Package.swift", headers: acceptSwift) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("swift-tools-version:5.9"))
            }

            try await tester.test(.GET, "/exampleregistry/HelloWorld/1.0.0/Package.swift?swift-version=5.10", headers: acceptSwift) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("swift-tools-version:5.10"))
            }

            try await tester.test(.GET, "/exampleregistry/HelloWorld/1.0.0.zip", headers: acceptZip) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: .contentType) == "application/zip")
            }

            try await tester.test(
                .GET,
                "/identifiers?url=https://github.com/exampleregistry/HelloWorld",
                headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("exampleregistry.HelloWorld"))
            }
        }
    }
}