//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Testing

import Foundation
import Basics
import struct TSCBasic.ByteString
import PackageModel

@Suite
struct SwiftToolchainVersionTests {
    let toolchain = MockToolchain()
    let versionFilePath: AbsolutePath
    let mockFileSystem: InMemoryFileSystem

    init() {
        self.versionFilePath = toolchain.swiftCompilerPath.parentDirectory.parentDirectory.appending(
            RelativePath("lib/swift/version.json")
        )

        self.mockFileSystem = InMemoryFileSystem(
           files: [self.versionFilePath.pathString: ByteString(encodingAsUTF8: """
           {
               "tag": "swift-6.1-RELEASE",
               "branch": "swift-6.1-branch",
               "architecture": "aarch64",
               "platform": "ubuntu2004"
           }
           """)]
       )
    }

    @Test
    func versionDecoding() throws {
        let version = try SwiftToolchainVersion(toolchain: self.toolchain, fileSystem: self.mockFileSystem)

        #expect(version == SwiftToolchainVersion(
            tag: "swift-6.1-RELEASE",
            branch: "swift-6.1-branch",
            architecture: .aarch64,
            platform: .ubuntu2004
        ))
    }

    @Test
    func versionMetadataMissing() {
        #expect(throws: SwiftToolchainVersion.Error.versionMetadataNotFound(self.versionFilePath)) {
            try SwiftToolchainVersion(toolchain: self.toolchain, fileSystem: InMemoryFileSystem())
        }
    }

    @Test
    func urlGeneration() throws {
        let version = try SwiftToolchainVersion(toolchain: self.toolchain, fileSystem: self.mockFileSystem)

        #expect(throws: SwiftToolchainVersion.Error.unknownSwiftSDKAlias("foo")) {
            try version.generateURL(aliasString: "foo")
        }

        #expect(try version.generateURL(aliasString: "wasi") == """
            https://download.swift.org/swift-6.1-release/swift-6.1-RELEASE/swift-6.1-RELEASE_wasi-0.0.1.artifactbundle.tar.gz
            """
        )

        #expect(try version.generateURL(aliasString: "wasi-embedded") == """
            https://download.swift.org/swift-6.1-release/swift-6.1-RELEASE/swift-6.1-RELEASE_wasi-0.0.1.artifactbundle.tar.gz
            """
        )
        
        #expect(try version.generateURL(aliasString: "static-linux") == """
            https://download.swift.org/swift-6.1-release/static-sdk/swift-6.1-RELEASE/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz
            https://download.swift.org/swift-6.1-branch/swift-6.1-RELEASE/swift-6.1-RELEASE_wasi-0.0.1.artifactbundle.tar.gz
            """
        )
    }
}
