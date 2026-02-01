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
import Foundation
import OrderedCollections
import PackageModel

import protocol TSCBasic.HashAlgorithm
import struct TSCBasic.SHA256
import struct TSCUtility.Version

/// Delegate to notify clients about actions being performed by BinaryArtifactsDownloadsManage.
public protocol PrebuiltsManagerDelegate {
    /// The workspace has started downloading a binary artifact.
    func willDownloadPrebuilt(
        for package: PackageIdentity,
        from url: String,
        fromCache: Bool
    )
    /// The workspace has finished downloading a binary artifact.
    func didDownloadPrebuilt(
        for package: PackageIdentity,
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    )
    /// The workspace is downloading a binary artifact.
    func downloadingPrebuilt(
        for package: PackageIdentity,
        from url: String,
        bytesDownloaded: Int64,
        totalBytesToDownload: Int64?
    )
    /// The workspace finished downloading all binary artifacts.
    func didDownloadAllPrebuilts()
}

extension Workspace {
    public struct PrebuiltsManifest: Codable {
        public var libraries: [Library]

        public struct Library: Identifiable, Codable {
            public let name: String
            public var checksum: String
            public var products: [String]
            public var includePath: [String]?

            public var id: String { name }

            public init(
                name: String,
                checksum: String,
                products: [String] = [],
                includePath: [RelativePath]? = nil
            ) {
                self.name = name
                self.checksum = checksum
                self.products = products
                self.includePath = includePath?.map({ $0.pathString.replacingOccurrences(of: "\\", with: "/") })
            }
        }

        public init(libraries: [Library] = []) {
            self.libraries = libraries
        }
    }

    public struct SignedPrebuiltsManifest: Codable {
        public var manifest: PrebuiltsManifest
        public var signature: ManifestSignature

        public init(manifest: PrebuiltsManifest, signature: ManifestSignature) {
            self.manifest = manifest
            self.signature = signature
        }
    }

    /// For simplified init in tests
    public struct CustomPrebuiltsManager {
        let swiftVersion: String
        let httpClient: HTTPClient?
        let archiver: Archiver?
        let useCache: Bool?
        let hostPlatform: PrebuiltsPlatform?
        let rootCertPath: AbsolutePath?

        public init(
            swiftVersion: String,
            httpClient: HTTPClient? = .none,
            archiver: Archiver? = .none,
            useCache: Bool? = .none,
            hostPlatform: PrebuiltsPlatform? = nil,
            rootCertPath: AbsolutePath? = nil
        ) {
            self.swiftVersion = swiftVersion
            self.httpClient = httpClient
            self.archiver = archiver
            self.useCache = useCache
            self.hostPlatform = hostPlatform
            self.rootCertPath = rootCertPath
        }
    }

    /// Provider of prebuilt binaries for packages. Currently only supports swift-syntax for macros.
    public struct PrebuiltsManager: Cancellable {
        public typealias Delegate = PrebuiltsManagerDelegate

        private let fileSystem: FileSystem
        private let authorizationProvider: AuthorizationProvider?
        private let httpClient: HTTPClient
        private let archiver: Archiver
        private let scratchPath: AbsolutePath
        private let cachePath: AbsolutePath?
        private let delegate: Delegate?
        private let hashAlgorithm: HashAlgorithm = SHA256()
        private let prebuiltsDownloadURL: URL
        private let rootCertPath: AbsolutePath?
        private let customSwiftCompilerVersion: String?
        let hostPlatform: PrebuiltsPlatform

        init(
            fileSystem: FileSystem,
            hostPlatform: PrebuiltsPlatform,
            authorizationProvider: AuthorizationProvider?,
            scratchPath: AbsolutePath,
            cachePath: AbsolutePath?,
            customSwiftCompilerVersion: String?,
            customHTTPClient: HTTPClient?,
            customArchiver: Archiver?,
            delegate: Delegate?,
            prebuiltsDownloadURL: String?,
            rootCertPath: AbsolutePath?
        ) {
            self.fileSystem = fileSystem
            self.hostPlatform = hostPlatform
            self.authorizationProvider = authorizationProvider
            self.httpClient = customHTTPClient ?? HTTPClient()
            self.customSwiftCompilerVersion = customSwiftCompilerVersion

#if os(Linux)
            self.archiver = customArchiver ?? TarArchiver(fileSystem: fileSystem)
#else
            self.archiver = customArchiver ?? ZipArchiver(fileSystem: fileSystem)
#endif

            self.scratchPath = scratchPath
            self.cachePath = cachePath
            self.delegate = delegate
            if let prebuiltsDownloadURL, let url = URL(string: prebuiltsDownloadURL) {
                self.prebuiltsDownloadURL = url
            } else {
                self.prebuiltsDownloadURL = URL(string: "https://download.swift.org/prebuilts")!
            }
            self.rootCertPath = rootCertPath

            self.prebuiltPackages = [
                // TODO: we should have this in a manifest somewhere, not hardcoded like this
                .init(
                    identity: .plain("swift-syntax"),
                    packageRefs: [
                        .init(
                            identity: .plain("swift-syntax"),
                            kind: .remoteSourceControl("https://github.com/swiftlang/swift-syntax.git")
                        ),
                        // The old site that's being redirected but still in use.
                        .init(
                            identity: .plain("swift-syntax"),
                            kind: .remoteSourceControl("https://github.com/apple/swift-syntax.git")
                        ),
                        .init(
                            identity: .plain("swift-syntax"),
                            kind: .remoteSourceControl("git@github.com:swiftlang/swift-syntax.git")
                        ),
                    ]
                ),
            ]
        }

        struct PrebuiltPackage {
            let identity: PackageIdentity
            let packageRefs: [PackageReference]
        }

        private let prebuiltPackages: [PrebuiltPackage]

        fileprivate func findPrebuilts(packages: [PackageReference]) -> [PrebuiltPackage] {
            var prebuilts: [PrebuiltPackage] = []
            for packageRef in packages {
                guard case let .remoteSourceControl(pkgURL) = packageRef.kind else {
                    // Only support remote source control for now
                    continue
                }

                if let prebuilt = prebuiltPackages.first(where: {
                    $0.packageRefs.contains(where: {
                        guard case let .remoteSourceControl(prebuiltURL) = $0.kind,
                              $0.identity == packageRef.identity else {
                            return false
                        }

                        if pkgURL == prebuiltURL {
                            return true
                        } else if !pkgURL.lastPathComponent.hasSuffix(".git") {
                            // try with the git extension
                            // TODO: Does this need to be in the PackageRef Equatable?
                            let gitURL = SourceControlURL(pkgURL.absoluteString + ".git")
                            return gitURL == prebuiltURL
                        } else {
                            return false
                        }
                    })
                }) {
                    prebuilts.append(prebuilt)
                }
            }
            return prebuilts
        }

        func prebuiltName(workspace: Workspace) throws -> String {
            if let customSwiftCompilerVersion {
                return "\(customSwiftCompilerVersion)-\(hostPlatform)"
            } else {
                return try hostPlatform.prebuiltName(hostToolchain: workspace.hostToolchain)
            }

        }

        func downloadManifest(
            workspace: Workspace,
            package: PrebuiltPackage,
            version: Version,
            observabilityScope: ObservabilityScope
        ) async throws -> PrebuiltsManifest? {
            let prebuiltName = try prebuiltName(workspace: workspace)
            let manifestFile = "\(prebuiltName).json"
            let manifestPath = try RelativePath(validating: "\(package.identity)/\(version)/\(manifestFile)")
            let destination = scratchPath.appending(manifestPath)
            let cacheDest = cachePath?.appending(manifestPath)

            func loadManifest() async throws -> PrebuiltsManifest? {
                do {
                    let signedManifest = try JSONDecoder().decode(
                        path: destination,
                        fileSystem: fileSystem,
                        as: SignedPrebuiltsManifest.self
                    )

                    // Check the signature
                    // Ignore errors coming from the certificate loading, that will shutdown the build
                    // instead of letting it continue with build from source.
                    if let rootCertPath {
                        try await withTemporaryDirectory(fileSystem: fileSystem) { tmpDir in
                            try fileSystem.copy(from: rootCertPath, to: tmpDir.appending(rootCertPath.basename))
                            let validator = ManifestSigning(trustedRootCertsDir: tmpDir, observabilityScope: ObservabilitySystem.NOOP)
                            try await validator.validate(
                                manifest: signedManifest.manifest,
                                signature: signedManifest.signature,
                                fileSystem: fileSystem
                            )
                        }.value
                    } else {
                        let validator = ManifestSigning(observabilityScope: ObservabilitySystem.NOOP)
                        try await validator.validate(
                            manifest: signedManifest.manifest,
                            signature: signedManifest.signature,
                            fileSystem: fileSystem
                        )
                    }

                    return signedManifest.manifest
                } catch {
                    // redownload it
                    observabilityScope.emit(
                        info: "Failed to decode prebuilt manifest",
                        underlyingError: error
                    )
                    try fileSystem.removeFileTree(destination)
                    return nil
                }
            }

            // Skip prebuilts if this file exists.
            if let cachePath, fileSystem.exists(cachePath.appending("noprebuilts")) {
                return nil
            }

            if fileSystem.exists(destination), let manifest = try? await loadManifest() {
                return manifest
            } else if let cacheDest, fileSystem.exists(cacheDest) {
                // Pull it out of the cache
                try fileSystem.createDirectory(destination.parentDirectory, recursive: true)
                try fileSystem.copy(from: cacheDest, to: destination)

                if let manifest = try? await loadManifest() {
                    return manifest
                }
            } else if fileSystem.exists(destination.parentDirectory) {
                // We tried previously and were not able to find the manifest.
                // Don't try again to avoid excessive server traffic
                return nil
            }

            try fileSystem.createDirectory(destination.parentDirectory, recursive: true)

            let manifestURL = self.prebuiltsDownloadURL.appending(
                components: package.identity.description, version.description, manifestFile
            )

            if manifestURL.scheme == "file" {
                let sourcePath = try AbsolutePath(validating: manifestURL.path)
                if fileSystem.exists(sourcePath) {
                    // simply copy it over
                    try fileSystem.copy(from: sourcePath, to: destination)
                } else {
                    return nil
                }
            } else {
                var headers = HTTPClientHeaders()
                headers.add(name: "Accept", value: "application/json")
                var request = HTTPClient.Request.download(
                    url: manifestURL,
                    headers: headers,
                    fileSystem: self.fileSystem,
                    destination: destination
                )
                request.options.authorizationProvider =
                self.authorizationProvider?.httpAuthorizationHeader(for:)
                request.options.retryStrategy = .exponentialBackoff(
                    maxAttempts: 3,
                    baseDelay: .milliseconds(50)
                )
                request.options.validResponseCodes = [200]

                do {
                    _ = try await self.httpClient.execute(request) { _, _ in
                        // TODO: send to delegate
                    }
                } catch {
                    observabilityScope.emit(
                        info: "Prebuilt \(manifestFile)",
                        underlyingError: error
                    )
                    // Create an empty manifest so we don't keep trying to download it
                    let manifest = PrebuiltsManifest(libraries: [])
                    try? fileSystem.writeFileContents(destination, data: JSONEncoder().encode(manifest))
                    return nil
                }
            }

            if let manifest = try await loadManifest() {
                // Cache the manifest
                if let cacheDest {
                    if fileSystem.exists(cacheDest) {
                        try fileSystem.removeFileTree(cacheDest)
                    }
                    try fileSystem.createDirectory(cacheDest.parentDirectory, recursive: true)
                    try fileSystem.copy(from: destination, to: cacheDest)
                }

                return manifest
            } else {
                return nil
            }
        }

        func check(path: AbsolutePath, checksum: String) throws -> Bool {
            let contents = try fileSystem.readFileContents(path)
            let hash = hashAlgorithm.hash(contents).hexadecimalRepresentation
            return hash == checksum
        }

        func downloadPrebuilt(
            workspace: Workspace,
            package: PrebuiltPackage,
            version: Version,
            library: PrebuiltsManifest.Library,
            observabilityScope: ObservabilityScope
        ) async throws -> AbsolutePath? {
            let prebuiltName = try prebuiltName(workspace: workspace)
            let artifactName = "\(prebuiltName)-\(library.name)"
            let scratchDir = scratchPath.appending(components: package.identity.description, version.description)

            let artifactDir = scratchDir.appending(artifactName)
            guard !fileSystem.exists(artifactDir) else {
                return artifactDir
            }

            let artifactFile = artifactName + (hostPlatform.os == .linux ? ".tar.gz" : ".zip")
            let destination = scratchDir.appending(artifactFile)
            let cacheFile = cachePath?.appending(components: package.identity.description, version.description, artifactFile)

            let zipExists = fileSystem.exists(destination)
            if try (!zipExists || !check(path: destination, checksum: library.checksum)) {
                try fileSystem.createDirectory(destination.parentDirectory, recursive: true)

                if let cacheFile, fileSystem.exists(cacheFile), try check(path: cacheFile, checksum: library.checksum) {
                    // Copy over the cached file
                    observabilityScope.emit(info: "Using cached \(artifactFile)")
                    try fileSystem.copy(from: cacheFile, to: destination)
                } else {
                    if zipExists {
                        // Exists but failed checksum
                        observabilityScope.emit(info: "Prebuilt artifact \(artifactFile) checksum mismatch, redownloading.")
                        try fileSystem.removeFileTree(destination)
                    }

                    // Download
                    let artifactURL = self.prebuiltsDownloadURL.appending(
                        components: package.identity.description, version.description, artifactFile
                    )

                    let fetchStart = DispatchTime.now()
                    if artifactURL.scheme == "file" {
                        let artifactPath = try AbsolutePath(validating: artifactURL.path)
                        if fileSystem.exists(artifactPath) {
                            self.delegate?.willDownloadPrebuilt(
                                for: package.identity,
                                from: artifactURL.absoluteString,
                                fromCache: true
                            )
                            try fileSystem.copy(from: artifactPath, to: destination)
                            self.delegate?.didDownloadPrebuilt(
                                for: package.identity,
                                from: artifactURL.absoluteString,
                                result: .success((destination, false)),
                                duration: fetchStart.distance(to: .now())
                            )
                        } else {
                            return nil
                        }
                    } else {
                        var headers = HTTPClientHeaders()
                        headers.add(name: "Accept", value: "application/octet-stream")
                        var request = HTTPClient.Request.download(
                            url: artifactURL,
                            headers: headers,
                            fileSystem: self.fileSystem,
                            destination: destination
                        )
                        request.options.authorizationProvider =
                        self.authorizationProvider?.httpAuthorizationHeader(for:)
                        request.options.retryStrategy = .exponentialBackoff(
                            maxAttempts: 3,
                            baseDelay: .milliseconds(50)
                        )
                        request.options.validResponseCodes = [200]

                        self.delegate?.willDownloadPrebuilt(
                            for: package.identity,
                            from: artifactURL.absoluteString,
                            fromCache: false
                        )
                        do {
                            _ = try await self.httpClient.execute(request) {
                                bytesDownloaded,
                                totalBytesToDownload in
                                self.delegate?.downloadingPrebuilt(
                                    for: package.identity,
                                    from: artifactURL.absoluteString,
                                    bytesDownloaded: bytesDownloaded,
                                    totalBytesToDownload: totalBytesToDownload
                                )
                            }
                        } catch {
                            observabilityScope.emit(
                                info: "Prebuilt artifact \(artifactFile)",
                                underlyingError: error
                            )
                            self.delegate?.didDownloadPrebuilt(
                                for: package.identity,
                                from: artifactURL.absoluteString,
                                result: .failure(error),
                                duration: fetchStart.distance(to: .now())
                            )
                            return nil
                        }

                        // Check the checksum
                        if try !check(path: destination, checksum: library.checksum) {
                            let errorString =
                                "Prebuilt artifact \(artifactFile) checksum mismatch"
                            observabilityScope.emit(info: errorString)
                            self.delegate?.didDownloadPrebuilt(
                                for: package.identity,
                                from: artifactURL.absoluteString,
                                result: .failure(StringError(errorString)),
                                duration: fetchStart.distance(to: .now())
                            )
                            return nil
                        }

                        self.delegate?.didDownloadPrebuilt(
                            for: package.identity,
                            from: artifactURL.absoluteString,
                            result: .success((destination, false)),
                            duration: fetchStart.distance(to: .now())
                        )
                    }

                    if let cacheFile {
                        // Cache the zip file
                        if fileSystem.exists(cacheFile) {
                            try fileSystem.removeFileTree(cacheFile)
                        } else {
                            try fileSystem.createDirectory(cacheFile.parentDirectory, recursive: true)
                        }
                        try fileSystem.copy(from: destination, to: cacheFile)
                    }
                }
            }

            // Extract
            if fileSystem.exists(artifactDir) {
                try fileSystem.removeFileTree(artifactDir)
            }
            try fileSystem.createDirectory(artifactDir, recursive: true)
            try await archiver.extract(from: destination, to: artifactDir)

            observabilityScope.emit(
                info: "Prebuilt artifact \(artifactFile) downloaded"
            )

            return artifactDir
        }

        public func cancel(deadline: DispatchTime) throws {
            if let cancellableArchiver = self.archiver as? Cancellable {
                try cancellableArchiver.cancel(deadline: deadline)
            }
        }
    }
}

extension Workspace {
    func updatePrebuilts(
        manifests: DependencyManifests,
        addedOrUpdatedPackages: [PackageReference],
        observabilityScope: ObservabilityScope
    ) async throws {
        guard let prebuiltsManager else {
            // Disabled
            return
        }

        let addedPrebuilts = ManagedPrebuilts()

        for prebuilt in prebuiltsManager.findPrebuilts(packages: try manifests.requiredPackages) {
            guard
                let manifest = manifests.allDependencyManifests[prebuilt.identity],
                let packageVersion = manifest.manifest.version,
                let prebuiltManifest = try await prebuiltsManager
                    .downloadManifest(
                        workspace: self,
                        package: prebuilt,
                        version: packageVersion,
                        observabilityScope: observabilityScope
                    )
            else {
                continue
            }

            let hostPlatform = prebuiltsManager.hostPlatform

            for library in prebuiltManifest.libraries {
                if let path = try await prebuiltsManager
                    .downloadPrebuilt(
                        workspace: self,
                        package: prebuilt,
                        version: packageVersion,
                        library: library,
                        observabilityScope: observabilityScope
                    )
                {
                    // Add to workspace state
                    let checkoutPath = self.location.repositoriesCheckoutsDirectory
                        .appending(component: prebuilt.identity.description)
                    let managedPrebuilt = ManagedPrebuilt(
                        identity: prebuilt.identity,
                        version: packageVersion,
                        libraryName: library.name,
                        path: path,
                        checkoutPath: checkoutPath,
                        products: library.products,
                        includePath: try library.includePath?.map({ try RelativePath(validating: $0) }),
                        cModules: []
                    )
                    addedPrebuilts.add(managedPrebuilt)
                    await self.state.prebuilts.add(managedPrebuilt)
                }
            }
        }

        for prebuilt in await self.state.prebuilts.prebuilts {
            if !addedPrebuilts.contains(where: { $0.identity == prebuilt.identity && $0.version == prebuilt.version }) {
                await self.state.prebuilts.remove(packageIdentity: prebuilt.identity, targetName: prebuilt.libraryName)
            }
        }

        try await self.state.save()
    }
}
