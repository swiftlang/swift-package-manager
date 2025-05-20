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
    let version: SwiftToolchainVersion

    init() throws {
        self.versionFilePath = self.toolchain.swiftCompilerPath.parentDirectory.parentDirectory.appending(
            RelativePath("lib/swift/version.json")
        )

        self.mockFileSystem = InMemoryFileSystem(
           files: [self.versionFilePath.pathString: ByteString(encodingAsUTF8: """
           {
               "tag": "swift-6.1-RELEASE",
               "branch": "swift-6.1-release",
               "architecture": "aarch64",
               "platform": "ubuntu2004"
           }
           """)]
        )

        self.version = try SwiftToolchainVersion(
            toolchain: self.toolchain,
            fileSystem: self.mockFileSystem
        )
    }

    @Test
    func versionDecoding() throws {
        #expect(self.version == SwiftToolchainVersion(
            tag: "swift-6.1-RELEASE",
            branch: "swift-6.1-release",
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
    func idForSwiftSDKGeneration() throws {
        #expect(throws: SwiftToolchainVersion.Error.unknownSwiftSDKAlias("foo")) {
            try self.version.idForSwiftSDK(aliasString: "foo")
        }

        var id = try self.version.idForSwiftSDK(aliasString: "wasi")
        #expect(id == "6.1-RELEASE-wasm32-wasi")

        id = try self.version.idForSwiftSDK(aliasString: "embedded-wasi")
        #expect(id == "6.1-RELEASE-wasm32-embedded-wasi")

        id = try self.version.idForSwiftSDK(aliasString: "static-linux")
        #expect(id == "swift-6.1-RELEASE_static-linux-0.0.1")
    }

    @Test
    func urlForSwiftSDKGeneration() throws {
        #expect(throws: SwiftToolchainVersion.Error.unknownSwiftSDKAlias("foo")) {
            try self.version.urlForSwiftSDK(aliasString: "foo")
        }

        var url = try self.version.urlForSwiftSDK(aliasString: "wasi")
        #expect(url == """
            https://download.swift.org/swift-6.1-release/wasi/swift-6.1-RELEASE/swift-6.1-RELEASE_wasi-0.0.1.artifactbundle.tar.gz
            """
        )

        url = try self.version.urlForSwiftSDK(aliasString: "embedded-wasi")
        #expect(url == """
            https://download.swift.org/swift-6.1-release/wasi/swift-6.1-RELEASE/swift-6.1-RELEASE_wasi-0.0.1.artifactbundle.tar.gz
            """
        )

        url = try version.urlForSwiftSDK(aliasString: "static-linux")
        #expect(url == """
            https://download.swift.org/swift-6.1-release/static-sdk/swift-6.1-RELEASE/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz
            """
        )
    }
}
