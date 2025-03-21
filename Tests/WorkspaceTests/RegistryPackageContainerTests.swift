//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Foundation
import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import _InternalTestSupport
@testable import Workspace
import XCTest

import struct TSCUtility.Version

final class RegistryPackageContainerTests: XCTestCase {

    override func setUpWithError() throws {
        try skipOnWindowsAsTestCurrentlyFails()
    }

    func testToolsVersionCompatibleVersions() async throws {
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let packageIdentity = PackageIdentity.plain("org.foo")
        let packageVersion = Version("1.0.0")
        let packagePath = AbsolutePath.root

        func createProvider(_ toolsVersion: ToolsVersion) throws -> PackageContainerProvider {
            let registryClient = try makeRegistryClient(
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                packagePath: packagePath,
                fileSystem: fs,
                releasesRequestHandler: { request, _ in
                    let metadata = RegistryClient.Serialization.PackageMetadata(
                        releases: [
                            "1.0.0":  .init(url: .none, problem: .none),
                            "1.0.1":  .init(url: .none, problem: .none),
                            "1.0.2":  .init(url: .none, problem: .none),
                            "1.0.3":  .init(url: .none, problem: .none)
                        ]
                    )
                    return HTTPClientResponse(
                        statusCode: 200,
                        headers: [
                            "Content-Version": "1",
                            "Content-Type": "application/json"
                        ],
                        body: try! JSONEncoder.makeWithDefaults().encode(metadata)
                    )
                },
                manifestRequestHandler: { request, _ in
                    let toolsVersion: ToolsVersion
                    switch request.url.deletingLastPathComponent().lastPathComponent {
                    case "1.0.0":
                        toolsVersion = .v3
                    case "1.0.1":
                        toolsVersion = .v4
                    case "1.0.2":
                        toolsVersion = .v4_2
                    case "1.0.3":
                        toolsVersion = .v5_4
                    default:
                        toolsVersion = .current
                    }
                    return HTTPClientResponse(
                        statusCode: 200,
                        headers: [
                            "Content-Version": "1",
                            "Content-Type": "text/x-swift"
                        ],
                        body: Data("// swift-tools-version:\(toolsVersion)".utf8)
                    )
                }
            )

            return try Workspace._init(
                fileSystem: fs,
                environment: .mockEnvironment,
                location: .init(forRootPackage: packagePath, fileSystem: fs),
                customToolsVersion: toolsVersion,
                customHostToolchain: .mockHostToolchain(fs),
                customManifestLoader: MockManifestLoader(manifests: [:]),
                customRegistryClient: registryClient
            )
        }

        do {
            let provider = try createProvider(.v4)
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, ["1.0.1"])
        }

        do {
            let provider = try createProvider(.v4_2)
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, ["1.0.2", "1.0.1"])
        }

        do {
            let provider = try createProvider(.v5_4)
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, ["1.0.3", "1.0.2", "1.0.1"])
        }
    }

    func testAlternateManifests() async throws {
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let packageIdentity = PackageIdentity.plain("org.foo")
        let packageVersion = Version("1.0.0")
        let packagePath = AbsolutePath.root

        func createProvider(_ toolsVersion: ToolsVersion) throws -> PackageContainerProvider {
            let registryClient = try makeRegistryClient(
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                packagePath: packagePath,
                fileSystem: fs,
                manifestRequestHandler: { request, _ in
                    return HTTPClientResponse(
                        statusCode: 200,
                        headers: [
                            "Content-Version": "1",
                            "Content-Type": "text/x-swift",
                            "Link": """
                            \(self.manifestLink(packageIdentity, .v5_4)),
                            \(self.manifestLink(packageIdentity, .v5_5)),
                            """
                        ],
                        body: Data("// swift-tools-version:\(ToolsVersion.v5_3)".utf8)
                    )
                }
            )

            return try Workspace._init(
                fileSystem: fs,
                environment: .mockEnvironment,
                location: .init(forRootPackage: packagePath, fileSystem: fs),
                customToolsVersion: toolsVersion,
                customHostToolchain: .mockHostToolchain(fs),
                customManifestLoader: MockManifestLoader(manifests: [:]),
                customRegistryClient: registryClient
            )
        }

        do {
            let provider = try createProvider(.v5_2) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let version = try await container.toolsVersion(for: packageVersion)
            XCTAssertEqual(version, .v5_3)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, [])
        }

        do {
            let provider = try createProvider(.v5_3) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let version = try await container.toolsVersion(for: packageVersion)
            XCTAssertEqual(version, .v5_3)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, [packageVersion])
        }

        do {
            let provider = try createProvider(.v5_4) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let version = try await container.toolsVersion(for: packageVersion)
            XCTAssertEqual(version, .v5_4)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, [packageVersion])
        }

        do {
            let provider = try createProvider(.v5_5) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let version = try await container.toolsVersion(for: packageVersion)
            XCTAssertEqual(version, .v5_5)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, [packageVersion])
        }

        do {
            let provider = try createProvider(.v5_6) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref)
            let version = try await container.toolsVersion(for: packageVersion)
            XCTAssertEqual(version, .v5_5)
            let versions = try await container.toolsVersionsAppropriateVersionsDescending()
            XCTAssertEqual(versions, [packageVersion])
        }
    }

    func testLoadManifest() async throws {
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let packageIdentity = PackageIdentity.plain("org.foo")
        let packageVersion = Version("1.0.0")
        let packagePath = AbsolutePath.root

        let v5_3_3 = ToolsVersion(string: "5.3.3")!

        func createProvider(_ toolsVersion: ToolsVersion) throws -> PackageContainerProvider {
            let supportedVersions = Set<ToolsVersion>([ToolsVersion.v5, .v5_3, v5_3_3, .v5_4, .v5_5])
            let registryClient = try makeRegistryClient(
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                packagePath: packagePath,
                fileSystem: fs,
                manifestRequestHandler: { request, _ in
                    let requestedVersionString = request.url.query?.spm_dropPrefix("swift-version=")
                    let requestedVersion = (requestedVersionString.flatMap{ ToolsVersion(string: $0) }) ?? .v5_3
                    guard supportedVersions.contains(requestedVersion) else {
                        throw StringError("invalid version \(requestedVersion)")
                    }
                    return HTTPClientResponse(
                        statusCode: 200,
                        headers: [
                            "Content-Version": "1",
                            "Content-Type": "text/x-swift",
                            "Link": (supportedVersions.subtracting([requestedVersion])).map {
                                self.manifestLink(packageIdentity, $0)
                            }.joined(separator: ",\n")
                        ],
                        body: Data("// swift-tools-version:\(requestedVersion)".utf8)
                    )
                }
            )

            return try Workspace._init(
                fileSystem: fs,
                environment: .mockEnvironment,
                location: .init(forRootPackage: packagePath, fileSystem: fs),
                customToolsVersion: toolsVersion,
                customHostToolchain: .mockHostToolchain(fs),
                customManifestLoader: MockManifestLoader(),
                customRegistryClient: registryClient
            )

            struct MockManifestLoader: ManifestLoaderProtocol {
                func load(manifestPath: AbsolutePath,
                          manifestToolsVersion: ToolsVersion,
                          packageIdentity: PackageIdentity,
                          packageKind: PackageReference.Kind,
                          packageLocation: String,
                          packageVersion: (version: Version?, revision: String?)?,
                          identityResolver: IdentityResolver,
                          dependencyMapper: DependencyMapper,
                          fileSystem: FileSystem,
                          observabilityScope: ObservabilityScope,
                          delegateQueue: DispatchQueue,
                          callbackQueue: DispatchQueue,
                          completion: @escaping (Result<Manifest, Error>) -> Void) {
                    completion(.success(
                        Manifest.createManifest(
                            displayName: packageIdentity.description,
                            path: manifestPath,
                            packageKind: packageKind,
                            packageLocation: packageLocation,
                            platforms: [],
                            toolsVersion: manifestToolsVersion
                        )
                    ))
                }

                func resetCache(observabilityScope: ObservabilityScope) {}
                func purgeCache(observabilityScope: ObservabilityScope) {}
            }
        }

        do {
            let provider = try createProvider(.v5_3) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, .v5_3)
        }

        do {
            let provider = try createProvider(v5_3_3) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, v5_3_3)
        }

        do {
            let provider = try createProvider(.v5_4) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, .v5_4)
        }

        do {
            let provider = try createProvider(.v5_5) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, .v5_5)
        }

        do {
            let provider = try createProvider(.v5_6) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, .v5_5)
        }
        
        do {
            let provider = try createProvider(.v5) // the version of the alternate
            let ref = PackageReference.registry(identity: packageIdentity)
            let container = try await provider.getContainer(for: ref) as! RegistryPackageContainer
            let manifest = try await container.loadManifest(version: packageVersion)
            XCTAssertEqual(manifest.toolsVersion, .v5)
        }
    }

    func makeRegistryClient(
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packagePath: AbsolutePath,
        fileSystem: FileSystem,
        configuration: PackageRegistry.RegistryConfiguration? = .none,
        releasesRequestHandler: HTTPClient.Implementation? = .none,
        versionMetadataRequestHandler: HTTPClient.Implementation? = .none,
        manifestRequestHandler: HTTPClient.Implementation? = .none,
        downloadArchiveRequestHandler: HTTPClient.Implementation? = .none,
        archiver: Archiver? = .none
    ) throws -> RegistryClient {
        let jsonEncoder = JSONEncoder.makeWithDefaults()
        let fingerprintStorage = MockPackageFingerprintStorage()

        guard let registryIdentity = packageIdentity.registry else {
            throw StringError("Invalid package identifier: '\(packageIdentity)'")
        }

        var configuration = configuration
        if configuration == nil {
            configuration = PackageRegistry.RegistryConfiguration()
            configuration!.defaultRegistry = .init(url: "http://localhost", supportsAvailability: false)
        }

        let releasesRequestHandler = releasesRequestHandler ?? { request, _ in
            let metadata = RegistryClient.Serialization.PackageMetadata(
                releases: [packageVersion.description:  .init(url: .none, problem: .none)]
            )
            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/json"
                ],
                body: try! jsonEncoder.encode(metadata)
            )
        }

        let versionMetadataRequestHandler = versionMetadataRequestHandler ?? { request, _ in
            let metadata = RegistryClient.Serialization.VersionMetadata(
                id: packageIdentity.description,
                version: packageVersion.description,
                resources: [
                    .init(
                        name: "source-archive",
                        type: "application/zip",
                        checksum: "",
                        signing: nil
                    )
                ],
                metadata: .init(description: ""),
                publishedAt: nil
            )
            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/json"
                ],
                body: try! jsonEncoder.encode(metadata)
            )
        }

        let manifestRequestHandler = manifestRequestHandler ?? { request, _ in
            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "text/x-swift"
                ],
                body: Data("// swift-tools-version:\(ToolsVersion.current)".utf8)
            )
        }

        let downloadArchiveRequestHandler = downloadArchiveRequestHandler ?? { request, _ in
            // meh
            let path = packagePath
                .appending(components: ".build", "registry", "downloads", registryIdentity.scope.description, registryIdentity.name.description)
                .appending("\(packageVersion).zip")
            try! fileSystem.createDirectory(path.parentDirectory, recursive: true)
            try! fileSystem.writeFileContents(path, string: "")

            return HTTPClientResponse(
                statusCode: 200,
                headers: [
                    "Content-Version": "1",
                    "Content-Type": "application/zip"
                ],
                body: Data("".utf8)
            )
        }

        let archiver = archiver ?? MockArchiver(handler: { archiver, from, to, completion in
            do {
                try fileSystem.createDirectory(to.appending("top"), recursive: true)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        })

        return RegistryClient(
            configuration: configuration!,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            authorizationProvider: .none,
            customHTTPClient: HTTPClient(configuration: .init(), implementation: { request, progress in
                var pathComponents = request.url.pathComponents
                if pathComponents.first == "/" {
                    pathComponents = Array(pathComponents.dropFirst())
                }
                guard pathComponents.count >= 2 else {
                    throw StringError("invalid url \(request.url)")
                }
                guard pathComponents[0] == registryIdentity.scope.description else {
                    throw StringError("invalid url \(request.url)")
                }
                guard pathComponents[1] == registryIdentity.name.description else {
                    throw StringError("invalid url \(request.url)")
                }

                switch pathComponents.count {
                case 2:
                    return try await releasesRequestHandler(request, progress)
                case 3 where pathComponents[2].hasSuffix(".zip"):
                    return try await downloadArchiveRequestHandler(request, progress)
                case 3:
                    return try await versionMetadataRequestHandler(request, progress)
                case 4 where pathComponents[3].hasSuffix(".swift"):
                    return try await manifestRequestHandler(request, progress)
                default:
                    throw StringError("unexpected url \(request.url)")
                }
            }),
            customArchiverProvider: { _ in archiver },
            delegate: .none,
            checksumAlgorithm: MockHashAlgorithm()
        )
    }

    private func manifestLink(_ identity: PackageIdentity, _ version: ToolsVersion) -> String {
        guard let registryIdentity = identity.registry else {
            preconditionFailure("invalid registry identity: '\(identity)'")
        }
        let versionString = if version.patch == 0 && version.minor == 0 {
            "\(version.major)"
        } else if version.patch == 0 {
            "\(version.major).\(version.minor)"
        } else {
            version.description
        }
        return "<http://localhost/\(registryIdentity.scope)/\(registryIdentity.name)/\(version)/\(Manifest.filename)?swift-version=\(version)>; rel=\"alternate\"; filename=\"\(Manifest.basename)@swift-\(versionString).swift\"; swift-tools-version=\"\(version)\""
    }
}

extension PackageContainerProvider {
    fileprivate func getContainer(for package: PackageReference, updateStrategy: ContainerUpdateStrategy = .always) async throws -> PackageContainer {
        try await self.getContainer(
            for: package,
            updateStrategy: updateStrategy,
            observabilityScope: ObservabilitySystem.NOOP,
            on: .global()
        )
    }
}
