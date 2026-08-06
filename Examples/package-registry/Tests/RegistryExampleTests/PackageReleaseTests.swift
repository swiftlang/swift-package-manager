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
@testable import RegistryExample

@Suite("PackageRelease")
struct PackageReleaseTests {
    @Test func `memberwise constructed author with organization round-trips through JSON`() throws {
        let release = PackageRelease(
            author: PackageRelease.Author(
                name: "Alice",
                email: "alice@example.com",
                description: "maintainer",
                organization: PackageRelease.Author.Organization(
                    name: "Acme",
                    email: "info@acme.example",
                    description: "example org",
                    url: URL(string: "https://acme.example")
                ),
                url: URL(string: "https://example.com/alice")
            ),
            description: "demo",
            licenseURL: URL(string: "https://example.com/LICENSE"),
            readmeURL: URL(string: "https://example.com/README"),
            repositoryURLs: [URL(string: "https://example.com/repo.git")!],
            originalPublicationTime: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let data = try JSONEncoder.registry.encode(release)
        let decoded = try JSONDecoder.registry.decode(PackageRelease.self, from: data)
        #expect(decoded == release)
    }
}