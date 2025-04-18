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
    func willDownloadPrebuilt(from url: String, fromCache: Bool)
    /// The workspace has finished downloading a binary artifact.
    func didDownloadPrebuilt(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    )
    /// The workspace is downloading a binary artifact.
    func downloadingPrebuilt(
        from url: String,
        bytesDownloaded: Int64,
        totalBytesToDownload: Int64?
    )
    /// The workspace finished downloading all binary artifacts.
    func didDownloadAllPrebuilts()
}

extension Workspace {
    public struct PrebuiltsManifest: Codable {
        public let version: Int
        public var libraries: [Library]

        public struct Library: Identifiable, Codable {
            public let name: String
            public var products: [String]
            public var cModules: [String]
            public var artifacts: [Artifact]

            public var id: String { name }

            public struct Artifact: Identifiable, Codable {
                public let platform: Platform
                public let checksum: String

                public var id: Platform { platform }

                public init(platform: Platform, checksum: String) {
                    self.platform = platform
                    self.checksum = checksum
                }
            }

            public init(
                name: String,
                products: [String] = [],
                cModules: [String] = [],
                artifacts: [Artifact] = []
            ) {
                self.name = name
                self.products = products
                self.cModules = cModules
                self.artifacts = artifacts
            }
        }

        public init(libraries: [Library] = []) {
            self.version = 1
            self.libraries = libraries
        }

        public enum Platform: String, Codable, CaseIterable {
            case macos_aarch64
            case macos_x86_64
            case windows_aarch64
            case windows_x86_64
            // noble is currently missing
            case ubuntu_jammy_aarch64
            case ubuntu_jammy_x86_64
            case ubuntu_focal_aarch64
            case ubuntu_focal_x86_64
            // bookworm is currently missing
            // fedora39 is currently missing
            case amazonlinux2_aarch64
            case amazonlinux2_x86_64
            case rhel_ubi9_aarch64
            case rhel_ubi9_x86_64

            public enum Arch: String {
                case x86_64
                case aarch64
            }

            public enum OS {
                case macos
                case windows
                case linux
            }

            public var arch: Arch {
                switch self {
                case .macos_aarch64, .windows_aarch64,
                    .ubuntu_jammy_aarch64, .ubuntu_focal_aarch64,
                    .amazonlinux2_aarch64,
                    .rhel_ubi9_aarch64:
                    return .aarch64
                case .macos_x86_64, .windows_x86_64,
                    .ubuntu_jammy_x86_64, .ubuntu_focal_x86_64,
                    .amazonlinux2_x86_64,
                    .rhel_ubi9_x86_64:
                    return .x86_64
                }
            }

            public var os: OS {
                switch self {
                case .macos_aarch64, .macos_x86_64:
                    return .macos
                case .windows_aarch64, .windows_x86_64:
                    return .windows
                case .ubuntu_jammy_aarch64, .ubuntu_jammy_x86_64,
                    .ubuntu_focal_aarch64, .ubuntu_focal_x86_64,
                    .amazonlinux2_aarch64, .amazonlinux2_x86_64,
                    .rhel_ubi9_aarch64, .rhel_ubi9_x86_64:
                    return .linux
                }
            }
        }
    }

    /// For simplified init in tests
    public struct CustomPrebuiltsManager {
        let httpClient: HTTPClient?
        let archiver: Archiver?
        let useCache: Bool?

        public init(
            httpClient: HTTPClient? = .none,
            archiver: Archiver? = .none,
            useCache: Bool? = .none
        ) {
            self.httpClient = httpClient
            self.archiver = archiver
            self.useCache = useCache
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

        init(
            fileSystem: FileSystem,
            authorizationProvider: AuthorizationProvider?,
            scratchPath: AbsolutePath,
            cachePath: AbsolutePath?,
            customHTTPClient: HTTPClient?,
            customArchiver: Archiver?,
            delegate: Delegate?
        ) {
            self.fileSystem = fileSystem
            self.authorizationProvider = authorizationProvider
            self.httpClient = customHTTPClient ?? HTTPClient()
            self.archiver = customArchiver ?? ZipArchiver(fileSystem: fileSystem)
            self.scratchPath = scratchPath
            self.cachePath = cachePath
            self.delegate = delegate
        }

        struct PrebuiltPackage {
            let packageRef: PackageReference
            let prebuiltsURL: URL
        }

        private let prebuiltPackages: [PrebuiltPackage] = [
            .init(
                packageRef: .init(
                    identity: .plain("swift-syntax"),
                    kind: .remoteSourceControl("https://github.com/swiftlang/swift-syntax.git")
                ),
                prebuiltsURL: URL(
                    string:
                        "https://github.com/dschaefer2/swift-syntax/releases/download"
                )!
            ),
        ]

        // Version of the compiler we're building against
        private let swiftVersion =
            "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

        fileprivate func findPrebuilts(packages: [PackageReference])
            -> [PrebuiltPackage]
        {
            var prebuilts: [PrebuiltPackage] = []
            for packageRef in packages {
                guard case let .remoteSourceControl(pkgURL) = packageRef.kind else {
                    // Only support remote source control for now
                    continue
                }

                if let prebuilt = prebuiltPackages.first(where: {
                    guard case let .remoteSourceControl(prebuiltURL) = $0.packageRef.kind,
                        $0.packageRef.identity == packageRef.identity else {
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
                }) {
                    prebuilts.append(prebuilt)
                }
            }
            return prebuilts
        }

        func downloadManifest(
            package: PrebuiltPackage,
            version: Version,
            observabilityScope: ObservabilityScope
        ) async throws -> PrebuiltsManifest? {
            let manifestFile = swiftVersion + "-manifest.json"
            let prebuiltsDir = cachePath ?? scratchPath
            let destination = prebuiltsDir.appending(
                components: package.packageRef.identity.description,
                manifestFile
            )
            if fileSystem.exists(destination) {
                do {
                    return try JSONDecoder().decode(
                        PrebuiltsManifest.self,
                        from: try Data(contentsOf: destination.asURL)
                    )
                } catch {
                    // redownload it
                    observabilityScope.emit(
                        info: "Failed to decode prebuilt manifest",
                        underlyingError: error
                    )
                    try fileSystem.removeFileTree(destination)
                }
            }
            try fileSystem.createDirectory(
                destination.parentDirectory,
                recursive: true
            )

            let manifestURL = package.prebuiltsURL.appending(
                components: version.description,
                manifestFile
            )
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
                return nil
            }

            do {
                let data = try fileSystem.readFileContents(destination)
                return try JSONDecoder().decode(
                    PrebuiltsManifest.self,
                    from: Data(data.contents)
                )
            } catch {
                observabilityScope.emit(
                    info: "Failed to decode prebuilt manifest",
                    underlyingError: error
                )
                return nil
            }
        }

        func check(path: AbsolutePath, checksum: String) throws -> Bool {
            let contents = try fileSystem.readFileContents(path)
            let hash = hashAlgorithm.hash(contents).hexadecimalRepresentation
            return hash == checksum
        }

        func downloadPrebuilt(
            package: PrebuiltPackage,
            version: Version,
            library: PrebuiltsManifest.Library,
            artifact: PrebuiltsManifest.Library.Artifact,
            observabilityScope: ObservabilityScope
        ) async throws -> AbsolutePath? {
            let artifactName =
                "\(swiftVersion)-\(library.name)-\(artifact.platform.rawValue)"
            let scratchDir = scratchPath.appending(
                package.packageRef.identity.description
            )
            let artifactDir = scratchDir.appending(artifactName)
            guard !fileSystem.exists(artifactDir) else {
                return artifactDir
            }

            let artifactFile = artifactName + ".zip"
            let prebuiltsDir = cachePath ?? scratchPath
            let destination = prebuiltsDir.appending(
                components: package.packageRef.identity.description,
                artifactFile
            )

            let zipExists = fileSystem.exists(destination)
            if try (!zipExists || !check(path: destination, checksum: artifact.checksum)) {
                if zipExists {
                    observabilityScope.emit(info: "Prebuilt artifact \(artifactFile) checksum mismatch, redownloading.")
                    try fileSystem.removeFileTree(destination)
                }

                try fileSystem.createDirectory(
                    destination.parentDirectory,
                    recursive: true
                )

                // Download
                let artifactURL = package.prebuiltsURL.appending(
                    components: version.description,
                    artifactFile
                )
                let fetchStart = DispatchTime.now()
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
                    from: artifactURL.absoluteString,
                    fromCache: false
                )
                do {
                    _ = try await self.httpClient.execute(request) {
                        bytesDownloaded,
                        totalBytesToDownload in
                        self.delegate?.downloadingPrebuilt(
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
                        from: artifactURL.absoluteString,
                        result: .failure(error),
                        duration: fetchStart.distance(to: .now())
                    )
                    return nil
                }

                // Check the checksum
                if try !check(path: destination, checksum: artifact.checksum) {
                    let errorString =
                        "Prebuilt artifact \(artifactFile) checksum mismatch"
                    observabilityScope.emit(info: errorString)
                    self.delegate?.didDownloadPrebuilt(
                        from: artifactURL.absoluteString,
                        result: .failure(StringError(errorString)),
                        duration: fetchStart.distance(to: .now())
                    )
                    return nil
                }

                self.delegate?.didDownloadPrebuilt(
                    from: artifactURL.absoluteString,
                    result: .success((destination, false)),
                    duration: fetchStart.distance(to: .now())
                )
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
        guard let prebuiltsManager = self.prebuiltsManager else {
            // Disabled
            return
        }

        for prebuilt in prebuiltsManager.findPrebuilts(
            packages: try manifests.requiredPackages
        ) {
            guard
                let manifest = manifests.allDependencyManifests[
                    prebuilt.packageRef.identity
                ],
                let packageVersion = manifest.manifest.version,
                let prebuiltManifest = try await prebuiltsManager
                    .downloadManifest(
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

                    if let path = try await prebuiltsManager
                        .downloadPrebuilt(
                            package: prebuilt,
                            version: packageVersion,
                            library: library,
                            artifact: artifact,
                            observabilityScope: observabilityScope
                        )
                    {
                        // Add to workspace state
                        let managedPrebuilt = ManagedPrebuilt(
                            packageRef: prebuilt.packageRef,
                            libraryName: library.name,
                            path: path,
                            products: library.products,
                            cModules: library.cModules
                        )
                        await self.state.prebuilts.add(managedPrebuilt)
                        try await self.state.save()
                    }
                }
            }
        }
    }

    var hostPrebuiltsPlatform: PrebuiltsManifest.Platform? {
        if self.hostToolchain.targetTriple.isDarwin() {
            switch self.hostToolchain.targetTriple.arch {
            case .aarch64:
                return .macos_aarch64
            case .x86_64:
                return .macos_x86_64
            default:
                return nil
            }
        } else if self.hostToolchain.targetTriple.isWindows() {
            switch self.hostToolchain.targetTriple.arch {
            case .aarch64:
                return .windows_aarch64
            case .x86_64:
                return .windows_x86_64
            default:
                return nil
            }
        } else if self.hostToolchain.targetTriple.isLinux() {
            // Load up the os-release file into a dictionary
            guard let osData = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)
            else {
                return nil
            }
            let osLines = osData.split(separator: "\n")
            let osDict = osLines.reduce(into: [Substring: String]()) {
                (dict, line) in
                let parts = line.split(separator: "=", maxSplits: 2)
                dict[parts[0]] = parts[1...].joined(separator: "=").trimmingCharacters(in: ["\""])
            }

            switch osDict["ID"] {
            case "ubuntu":
                switch osDict["VERSION_CODENAME"] {
                case "jammy":
                    switch self.hostToolchain.targetTriple.arch {
                    case .aarch64:
                        return .ubuntu_jammy_aarch64
                    case .x86_64:
                        return .ubuntu_jammy_x86_64
                    default:
                        return nil
                    }
                case "focal":
                    switch self.hostToolchain.targetTriple.arch {
                    case .aarch64:
                        return .ubuntu_focal_aarch64
                    case .x86_64:
                        return .ubuntu_focal_x86_64
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            case "amzn":
                switch osDict["VERSION_ID"] {
                case "2":
                    switch self.hostToolchain.targetTriple.arch {
                    case .aarch64:
                        return .amazonlinux2_aarch64
                    case .x86_64:
                        return .amazonlinux2_x86_64
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            case "rhel":
                guard let version = osDict["VERSION_ID"] else {
                    return nil
                }
                switch version.split(separator: ".")[0] {
                case "9":
                    switch self.hostToolchain.targetTriple.arch {
                    case .aarch64:
                        return .rhel_ubi9_aarch64
                    case .x86_64:
                        return .rhel_ubi9_x86_64
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            default:
                return nil
            }
        } else {
            return nil
        }
    }

}
