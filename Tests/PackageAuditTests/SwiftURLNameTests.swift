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

@testable import PackageAudit
import Testing

@Suite
struct SwiftURLNameTests {
    @Test
    func variantsNormalizeIdentically() {
        let variants = [
            "https://github.com/apple/swift-nio.git",
            "https://GitHub.com/apple/swift-nio/",
            "git@github.com:apple/swift-nio.git",
            "ssh://git@github.com/apple/swift-nio.git",
            "https://user:token@github.com/apple/swift-nio",
        ]
        for variant in variants {
            #expect(SwiftURLName.normalize(variant) == "github.com/apple/swift-nio", "\(variant)")
        }
    }

    @Test
    func pathCaseIsPreserved() {
        #expect(SwiftURLName.normalize("https://github.com/Apple/Swift-NIO.git") == "github.com/Apple/Swift-NIO")
    }

    @Test
    func localPaths() {
        #expect(SwiftURLName.normalize("/local/path") == nil)
        #expect(SwiftURLName.normalize("file:///tmp/Dep") == "tmp/Dep")
    }

    @Test
    func repositoryName() {
        #expect(SwiftURLName.repositoryName(of: "github.com/apple/swift-nio-http2") == "swift-nio-http2")
        #expect(SwiftURLName.repositoryName(of: "swift-nio-http2") == nil)
    }

    @Test
    func urlWithinRepository() {
        let name = "github.com/apple/swift-nio-http2"
        #expect(SwiftURLName.url("https://github.com/apple/swift-nio-http2", isWithinRepository: name))
        #expect(SwiftURLName.url("https://github.com/Apple/swift-nio-http2.git", isWithinRepository: name))
        #expect(SwiftURLName.url(
            "https://github.com/apple/swift-nio-http2/security/advisories/GHSA-q3g2-m552-3r9c",
            isWithinRepository: name
        ))
        #expect(!SwiftURLName.url("https://github.com/apple/swift-nio-http2-extras", isWithinRepository: name))
        #expect(!SwiftURLName.url("https://github.com/someone/swift-nio-http2", isWithinRepository: name))
        #expect(!SwiftURLName.url("https://nvd.nist.gov/vuln/detail/CVE-2026-64785", isWithinRepository: name))
    }
}
