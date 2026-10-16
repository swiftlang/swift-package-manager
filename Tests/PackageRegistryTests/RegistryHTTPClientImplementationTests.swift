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

import Basics
import Foundation
import NIOConcurrencyHelpers
import NIOSSL
import PackageModel
import Testing
@testable import PackageRegistry

private let registryURL = URL(string: "https://mtls.example.com")!
private let availabilityURL = URL(string: "https://mtls.example.com/availability")!
private let certificateFile = AbsolutePath("/identity/client.cer")
private let privateKeyFile = AbsolutePath("/identity/client.key")

private let clientIdentity = RegistryConfiguration.Identity.files(
    certificatePath: certificateFile.pathString,
    privateKeyPath: privateKeyFile.pathString
)

@Suite("Registry HTTP Client Implementation") struct RegistryHTTPClientImplementationTests {
    @Test func usesTheDefaultTransportWhenNoRegistryHasAnIdentity() async throws {
        let transports = TransportRecorder()
        let implementation = transports.implementation(
            configuration: RegistryConfiguration(),
            fileSystem: InMemoryFileSystem()
        )

        let response = try await implementation.execute(HTTPClientRequest(url: availabilityURL), progress: .none)

        #expect(response.statusCode == 200)
        #expect(transports.defaultTransportURLs == [availabilityURL])
        #expect(transports.mutualTLSURLs.isEmpty)
    }

    @Test func usesTheDefaultTransportForAnotherRegistry() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let transports = TransportRecorder()
            let implementation = transports.implementation(
                configuration: try Self.configurationWithIdentity(),
                fileSystem: try Self.fileSystem(material)
            )
            let elsewhere = URL(string: "https://plain.example.com/availability")!

            _ = try await implementation.execute(HTTPClientRequest(url: elsewhere), progress: .none)

            #expect(transports.defaultTransportURLs == [elsewhere])
            #expect(transports.mutualTLSURLs.isEmpty)
        }
    }

    @Test func usesTheDefaultTransportForAURLWithoutAHost() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let transports = TransportRecorder()
            let implementation = transports.implementation(
                configuration: try Self.configurationWithIdentity(),
                fileSystem: try Self.fileSystem(material)
            )
            let hostless = URL(string: "mailto:packages@example.com")!

            _ = try await implementation.execute(HTTPClientRequest(url: hostless), progress: .none)

            #expect(transports.defaultTransportURLs == [hostless])
        }
    }

    @Test func presentsTheConfiguredIdentityToTheMatchingRegistry() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let transports = TransportRecorder()
            let implementation = transports.implementation(
                configuration: try Self.configurationWithIdentity(),
                fileSystem: try Self.fileSystem(material)
            )

            _ = try await implementation.execute(HTTPClientRequest(url: availabilityURL), progress: .none)

            #expect(transports.defaultTransportURLs.isEmpty)
            #expect(transports.mutualTLSURLs == [availabilityURL])
            #expect(
                transports.presentedConfiguration?.certificateChain ==
                    [.certificate(try NIOSSLCertificate(bytes: material.certificateDER, format: .der))]
            )
        }
    }

    @Test func doesNotPresentTheIdentityToACrossOriginRedirectTarget() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let elsewhere = URL(string: "https://cdn.other.example/archive.zip")!
            let transports = TransportRecorder(responses: [availabilityURL: .movedTo(elsewhere)])
            let implementation = transports.implementation(
                configuration: try Self.configurationWithIdentity(),
                fileSystem: try Self.fileSystem(material)
            )

            _ = try await implementation.execute(HTTPClientRequest(url: availabilityURL), progress: .none)

            #expect(transports.mutualTLSURLs == [availabilityURL])
            #expect(transports.defaultTransportURLs == [elsewhere])
        }
    }

    @Test func keepsPresentingTheIdentityOnASameOriginRedirect() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let moved = URL(string: "https://mtls.example.com/moved")!
            let transports = TransportRecorder(responses: [availabilityURL: .movedTo(moved)])
            let implementation = transports.implementation(
                configuration: try Self.configurationWithIdentity(),
                fileSystem: try Self.fileSystem(material)
            )

            _ = try await implementation.execute(HTTPClientRequest(url: availabilityURL), progress: .none)

            #expect(transports.mutualTLSURLs == [availabilityURL, moved])
            #expect(transports.defaultTransportURLs.isEmpty)
            #expect(
                transports.presentedConfiguration?.certificateChain ==
                    [.certificate(try NIOSSLCertificate(bytes: material.certificateDER, format: .der))]
            )
        }
    }

    @Test func reportsAMissingCertificateByPath() async throws {
        let transports = TransportRecorder()
        let implementation = transports.implementation(
            configuration: try Self.configurationWithIdentity(),
            fileSystem: InMemoryFileSystem()
        )

        await #expect {
            try await implementation.execute(HTTPClientRequest(url: availabilityURL), progress: .none)
        } throws: { error in
            guard case RegistryClientIdentityError.missingFile(let path) = error else { return false }
            return path == certificateFile.pathString
        }
    }

    @Test func customHTTPClientOverridesTheMutualTLSTransport() async throws {
        let httpClient = HTTPClient { request, _ in
            guard request.url == availabilityURL else { throw StringError("unexpected \(request.url)") }
            return .okay()
        }
        let registryClient = makeRegistryClient(
            configuration: try Self.configurationWithIdentity(),
            httpClient: httpClient
        )

        let status = try await registryClient.checkAvailability(
            registry: Registry(url: registryURL, supportsAvailability: true)
        )

        #expect(status == .available())
    }

    @Test func reportsWhetherAnyRegistryHasAnIdentity() throws {
        #expect(RegistryClientIdentityLookup(configuration: RegistryConfiguration()).isEmpty)
        #expect(!RegistryClientIdentityLookup(configuration: try Self.configurationWithIdentity()).isEmpty)
    }

    private static func configurationWithIdentity() throws -> RegistryConfiguration {
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: true)
        try configuration.add(
            authentication: .init(type: .mtls, identity: clientIdentity),
            for: registryURL
        )
        return configuration
    }

    private static func fileSystem(_ material: IdentityMaterial) throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(certificateFile.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(certificateFile, data: Data(material.certificatePEM))
        try fileSystem.writeFileContents(privateKeyFile, data: Data(material.privateKeyPEM))
        return fileSystem
    }
}

extension HTTPClientResponse {
    fileprivate static func movedTo(_ destination: URL) -> HTTPClientResponse {
        HTTPClientResponse(statusCode: 307, headers: ["Location": destination.absoluteString])
    }
}

private final class TransportRecorder: Sendable {
    private let defaultTransport = NIOLockedValueBox<[URL]>([])
    private let mutualTLS = NIOLockedValueBox<[URL]>([])
    private let presented = NIOLockedValueBox<TLSConfiguration?>(nil)
    private let scripted: NIOLockedValueBox<[URL: HTTPClientResponse]>

    init(responses: [URL: HTTPClientResponse] = [:]) {
        self.scripted = NIOLockedValueBox(responses)
    }

    var defaultTransportURLs: [URL] {
        self.defaultTransport.withLockedValue { $0 }
    }

    var mutualTLSURLs: [URL] {
        self.mutualTLS.withLockedValue { $0 }
    }

    var presentedConfiguration: TLSConfiguration? {
        self.presented.withLockedValue { $0 }
    }

    func implementation(
        configuration: RegistryConfiguration,
        fileSystem: FileSystem
    ) -> RegistryHTTPClientImplementation {
        RegistryHTTPClientImplementation(
            identities: RegistryClientIdentityLookup(configuration: configuration),
            fileSystem: fileSystem,
            mutualTLS: { request, tlsConfiguration, _ in
                self.mutualTLS.withLockedValue { $0.append(request.url) }
                self.presented.withLockedValue { $0 = tlsConfiguration }
                return self.response(for: request.url)
            },
            fallback: { request, _ in
                self.defaultTransport.withLockedValue { $0.append(request.url) }
                return self.response(for: request.url)
            }
        )
    }

    private func response(for url: URL) -> HTTPClientResponse {
        self.scripted.withLockedValue { $0[url] } ?? .okay()
    }
}
