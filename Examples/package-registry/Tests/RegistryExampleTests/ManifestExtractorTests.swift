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
import ZIPFoundation
@testable import RegistryExample

@Suite("ManifestExtractor")
struct ManifestExtractorTests {
    @Test func `extracts Package.swift at archive root`() throws {
        let data = try makeZip(entries: [
            "Package.swift": "// swift-tools-version:5.9"
        ])
        let manifests = try ManifestExtractor.extract(from: data)
        #expect(manifests[""] == "// swift-tools-version:5.9")
    }

    @Test func `extracts Package.swift nested under single top-level directory`() throws {
        let data = try makeZip(entries: [
            "HelloWorld-1.0.0/Package.swift": "// swift-tools-version:5.9",
            "HelloWorld-1.0.0/Sources/HelloWorld/HelloWorld.swift": "print()"
        ])
        let manifests = try ManifestExtractor.extract(from: data)
        #expect(manifests[""] == "// swift-tools-version:5.9")
    }

    @Test func `collects version-specific manifests alongside Package.swift`() throws {
        let data = try makeZip(entries: [
            "HelloWorld/Package.swift": "// swift-tools-version:5.9",
            "HelloWorld/Package@swift-5.10.swift": "// swift-tools-version:5.10",
            "HelloWorld/Package@swift-4.2.swift": "// swift-tools-version:4.2",
        ])
        let manifests = try ManifestExtractor.extract(from: data)
        #expect(manifests[""]?.contains("5.9") == true)
        #expect(manifests["5.10"]?.contains("5.10") == true)
        #expect(manifests["4.2"]?.contains("4.2") == true)
    }

    @Test func `throws for corrupt archives`() {
        let data = Data("not a zip".utf8)
        #expect(throws: ManifestExtractorError.invalidArchive) {
            _ = try ManifestExtractor.extract(from: data)
        }
    }

    @Test func `throws when Package.swift is missing`() throws {
        let data = try makeZip(entries: [
            "HelloWorld/README.md": "hello",
        ])
        #expect(throws: ManifestExtractorError.manifestMissing) {
            _ = try ManifestExtractor.extract(from: data)
        }
    }

    @Test func `throws when decompressed manifest exceeds maxManifestBytes`() throws {
        let oversized = String(repeating: "a", count: 1024)
        let data = try makeZip(entries: [
            "HelloWorld/Package.swift": oversized,
        ])
        #expect(throws: ManifestExtractorError.manifestTooLarge) {
            _ = try ManifestExtractor.extract(from: data, maxManifestBytes: 128)
        }
    }

    @Test func `accepts manifest whose decompressed size equals the cap`() throws {
        let atCap = String(repeating: "a", count: 128)
        let data = try makeZip(entries: [
            "HelloWorld/Package.swift": atCap,
        ])
        let manifests = try ManifestExtractor.extract(from: data, maxManifestBytes: 128)
        #expect(manifests[""] == atCap)
    }
}

func makeZip(entries: [String: String]) throws -> Data {
    let archive = try Archive(accessMode: .create)
    for (path, contents) in entries {
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }
    return archive.data ?? Data()
}