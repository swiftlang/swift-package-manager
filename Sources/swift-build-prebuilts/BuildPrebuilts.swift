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

/// Checkout supported versions of the prebuilts, build them, package up the zip and update the manifest file.

// Ideally this would be a script, however until we have package dependencies
// for scripts, this will need to be a part of the package. But this is why it's
// reading like a script

import ArgumentParser
import Basics
import Foundation
import PackageModel
import struct TSCBasic.ByteString
import struct TSCBasic.SHA256
import Workspace

// Format for the .zip.json files.
struct Artifact: Codable {
    var platform: Workspace.PrebuiltsManifest.Platform
    var checksum: String
    var libraryName: String?
    var products: [String]?
    var includePath: [String]?
    var cModules: [String]? // deprecated, includePath is the way forward
    var swiftVersion: String?
}

@main
struct BuildPrebuilts: AsyncParsableCommand {
    @Option(help: "The directory to generate the artifacts to.")
    var stageDir = try! AbsolutePath(validating: FileManager.default.currentDirectoryPath).appending("stage")

    @Option(name: .customLong("version"), help: "swift-syntax versions to build. Multiple are allowed.")
    var versions: [String] = ["600.0.1", "601.0.1"]

    @Flag(help: "Whether to build the prebuilt artifacts")
    var build = false

    @Flag(help: "Whether to sign the manifest")
    var sign = false

    @Option(name: .customLong("private-key-path"), help: "The path to certificate's private key (PEM encoded)")
    var privateKeyPathStr: String?

    @Option(name: .customLong("cert-chain-path"), help: "Path to a certificate (DER encoded) in the chain. The certificate used for signing must be first and the root certificate last.")
    var certChainPathStrs: [String] = []

    @Option(help: .hidden)
    var prebuiltsUrl: String = "https://download.swift.org/prebuilts"

    @Flag(help: .hidden)
    var testSigning: Bool = false

    func validate() throws {
        if sign && !testSigning {
            guard privateKeyPathStr != nil else {
                throw ValidationError("No private key path provided")
            }

            guard !certChainPathStrs.isEmpty else {
                throw ValidationError("No certificates provided")
            }
        }

        if !build && !sign && !testSigning {
            throw ValidationError("Requires one of --build or --sign or both")
        }
    }

    func computeSwiftVersion() throws -> String? {
        let fileSystem = localFileSystem

        let environment = Environment.current
        let hostToolchain = try UserToolchain(
            swiftSDK: SwiftSDK.hostSwiftSDK(
                environment: environment,
                fileSystem: fileSystem
            ),
            environment: environment
        )

        return hostToolchain.swiftCompilerVersion
    }

    mutating func run() async throws {
        if build {
            try await build()
        }

        if sign || testSigning {
            try await sign()
        }
    }

    mutating func build() async throws {
        let fileSystem = localFileSystem
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let swiftVersion = try computeSwiftVersion() else {
            print("Unable to determine swift compiler version")
            return
        }

        print("Stage directory: \(stageDir)")

        let srcDir = stageDir.appending("src")
        let libDir = stageDir.appending("lib")
        let modulesDir = stageDir.appending("Modules")

        if fileSystem.exists(srcDir) {
            try fileSystem.removeFileTree(srcDir)
        }
        try fileSystem.createDirectory(srcDir, recursive: true)

        if fileSystem.exists(libDir) {
            try fileSystem.removeFileTree(libDir)
        }

        if fileSystem.exists(modulesDir) {
            try fileSystem.removeFileTree(modulesDir)
        }

        let id = "swift-syntax"
        let libraryName = "MacroSupport"
        let repoDir = srcDir.appending(id)
        let scratchDir = repoDir.appending(".build")
        let buildDir = scratchDir.appending("release")
        let srcModulesDir = buildDir.appending("Modules")
        let prebuiltDir = stageDir.appending(id)

        try await shell("git clone https://github.com/swiftlang/swift-syntax.git", cwd: srcDir)

        for version in versions {
            let versionDir = prebuiltDir.appending(version)
            if !fileSystem.exists(versionDir) {
                try fileSystem.createDirectory(versionDir, recursive: true)
            }

            try await shell("git checkout \(version)", cwd: repoDir)

            // Update package with the libraries
            let packageFile = repoDir.appending(component: "Package.swift")
            let workspace = try Workspace(fileSystem: fileSystem, location: .init(forRootPackage: repoDir, fileSystem: fileSystem))
            let package = try await workspace.loadRootPackage(
                at: repoDir,
                observabilityScope: ObservabilitySystem { _, diag in print(diag) }.topScope
            )

            // Gather the list of targets for the package products
            let libraryTargets = package.targets(forPackage: package)

            var packageContents = try String(contentsOf: packageFile.asURL)
            packageContents += """
                    package.products += [
                        .library(name: "\(libraryName)", type: .static, targets: [
                            \(libraryTargets.map({ "\"\($0.name)\"" }).joined(separator: ","))
                        ])
                    ]
                    """
            try packageContents.write(to: packageFile.asURL, atomically: true, encoding: .utf8)

            // Build
            let cModules = libraryTargets.compactMap({ $0 as? ClangModule })

            for platform in Workspace.PrebuiltsManifest.Platform.allCases {
                guard canBuild(platform) else {
                    continue
                }

                try fileSystem.createDirectory(libDir, recursive: true)
                try fileSystem.createDirectory(modulesDir, recursive: true)

                // Clean out the scratch dir
                if fileSystem.exists(scratchDir) {
                    try fileSystem.removeFileTree(scratchDir)
                }

                // Build
                let cmd = "swift build -c release -debug-info-format none --arch \(platform.arch) --product \(libraryName)"
                try await shell(cmd, cwd: repoDir)

                // Copy the library to staging
                let lib = "lib\(libraryName).a"
                try fileSystem.copy(from: buildDir.appending(lib), to: libDir.appending(lib))

                // Copy the swiftmodules
                for file in try fileSystem.getDirectoryContents(srcModulesDir) {
                    try fileSystem.copy(from: srcModulesDir.appending(file), to: modulesDir.appending(file))
                }

                // Zip it up
                let contentDirs = ["lib", "Modules"]
#if os(Windows)
                let zipFile = versionDir.appending("\(swiftVersion)-\(libraryName)-\(platform).zip")
                try await shell("tar -acf \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                let contents = try ByteString(Data(contentsOf: zipFile.asURL))
#elseif os(Linux)
                let tarFile = versionDir.appending("\(swiftVersion)-\(libraryName)-\(platform).tar.gz")
                try await shell("tar -zcf \(tarFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                let contents = try ByteString(Data(contentsOf: tarFile.asURL))
#else
                let zipFile = versionDir.appending("\(swiftVersion)-\(libraryName)-\(platform).zip")
                try await shell("zip -r \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                let contents = try ByteString(Data(contentsOf: zipFile.asURL))
#endif

                // Manifest fragment for the zip file
                let checksum = SHA256().hash(contents).hexadecimalRepresentation
                let artifact = Artifact(
                    platform: platform,
                    checksum: checksum,
                    libraryName: libraryName,
                    products: package.products.map(\.name),
                    includePath: cModules.map({ $0.includeDir.relative(to: repoDir ).pathString.replacingOccurrences(of: "\\", with: "/") }),
                    swiftVersion: swiftVersion
                )

                let artifactJsonFile = versionDir.appending("\(swiftVersion)-\(libraryName)-\(platform).zip.json")
                try fileSystem.writeFileContents(artifactJsonFile, data: encoder.encode(artifact))

                // Clean up
                try fileSystem.removeFileTree(libDir)
                try fileSystem.removeFileTree(modulesDir)
            }

            try await shell("git restore .", cwd: repoDir)
        }

        try fileSystem.changeCurrentWorkingDirectory(to: stageDir)
        try fileSystem.removeFileTree(srcDir)
    }

    mutating func sign() async throws {
        let fileSystem = localFileSystem
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let decoder = JSONDecoder()

        let httpClient = HTTPClient()

        guard let swiftVersion = try computeSwiftVersion() else {
            print("Unable to determine swift compiler version")
            _exit(1)
        }

        let id = "swift-syntax"
        let prebuiltDir = stageDir.appending(id)
        for version in try fileSystem.getDirectoryContents(prebuiltDir) {
            let versionDir = prebuiltDir.appending(version)

            // Load artifacts
            let artifacts = try fileSystem.getDirectoryContents(versionDir)
                .filter({ $0.hasSuffix(".zip.json") })
                .map {
                    let data: Data = try fileSystem.readFileContents(versionDir.appending($0))
                    var artifact = try decoder.decode(Artifact.self, from: data)
                    if artifact.swiftVersion == nil || artifact.libraryName == nil {
                        let regex = try Regex(#"(.+)-([^-]+)-[^-]+.zip.json"#)
                        if let match = try regex.firstMatch(in: $0),
                           match.count > 2,
                           let swiftVersion = match[1].substring,
                           let libraryName = match[2].substring
                        {
                            artifact.swiftVersion = .init(swiftVersion)
                            artifact.libraryName = .init(libraryName)
                        }
                    }
                    return artifact
                }

            // Fetch manifests for requested swift versions
            let swiftVersions: Set<String> = .init(artifacts.compactMap(\.swiftVersion))
            var manifests: [String: Workspace.PrebuiltsManifest] = [:]
            for swiftVersion in swiftVersions {
                let manifestFile = "\(swiftVersion)-manifest.json"
                let destination = versionDir.appending(component: manifestFile)
                if fileSystem.exists(destination) {
                    let signedManifest = try decoder.decode(
                        path: destination,
                        fileSystem: fileSystem,
                        as: Workspace.SignedPrebuiltsManifest.self
                    )
                    manifests[swiftVersion] = signedManifest.manifest
                } else {
                    let manifestURL = URL(string: prebuiltsUrl)?.appending(components: id, version, manifestFile)
                    guard let manifestURL else {
                        print("Invalid URL \(prebuiltsUrl)")
                        _exit(1)
                    }

                    var headers = HTTPClientHeaders()
                    headers.add(name: "Accept", value: "application/json")
                    var request = HTTPClient.Request.download(
                        url: manifestURL,
                        headers: headers,
                        fileSystem: fileSystem,
                        destination: destination
                    )
                    request.options.retryStrategy = .exponentialBackoff(
                        maxAttempts: 3,
                        baseDelay: .milliseconds(50)
                    )
                    request.options.validResponseCodes = [200]

                    do {
                        _ = try await httpClient.execute(request) { _, _ in }
                    } catch {
                        manifests[swiftVersion] = .init()
                        continue
                    }

                    let signedManifest = try decoder.decode(
                        path: destination,
                        fileSystem: fileSystem,
                        as: Workspace.SignedPrebuiltsManifest.self
                    )

                    manifests[swiftVersion] = signedManifest.manifest
                }
            }

            // Merge in the artifacts
            for artifact in artifacts {
                let swiftVersion = artifact.swiftVersion ?? swiftVersion
                guard var manifest = manifests[swiftVersion] else {
                    continue
                }
                let libraryName = artifact.libraryName ?? manifest.libraries[0].name
                var library = manifest.libraries.first(where: { $0.name == libraryName }) ?? .init(name: libraryName)
                var newArtifacts = library.artifacts ?? []

                if let products = artifact.products {
                    library.products = products
                }

                if let includePath = artifact.includePath {
                    library.includePath = includePath
                }

                if let cModules = artifact.cModules {
                    library.cModules = cModules
                }

                if let index = newArtifacts.firstIndex(where: { $0.platform == artifact.platform }) {
                    var oldArtifact = newArtifacts[index]
                    oldArtifact.checksum = artifact.checksum
                    newArtifacts[index] = oldArtifact
                } else {
                    newArtifacts.append(.init(platform: artifact.platform, checksum: artifact.checksum))
                }

                library.artifacts = newArtifacts

                if let index = manifest.libraries.firstIndex(where: { $0.name == libraryName }) {
                    manifest.libraries[index] = library
                } else {
                    manifest.libraries.append(library)
                }

                manifests[swiftVersion] = manifest
            }

            if testSigning {
                // Use SwiftPM's test certificate chain and private key for testing
                let certsPath = try AbsolutePath(validating: #file)
                    .parentDirectory.parentDirectory.parentDirectory
                    .appending(components: "Fixtures", "Signing", "Certificates")
                privateKeyPathStr = certsPath.appending("Test_rsa_key.pem").pathString
                certChainPathStrs = [
                    certsPath.appending("Test_rsa.cer").pathString,
                    certsPath.appending("TestIntermediateCA.cer").pathString,
                    certsPath.appending("TestRootCA.cer").pathString
                ]
            }

            guard let privateKeyPathStr else {
                fatalError("No private key path provided")
            }

            let certChainPaths = try certChainPathStrs.map { try make(path: $0) }

            guard let rootCertPath = certChainPaths.last else {
                fatalError("No certificates provided")
            }

            let privateKeyPath = try make(path: privateKeyPathStr)

            try await withTemporaryDirectory { tmpDir in
                try fileSystem.copy(from: rootCertPath, to: tmpDir.appending(rootCertPath.basename))

                let signer = ManifestSigning(
                    trustedRootCertsDir: tmpDir,
                    observabilityScope: ObservabilitySystem { _, diagnostic in print(diagnostic) }.topScope
                )

                for (swiftVersion, manifest) in manifests where !manifest.libraries.flatMap({ $0.artifacts ?? [] }).isEmpty {
                    let signature = try await signer.sign(
                        manifest: manifest,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath,
                        fileSystem: fileSystem
                    )

                    let signedManifest = Workspace.SignedPrebuiltsManifest(manifest: manifest, signature: signature)
                    let manifestFile = versionDir.appending(component: "\(swiftVersion)-manifest.json")
                    try encoder.encode(signedManifest).write(to: manifestFile.asURL)
                }
            }
        }
    }

    func canBuild(_ platform: Workspace.PrebuiltsManifest.Platform) -> Bool {
#if os(macOS)
        return platform.os == .macos
#elseif os(Windows)
        return platform.os == .windows
#elseif os(Linux)
        return platform == Workspace.PrebuiltsManifest.Platform.hostPlatform
#else
        return false
#endif
    }

    func make(path: String) throws -> AbsolutePath {
        if let path = try? AbsolutePath(validating: path) {
            // It's already absolute
            return path
        }

        return try AbsolutePath(validating: FileManager.default.currentDirectoryPath)
            .appending(RelativePath(validating: path))
    }

}

func shell(_ command: String, cwd: AbsolutePath) async throws {
    _ = FileManager.default.changeCurrentDirectoryPath(cwd.pathString)

#if os(Windows)
    let arguments = ["C:\\Windows\\System32\\cmd.exe", "/c", command]
#else
    let arguments = ["/bin/bash", "-c", command]
#endif
    let process = AsyncProcess(
        arguments: arguments,
        outputRedirection: .none
    )
    print("Running:", command)
    try process.launch()
    let result = try await process.waitUntilExit()
    switch result.exitStatus {
    case .terminated(code: let code):
        if code != 0 {
            throw StringError("Command exited with code \(code): \(command)")
        }
#if os(Windows)
    case .abnormal(exception: let exception):
        throw StringError("Command threw exception \(exception): \(command)")
#else
    case .signalled(signal: let signal):
        throw StringError("Command exited on signal \(signal): \(command)")
#endif
    }
}

extension Workspace.PrebuiltsManifest.Platform {
    var dockerTag: String? {
        switch self {
        case .ubuntu_jammy_aarch64, .ubuntu_jammy_x86_64:
            return "jammy"
        case .ubuntu_focal_aarch64, .ubuntu_focal_x86_64:
            return "focal"
        case .rhel_ubi9_aarch64, .rhel_ubi9_x86_64:
            return "rhel-ubi9"
        case .amazonlinux2_aarch64, .amazonlinux2_x86_64:
            return "amazonlinux2"
        default:
            return nil
        }
    }
}

extension Workspace.PrebuiltsManifest.Platform.Arch {
    var dockerPlatform: String? {
        switch self {
        case .aarch64:
            return "linux/arm64"
        case .x86_64:
            return "linux/amd64"
        }
    }
}

extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        try? self.init(validating: argument)
    }
}

extension Package {
    /// The transitive list of targets in this package for the given list of products
    func targets(forPackage package: Package) -> [Module] {
        var targets: [String: Module] = [:]
        for product in package.products where product.type.isLibrary {
            for target in product.modules {
                if !targets.keys.contains(target.name) {
                    func transitTarget(_ target: Module) {
                        for dep in target.dependencies {
                            switch dep {
                            case .module(let module, conditions: _):
                                if !targets.keys.contains(module.name) {
                                    targets[module.name] = module
                                    transitTarget(module)
                                }
                            default:
                                break
                            }
                        }
                    }

                    targets[target.name] = target
                    transitTarget(target)
                }
            }
        }
        return Array(targets.values)
    }
}
