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
import NIOCore
@testable import RegistryExample

@Suite("ReleasePublisher")
struct ReleasePublisherTests {
    private func makePublisher() -> (ReleasePublisher, RegistryStore) {
        let store = RegistryStore()
        return (ReleasePublisher(store: store), store)
    }

    private static let mona = try! PackageIdentifier(scope: "mona", name: "LinkedList")
    private static let v1 = try! PackageVersion("1.0.0")

    private func archiveBody(metadata: String? = nil) throws -> (ByteBuffer, String) {
        let zip = try makeHelloWorldZip()
        let body = publishMultipartBody(zip: zip, metadata: metadata)
        return (body, MultipartBuilder.contentTypeHeader)
    }

    // MARK: happy path

    @Test func `publish stores a release and returns it`() async throws {
        let (publisher, store) = makePublisher()
        let (body, contentType) = try archiveBody()
        let release = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: contentType, signatureFormat: nil
        )
        #expect(release.identifier == Self.mona)
        #expect(release.version == Self.v1)
        #expect(release.manifests[""] != nil)
        #expect(!release.sourceArchiveChecksum.isEmpty)
        let stored = await store.get(Self.mona, version: Self.v1)
        #expect(stored != nil)
    }

    @Test func `publish decodes metadata when present`() async throws {
        let (publisher, _) = makePublisher()
        let (body, contentType) = try archiveBody(
            metadata: #"{"description":"links to things"}"#
        )
        let release = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: contentType, signatureFormat: nil
        )
        #expect(release.metadata?.description == "links to things")
        #expect(release.metadataRaw != nil)
    }

    @Test func `publish computes a hex sha-256 checksum of the source archive`() async throws {
        let (publisher, _) = makePublisher()
        let (body, contentType) = try archiveBody()
        let release = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: contentType, signatureFormat: nil
        )
        #expect(release.sourceArchiveChecksum.count == 64)
        #expect(release.sourceArchiveChecksum.allSatisfy { $0.isHexDigit })
    }

    // MARK: conflicts

    @Test func `republishing the same version throws conflict`() async throws {
        let (publisher, _) = makePublisher()
        let (body, contentType) = try archiveBody()
        _ = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: contentType, signatureFormat: nil
        )
        await #expect(throws: PublishError.conflict) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: contentType, signatureFormat: nil
            )
        }
    }

    @Test func `republishing with build metadata still throws conflict`() async throws {
        let (publisher, _) = makePublisher()
        let (body, contentType) = try archiveBody()
        _ = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: contentType, signatureFormat: nil
        )
        let buildVariant = try PackageVersion("1.0.0+build.42")
        await #expect(throws: PublishError.conflict) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: buildVariant,
                body: body, contentType: contentType, signatureFormat: nil
            )
        }
    }

    // MARK: archive errors

    @Test func `missing source-archive part throws missingArchive`() async throws {
        let (publisher, _) = makePublisher()
        let body = MultipartBuilder.body(parts: [
            .init(name: "metadata", data: Data("{}".utf8), contentType: "application/json")
        ])
        await #expect(throws: PublishError.missingArchive) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    @Test func `corrupt archive throws invalidArchive`() async throws {
        let (publisher, _) = makePublisher()
        let body = MultipartBuilder.body(parts: [
            .init(
                name: "source-archive",
                data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                contentType: "application/zip"
            )
        ])
        await #expect(throws: PublishError.invalidArchive) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    @Test func `zip without Package.swift throws manifestMissing`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeZip(entries: ["readme.txt": "hi"])
        let body = publishMultipartBody(zip: zip, metadata: nil)
        await #expect(throws: PublishError.manifestMissing) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    // MARK: metadata errors

    @Test func `invalid metadata JSON throws invalidMetadataJSON`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = MultipartBuilder.body(parts: [
            .init(name: "source-archive", data: zip, contentType: "application/zip"),
            .init(name: "metadata", data: Data("not json".utf8), contentType: "application/json")
        ])
        await #expect(throws: PublishError.invalidMetadataJSON) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    @Test func `metadata with a malformed repository URL throws invalidMetadataJSON`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = MultipartBuilder.body(parts: [
            .init(name: "source-archive", data: zip, contentType: "application/zip"),
            .init(
                name: "metadata",
                data: Data(#"{"repositoryURLs":["ssh://git@github.com:mona/LinkedList.git"]}"#.utf8),
                contentType: "application/json"
            )
        ])
        await #expect(throws: PublishError.invalidMetadataJSON) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    @Test func `body with malformed headers throws malformedMultipart`() async throws {
        let (publisher, _) = makePublisher()
        var body = ByteBufferAllocator().buffer(capacity: 64)
        let boundary = "declared-boundary"
        body.writeString("--\(boundary)\r\n")
        body.writeString("no colon here\r\n")
        body.writeString("\r\n")
        body.writeString("junk\r\n")
        body.writeString("--\(boundary)--\r\n")
        await #expect(throws: PublishError.malformedMultipart) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body,
                contentType: "multipart/form-data; boundary=\"\(boundary)\"",
                signatureFormat: nil
            )
        }
    }

    @Test func `missing boundary parameter throws missingMultipartBoundary`() async throws {
        let (publisher, _) = makePublisher()
        let (body, _) = try archiveBody()
        await #expect(throws: PublishError.missingMultipartBoundary) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: "multipart/form-data",
                signatureFormat: nil
            )
        }
    }

    // MARK: signature rules

    @Test func `metadata-signature without metadata throws metadataSignatureRequiresMetadata`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = signedPublishBody(
            zip: zip, metadata: nil,
            archiveSignature: Data([0x01]),
            metadataSignature: Data([0x02])
        )
        await #expect(throws: PublishError.metadataSignatureRequiresMetadata) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: "cms-1.0.0"
            )
        }
    }

    @Test func `signature part without format throws signaturePartRequiresFormat`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = signedPublishBody(
            zip: zip, metadata: nil,
            archiveSignature: Data([0x01]),
            metadataSignature: nil
        )
        await #expect(throws: PublishError.signaturePartRequiresFormat) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: nil
            )
        }
    }

    @Test func `format header without signature throws signatureFormatRequiresPart`() async throws {
        let (publisher, _) = makePublisher()
        let (body, contentType) = try archiveBody()
        await #expect(throws: PublishError.signatureFormatRequiresPart) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: contentType,
                signatureFormat: "cms-1.0.0"
            )
        }
    }

    @Test func `unknown signature format throws unsupportedSignatureFormat`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = signedPublishBody(
            zip: zip, metadata: nil,
            archiveSignature: Data([0x01]),
            metadataSignature: nil
        )
        await #expect(throws: PublishError.unsupportedSignatureFormat("bogus-0.0.0")) {
            _ = try await publisher.publish(
                identifier: Self.mona, version: Self.v1,
                body: body, contentType: MultipartBuilder.contentTypeHeader,
                signatureFormat: "bogus-0.0.0"
            )
        }
    }

    @Test func `signed publish stores both signatures and format`() async throws {
        let (publisher, _) = makePublisher()
        let zip = try makeHelloWorldZip()
        let body = signedPublishBody(
            zip: zip,
            metadata: #"{"description":"signed"}"#,
            archiveSignature: Data([0xAA, 0xBB]),
            metadataSignature: Data([0xCC, 0xDD])
        )
        let release = try await publisher.publish(
            identifier: Self.mona, version: Self.v1,
            body: body, contentType: MultipartBuilder.contentTypeHeader,
            signatureFormat: "cms-1.0.0"
        )
        #expect(release.sourceArchiveSignature == Data([0xAA, 0xBB]))
        #expect(release.metadataSignature == Data([0xCC, 0xDD]))
        #expect(release.signatureFormat == "cms-1.0.0")
    }
}