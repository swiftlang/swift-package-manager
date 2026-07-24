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

@Suite("Metadata endpoints")
struct MetadataRouteTests {
    @Test func `GET /{scope}/{name} returns releases with latest-version link`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await publishHelloWorld(app: app, version: "1.2.3")

            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .json)
                #expect(res.headers.first(name: "Content-Version") == "1")
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("rel=\"latest-version\""))
                #expect(link.contains("/exampleregistry/HelloWorld/1.2.3"))
                #expect(res.body.string.contains("\"1.0.0\""))
                #expect(res.body.string.contains("\"1.2.3\""))
            }
        }
    }

    @Test func `list response exposes canonical and alternate repository URLs from latest release metadata`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(
                app: app,
                version: "1.0.0",
                metadata: #"{"repositoryURLs":["https://old.example.com/HelloWorld"]}"#
            )
            try await publishHelloWorld(
                app: app,
                version: "1.2.3",
                metadata: #"{"repositoryURLs":["https://github.com/exampleregistry/HelloWorld","git@github.com:exampleregistry/HelloWorld.git","ssh://git@github.com/exampleregistry/HelloWorld.git"]}"#
            )

            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("<https://github.com/exampleregistry/HelloWorld>; rel=\"canonical\""))
                #expect(link.contains("<git@github.com:exampleregistry/HelloWorld.git>; rel=\"alternate\""))
                #expect(link.contains("<ssh://git@github.com/exampleregistry/HelloWorld.git>; rel=\"alternate\""))
                #expect(!link.contains("old.example.com"))
            }
        }
    }

    @Test func `repository URL containing Link-header delimiters is percent-encoded rather than injected`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(
                app: app,
                version: "1.0.0",
                metadata: #"{"repositoryURLs":["https://example.com/x>;rel=\"canonical\",<https://evil.test/y"]}"#
            )
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("%3E"))
                #expect(!link.contains("<https://evil.test/y"))
                #expect(link.components(separatedBy: "rel=\"canonical\"").count - 1 == 1)
            }
        }
    }

    @Test func `list response omits repository links when latest release has no repositoryURLs`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(!link.contains("rel=\"canonical\""))
                #expect(!link.contains("rel=\"alternate\""))
            }
        }
    }

    @Test func `GET /{scope}/{name}.json is treated the same as /{scope}/{name}`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld.json", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `GET /{scope}/{name} returns 404 for unknown package`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .GET, "/nobody/Ghost", headers: acceptJSON
            ) { res async in
                #expect(res.status == .notFound)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `GET /{scope}/{name}/{version} returns release info with resources`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"id\":\"exampleregistry.HelloWorld\""))
                #expect(body.contains("\"version\":\"1.0.0\""))
                #expect(body.contains("\"source-archive\""))
                #expect(body.contains("\"application/zip\""))
                #expect(body.contains("\"checksum\""))
            }
        }
    }

    @Test func `release info always includes a metadata key even when none was submitted`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"metadata\":{}"))
            }
        }
    }

    @Test func `GET /{scope}/{name}/{version} returns 404 for unknown release`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/9.9.9", headers: acceptJSON
            ) { res async in
                #expect(res.status == .notFound)
            }
        }
    }

    @Test func `GET Package.swift returns default manifest with alternates Link header`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0", includeSwift510: true)
            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0/Package.swift",
                headers: acceptSwift
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == HTTPMediaType(type: "text", subType: "x-swift"))
                #expect(res.body.string.contains("swift-tools-version:5.9"))
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("Package.swift"))
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("rel=\"alternate\""))
                #expect(link.contains("Package@swift-5.10.swift"))
            }
        }
    }

    @Test func `GET Package.swift?swift-version=X returns matching alternate`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0", includeSwift510: true)
            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0/Package.swift?swift-version=5.10",
                headers: acceptSwift
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("swift-tools-version:5.10"))
            }
        }
    }

    @Test func `GET Package.swift?swift-version=X redirects when no match`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0/Package.swift?swift-version=99",
                headers: acceptSwift
            ) { res async in
                #expect(res.status == .seeOther)
                #expect(
                    res.headers.first(name: .location)?
                        .hasSuffix("/exampleregistry/HelloWorld/1.0.0/Package.swift") == true
                )
                #expect(res.headers.first(name: .contentType) != "application/problem+json")
                #expect(res.body.string.isEmpty)
            }
        }
    }

    @Test func `GET source archive returns zip with Digest header`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0.zip",
                headers: acceptZip
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .zip)
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("HelloWorld-1.0.0.zip"))
                #expect(res.headers.first(name: "Accept-Ranges") == "bytes")
                #expect(res.headers.first(name: "Digest")?.hasPrefix("sha-256=") == true)
                #expect(res.headers.first(name: .cacheControl)?.contains("immutable") == true)
            }
        }
    }

    @Test func `GET with invalid scope returns 400`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .GET, "/bad..scope/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid package scope"))
            }
        }
    }

    @Test func `GET with invalid name returns 400`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .GET, "/exampleregistry/bad..name", headers: acceptJSON
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid package name"))
            }
        }
    }

    @Test func `GET release with invalid version returns 400`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/not-a-version", headers: acceptJSON
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid version"))
            }
        }
    }

    @Test func `release info includes predecessor and successor version links`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await publishHelloWorld(app: app, version: "1.1.0")
            try await publishHelloWorld(app: app, version: "2.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.1.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("/exampleregistry/HelloWorld/1.0.0>; rel=\"predecessor-version\""))
                #expect(link.contains("/exampleregistry/HelloWorld/2.0.0>; rel=\"successor-version\""))
                #expect(link.contains("rel=\"latest-version\""))
            }
        }
    }

    @Test func `alternate link falls back to swift-version key when manifest lacks tools-version prefix`() async throws {
        try await withRegistryApp { app in
            let entries: [String: String] = [
                "HelloWorld-1.0.0/Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"HelloWorld\")",
                "HelloWorld-1.0.0/Package@swift-5.10.swift": "import PackageDescription\nlet package = Package(name: \"HelloWorld\")",
            ]
            let zip = try makeZip(entries: entries)
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: publishMultipartBody(zip: zip, metadata: nil)
            ) { res async in #expect(res.status == .created) }

            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0/Package.swift",
                headers: acceptSwift
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("swift-tools-version=\"5.10\""))
            }
        }
    }

    @Test func `alternate link reads tools-version from below a license header`() async throws {
        try await withRegistryApp { app in
            let licensedManifest = """
            // Copyright (c) 2026 Apple Inc. and the Swift project authors
            // Licensed under Apache License v2.0
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "HelloWorld")
            """
            let entries: [String: String] = [
                "HelloWorld-1.0.0/Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"HelloWorld\")",
                "HelloWorld-1.0.0/Package@swift-5.10.swift": licensedManifest,
            ]
            let zip = try makeZip(entries: entries)
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: publishMultipartBody(zip: zip, metadata: nil)
            ) { res async in #expect(res.status == .created) }

            try await app.testing().test(
                .GET,
                "/exampleregistry/HelloWorld/1.0.0/Package.swift",
                headers: acceptSwift
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("Package@swift-5.10.swift"))
                #expect(link.contains("swift-tools-version=\"6.0\""))
            }
        }
    }

    @Test func `author with nested organization round-trips through publish and release info`() async throws {
        try await withRegistryApp { app in
            let metadata = """
            {
              "author": {
                "name": "Alice",
                "email": "alice@example.com",
                "description": "maintainer",
                "url": "https://example.com/alice",
                "organization": {
                  "name": "Acme",
                  "email": "info@acme.example",
                  "description": "example org",
                  "url": "https://acme.example"
                }
              }
            }
            """
            try await publishHelloWorld(app: app, version: "1.0.0", metadata: metadata)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"name\":\"Alice\""))
                #expect(body.contains("\"email\":\"alice@example.com\""))
                #expect(body.contains("\"description\":\"maintainer\""))
                #expect(body.contains("\"url\":\"https://example.com/alice\""))
                #expect(body.contains("\"name\":\"Acme\""))
                #expect(body.contains("\"email\":\"info@acme.example\""))
                #expect(body.contains("\"description\":\"example org\""))
                #expect(body.contains("\"url\":\"https://acme.example\""))
            }
        }
    }

    @Test func `release info surfaces signing on source-archive resource when signed`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let archiveSig = Data([0xCA, 0xFE, 0xBA, 0xBE])
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(signatureFormat: "cms-1.0.0"),
                body: signedPublishBody(
                    zip: zip,
                    metadata: nil,
                    archiveSignature: archiveSig,
                    metadataSignature: nil
                )
            ) { res async in #expect(res.status == .created) }

            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Swift-Package-Signature") == nil)
                #expect(res.headers.first(name: "X-Swift-Package-Signature-Format") == nil)
                let body = res.body.string
                #expect(body.contains("\"signing\""))
                #expect(body.contains("\"signatureFormat\":\"cms-1.0.0\""))
                #expect(body.contains("\"signatureBase64Encoded\":\"\(archiveSig.base64EncodedString())\""))
            }
        }
    }

    @Test func `release info omits signature headers even when metadata-signature published`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(signatureFormat: "cms-1.0.0"),
                body: signedPublishBody(
                    zip: zip,
                    metadata: #"{"description":"hi"}"#,
                    archiveSignature: Data([0x01]),
                    metadataSignature: Data([0x11, 0x22, 0x33])
                )
            ) { res async in #expect(res.status == .created) }

            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Swift-Package-Signature") == nil)
                #expect(res.headers.first(name: "X-Swift-Package-Signature-Format") == nil)
            }
        }
    }

    @Test func `release info omits signing fields for unsigned releases`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Swift-Package-Signature") == nil)
                #expect(res.headers.first(name: "X-Swift-Package-Signature-Format") == nil)
                #expect(!res.body.string.contains("\"signing\""))
            }
        }
    }

    @Test func `source archive download emits signature headers for signed release`() async throws {
        try await withRegistryApp { app in
            let zip = try makeHelloWorldZip()
            let archiveSig = Data([0xDE, 0xAD, 0xBE, 0xEF])
            try await app.testing().test(
                .PUT,
                "/exampleregistry/HelloWorld/1.0.0",
                headers: publishHeaders(signatureFormat: "cms-1.0.0"),
                body: signedPublishBody(
                    zip: zip,
                    metadata: nil,
                    archiveSignature: archiveSig,
                    metadataSignature: nil
                )
            ) { res async in #expect(res.status == .created) }

            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0.zip", headers: acceptZip
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Swift-Package-Signature-Format") == "cms-1.0.0")
                #expect(res.headers.first(name: "X-Swift-Package-Signature") == archiveSig.base64EncodedString())
            }
        }
    }

    @Test func `source archive download omits signature headers for unsigned release`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld/1.0.0.zip", headers: acceptZip
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Swift-Package-Signature-Format") == nil)
                #expect(res.headers.first(name: "X-Swift-Package-Signature") == nil)
            }
        }
    }

    @Test func `single-page release list emits no pagination Link entries`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await publishHelloWorld(app: app, version: "1.1.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(!link.contains("rel=\"first\""))
                #expect(!link.contains("rel=\"last\""))
                #expect(!link.contains("rel=\"next\""))
                #expect(!link.contains("rel=\"prev\""))
            }
        }
    }

    @Test func `paginated release list returns default page one with first last next links`() async throws {
        try await withRegistryApp { app in
            try await seedReleases(app: app, count: 55)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"0.0.55\""))
                #expect(body.contains("\"0.0.6\""))
                #expect(!body.contains("\"0.0.5\""))
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("/exampleregistry/HelloWorld?page=1>; rel=\"first\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=2>; rel=\"next\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=2>; rel=\"last\""))
                #expect(!link.contains("rel=\"prev\""))
            }
        }
    }

    @Test func `paginated release list page two returns remainder with first prev links`() async throws {
        try await withRegistryApp { app in
            try await seedReleases(app: app, count: 55)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=2", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"0.0.5\""))
                #expect(body.contains("\"0.0.1\""))
                #expect(!body.contains("\"0.0.6\""))
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("/exampleregistry/HelloWorld?page=1>; rel=\"first\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=1>; rel=\"prev\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=2>; rel=\"last\""))
                #expect(!link.contains("rel=\"next\""))
            }
        }
    }

    @Test func `middle page emits both prev and next links`() async throws {
        try await withRegistryApp { app in
            try await seedReleases(app: app, count: 120)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=2", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("rel=\"first\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=1>; rel=\"prev\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=3>; rel=\"next\""))
                #expect(link.contains("/exampleregistry/HelloWorld?page=3>; rel=\"last\""))
            }
        }
    }

    @Test func `paginated list preserves latest-version Link from overall latest release`() async throws {
        try await withRegistryApp { app in
            try await seedReleases(app: app, count: 55)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=2", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("/exampleregistry/HelloWorld/0.0.55>; rel=\"latest-version\""))
            }
        }
    }

    @Test func `invalid page query parameter returns 400`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .badRequest)
            }
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=abc", headers: acceptJSON
            ) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func `page beyond last returns 404`() async throws {
        try await withRegistryApp { app in
            try await seedReleases(app: app, count: 55)
            try await app.testing().test(
                .GET, "/exampleregistry/HelloWorld?page=3", headers: acceptJSON
            ) { res async in
                #expect(res.status == .notFound)
            }
        }
    }
}

@Suite("Identifiers endpoint")
struct IdentifiersRouteTests {
    @Test func `GET /identifiers returns matching identifiers`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(
                app: app,
                version: "1.0.0",
                metadata: #"{"repositoryURLs":["https://github.com/exampleregistry/HelloWorld"]}"#
            )
            try await app.testing().test(
                .GET,
                "/identifiers?url=https://github.com/exampleregistry/HelloWorld",
                headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("exampleregistry.HelloWorld"))
            }
        }
    }

    @Test func `missing url query parameter returns 400`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/identifiers", headers: acceptJSON) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func `no matching URL returns 404`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(
                app: app,
                version: "1.0.0",
                metadata: #"{"repositoryURLs":["https://github.com/exampleregistry/HelloWorld"]}"#
            )
            try await app.testing().test(
                .GET,
                "/identifiers?url=https://example.com/nope",
                headers: acceptJSON
            ) { res async in
                #expect(res.status == .notFound)
            }
        }
    }
}

let acceptJSON: HTTPHeaders = {
    var h = HTTPHeaders()
    h.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+json")
    return h
}()

let acceptSwift: HTTPHeaders = {
    var h = HTTPHeaders()
    h.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+swift")
    return h
}()

let acceptZip: HTTPHeaders = {
    var h = HTTPHeaders()
    h.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+zip")
    return h
}()

func seedReleases(app: Application, count: Int) async throws {
    let identifier = try PackageIdentifier(scope: "exampleregistry", name: "HelloWorld")
    for i in 1...count {
        let version = try PackageVersion("0.0.\(i)")
        let release = StoredRelease(
            identifier: identifier,
            version: version,
            sourceArchive: Data(),
            sourceArchiveChecksum: "",
            manifests: [:],
            metadata: nil,
            metadataRaw: nil,
            publishedAt: Date()
        )
        try await app.registryStore.publish(release)
    }
}

func publishHelloWorld(
    app: Application,
    version: String,
    metadata: String? = nil,
    includeSwift510: Bool = false
) async throws {
    var entries: [String: String] = [
        "HelloWorld-\(version)/Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"HelloWorld\")",
    ]
    if includeSwift510 {
        entries["HelloWorld-\(version)/Package@swift-5.10.swift"] = "// swift-tools-version:5.10\nimport PackageDescription\nlet package = Package(name: \"HelloWorld\")"
    }
    let zip = try makeZip(entries: entries)
    let body = publishMultipartBody(zip: zip, metadata: metadata)
    try await app.testing().test(
        .PUT,
        "/exampleregistry/HelloWorld/\(version)",
        headers: publishHeaders(),
        body: body
    ) { res async in
        #expect(res.status == .created)
    }
}