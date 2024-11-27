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
import PackageModel

import struct TSCUtility.Version
import protocol TSCBasic.HashAlgorithm
import struct TSCBasic.SHA256

extension Workspace {
    public enum PrebuiltsPlatform: String, Codable {
        case macos_arm64
        case macos_x86_64
    }

    /// Provider of prebuilt binaries for packages. Currently only supports swift-syntax for macros.
    public struct PrebuiltsManager: Cancellable {
        private let fileSystem: FileSystem
        private let authorizationProvider: AuthorizationProvider?
        private let httpClient: HTTPClient
        private let archiver: Archiver
        private let scratchPath: AbsolutePath
        private let cachePath: AbsolutePath?

        init(
            fileSystem: FileSystem,
            authorizationProvider: AuthorizationProvider?,
            scratchPath: AbsolutePath,
            cachePath: AbsolutePath?
        ) {
            self.fileSystem = fileSystem
            self.authorizationProvider = authorizationProvider
            self.httpClient = HTTPClient() // TODO: mock
            self.archiver = ZipArchiver(fileSystem: fileSystem) // TODO: mock
            self.scratchPath = scratchPath
            self.cachePath = cachePath
        }

        struct PrebuiltPackage {
            let packageRef: PackageReference
            let prebuiltsURL: URL
        }

        private let prebuiltPackages: [PackageReference: PrebuiltPackage] = [
            .init(
                packageRef: .init(identity: .plain("swift-syntax"), kind: .remoteSourceControl(.init("https://github.com/swiftlang/swift-syntax.git"))),
                prebuiltsURL: URL(string: "https://github.com/dschaefer2/swift-syntax/releases/download")!
            ),
            .init(
                packageRef: .init(identity: .plain("swift-syntax"), kind: .remoteSourceControl(.init("https://github.com/swiftlang/swift-syntax"))),
                prebuiltsURL: URL(string: "https://github.com/dschaefer2/swift-syntax/releases/download")!
            ),
        ].reduce(into: .init()) { $0[$1.packageRef] = $1 }

        // Version of the compiler we're building against
        private let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

        fileprivate func findPrebuilts(packages: [PackageReference]) -> [PrebuiltPackage] {
            var prebuilts: [PrebuiltPackage] = []
            for packageRef in packages {
                guard let prebuilt = prebuiltPackages[packageRef] else {
                    continue
                }
                prebuilts.append(prebuilt)
            }
            return prebuilts
        }

        func downloadManifest(
            package: PrebuiltPackage,
            version: Version,
            observabilityScope: ObservabilityScope
        ) async throws -> PrebuiltsManifest? {
            let manifestFile = swiftVersion + "-manifest.json"
            let manifestURL = package.prebuiltsURL.appending(components: version.description, manifestFile)

            // TODO: pull it out of the cache if it's there
            // For now though, always fetch it
            let prebuiltsDir = cachePath ?? scratchPath
            let destination = prebuiltsDir.appending(components: package.packageRef.identity.description, manifestFile)
            if fileSystem.exists(destination) {
                // remove for now so we can overwrite it
                try fileSystem.removeFileTree(destination)
            }
            try fileSystem.createDirectory(destination.parentDirectory, recursive: true)

            var headers = HTTPClientHeaders()
            headers.add(name: "Accept", value: "application/json")
            var request = HTTPClient.Request.download(
                url: manifestURL,
                headers: headers,
                fileSystem: self.fileSystem,
                destination: destination
            )
            request.options.authorizationProvider = self.authorizationProvider?.httpAuthorizationHeader(for:)
            request.options.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
            request.options.validResponseCodes = [200]

            do {
                _ = try await self.httpClient.execute(request) { _, _ in
                    // TODO: send to delegate
                }
            } catch {
                observabilityScope.emit(info: "Prebuilt \(manifestFile)", underlyingError: error)
                return nil
            }

            do {
                return try JSONDecoder().decode(PrebuiltsManifest.self, from: try Data(contentsOf: destination.asURL))
            } catch {
                observabilityScope.emit(info: "Failed to decode prebuilt manifest", underlyingError: error)
                return nil
            }
        }

        func downloadPrebuilt(
            package: PrebuiltPackage,
            version: Version,
            library: PrebuiltsManifest.Library,
            artifact: PrebuiltsManifest.Library.Artifact,
            hashAlgorithm: HashAlgorithm = SHA256(),
            observabilityScope: ObservabilityScope
        ) async throws -> AbsolutePath? {
            let artifactName = swiftVersion + "-" + artifact.platform.rawValue
            let artifactFile = artifactName + ".zip"
            let artifactURL = package.prebuiltsURL.appending(components: version.description, artifactFile)

            // TODO: pull it out of the cache if it's there
            // For now though, always fetch it
            let prebuiltsDir = cachePath ?? scratchPath
            let destination = prebuiltsDir.appending(components: package.packageRef.identity.description, artifactFile)
            if fileSystem.exists(destination) {
                // remove for now so we can overwrite it
                try fileSystem.removeFileTree(destination)
            }
            try fileSystem.createDirectory(destination.parentDirectory, recursive: true)

            // Download
            var headers = HTTPClientHeaders()
            headers.add(name: "Accept", value: "application/octet-stream")
            var request = HTTPClient.Request.download(
                url: artifactURL,
                headers: headers,
                fileSystem: self.fileSystem,
                destination: destination
            )
            request.options.authorizationProvider = self.authorizationProvider?.httpAuthorizationHeader(for:)
            request.options.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
            request.options.validResponseCodes = [200]

            do {
                _ = try await self.httpClient.execute(request) { _, _ in
                    // TODO: send to delegate
                }
            } catch {
                observabilityScope.emit(info: "Prebuilt artifact \(artifactFile)", underlyingError: error)
                return nil
            }

            // Check the checksum
            let contents = try fileSystem.readFileContents(destination)
            let hash = hashAlgorithm.hash(contents).hexadecimalRepresentation
            if hash != artifact.checksum {
                observabilityScope.emit(info: "Prebuilt artifact \(artifactFile) checksum mismatch")
                return nil
            }

            // Copy over to scratch dir if it's not already there
            let scratchDir = scratchPath.appending(package.packageRef.identity.description)
            if scratchPath != cachePath {
                let scratchDest = scratchDir.appending(artifactFile)
                if fileSystem.exists(scratchDest) {
                    try fileSystem.removeFileTree(scratchDest)
                }
                try fileSystem.createDirectory(scratchDir, recursive: true)
                try fileSystem.copy(from: destination, to: scratchDest)
            }

            // Extract
            let artifactDir = scratchDir.appending(artifactName)
            if fileSystem.exists(artifactDir) {
                try fileSystem.removeFileTree(artifactDir)
            }
            try fileSystem.createDirectory(artifactDir, recursive: true)
            try await archiver.extract(from: destination, to: artifactDir)

            observabilityScope.emit(info: "Prebuilt artifact \(artifactFile) downloaded")
            return artifactDir
        }

        public func cancel(deadline: DispatchTime) throws {
        }
    }
}

extension Workspace {
    struct PrebuiltsManifest: Codable {
        let version: Int
        let libraries: [Library]

        struct Library: Codable {
            let name: String
            let products: [String]
            let cModules: [String]
            let artifacts: [Artifact]

            struct Artifact: Codable {
                let platform: PrebuiltsPlatform
                let checksum: String
            }
        }
    }
}

extension Workspace {
    var hostPrebuiltsPlatform: PrebuiltsPlatform? {
        if self.hostToolchain.targetTriple.isDarwin() {
            switch self.hostToolchain.targetTriple.arch {
            case .aarch64:
                return .macos_arm64
            case .x86_64:
                return .macos_x86_64
            default:
                return nil
            }
        } else if self.hostToolchain.targetTriple.isLinux() {
            return nil
        } else {
            return nil
        }
    }

    func updatePrebuilts(
        manifests: DependencyManifests,
        addedOrUpdatedPackages: [PackageReference],
        observabilityScope: ObservabilityScope
    ) async throws {
        for prebuilt in self.prebuiltsManager.findPrebuilts(packages: addedOrUpdatedPackages) {
            guard let manifest = manifests.allDependencyManifests[prebuilt.packageRef.identity],
                  let packageVersion = manifest.manifest.version,
                  let prebuiltManifest = try await self.prebuiltsManager.downloadManifest(
                    package: prebuilt,
                    version: packageVersion,
                    observabilityScope: observabilityScope
                  )
            else {
                continue
            }

            let hostPlatform = hostPrebuiltsPlatform

            for library in prebuiltManifest.libraries {
                for artifact in library.artifacts {
                    guard artifact.platform == hostPlatform else {
                        continue
                    }

                    if let path = try await self.prebuiltsManager.downloadPrebuilt(
                        package: prebuilt,
                        version: packageVersion,
                        library: library,
                        artifact: artifact,
                        observabilityScope: observabilityScope
                    ) {
                        // Add to workspace state
                        let managedPrebuilt = ManagedPrebuilt(
                            packageRef: prebuilt.packageRef,
                            libraryName: library.name,
                            path: path,
                            products: library.products,
                            cModules: library.cModules
                        )
                        self.state.prebuilts.add(managedPrebuilt)
                        try self.state.save()
                    }
                }
            }
        }
    }
}
