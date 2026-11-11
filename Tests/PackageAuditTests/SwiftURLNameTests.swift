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
}
