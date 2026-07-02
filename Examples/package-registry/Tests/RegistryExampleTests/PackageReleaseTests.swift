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
                    url: "https://acme.example"
                ),
                url: "https://example.com/alice"
            ),
            description: "demo",
            licenseURL: "https://example.com/LICENSE",
            readmeURL: "https://example.com/README",
            repositoryURLs: ["https://example.com/repo.git"],
            originalPublicationTime: "2025-01-01T00:00:00Z"
        )
        let data = try JSONEncoder().encode(release)
        let decoded = try JSONDecoder().decode(PackageRelease.self, from: data)
        #expect(decoded == release)
    }
}