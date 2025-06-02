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

struct PrebuiltRepos: Codable {
    let url: URL
    let versions: [Version]

    struct Version: Identifiable, Codable {
        let tag: String
        let manifest: Workspace.PrebuiltsManifest

        var id: String { tag }
    }
}

var prebuiltRepos: [PrebuiltRepos] = [
    .init(
        url: .init(string: "https://github.com/swiftlang/swift-syntax")!,
        versions: [
            .init(
                tag:"600.0.1",
                manifest: .init(libraries: [
                    .init(
                        name: "MacroSupport",
                        products: [
                            "SwiftBasicFormat",
                            "SwiftCompilerPlugin",
                            "SwiftDiagnostics",
                            "SwiftIDEUtils",
                            "SwiftOperators",
                            "SwiftParser",
                            "SwiftParserDiagnostics",
                            "SwiftRefactor",
                            "SwiftSyntax",
                            "SwiftSyntaxBuilder",
                            "SwiftSyntaxMacros",
                            "SwiftSyntaxMacroExpansion",
                            "SwiftSyntaxMacrosTestSupport",
                            "SwiftSyntaxMacrosGenericTestSupport",
                            "_SwiftCompilerPluginMessageHandling",
                            "_SwiftLibraryPluginProvider",
                        ]
                    ),
                ])
            ),
            .init(
                tag:"601.0.1",
                manifest: .init(libraries: [
                    .init(
                        name: "MacroSupport",
                        products: [
                            "SwiftBasicFormat",
                            "SwiftCompilerPlugin",
                            "SwiftDiagnostics",
                            "SwiftIDEUtils",
                            "SwiftIfConfig",
                            "SwiftLexicalLookup",
                            "SwiftOperators",
                            "SwiftParser",
                            "SwiftParserDiagnostics",
                            "SwiftRefactor",
                            "SwiftSyntax",
                            "SwiftSyntaxBuilder",
                            "SwiftSyntaxMacros",
                            "SwiftSyntaxMacroExpansion",
                            "SwiftSyntaxMacrosTestSupport",
                            "SwiftSyntaxMacrosGenericTestSupport",
                            "_SwiftCompilerPluginMessageHandling",
                            "_SwiftLibraryPluginProvider",
                        ]
                    ),
                ])
            ),
        ]
    ),
]

@main
struct BuildPrebuilts: AsyncParsableCommand {
    @Option(help: "The directory to generate the artifacts to.")
    var stageDir = try! AbsolutePath(validating: FileManager.default.currentDirectoryPath).appending("stage")

    @Option(help: "The config file used to determine the prebuilts to build")
    var config = try! AbsolutePath(validating: #file).parentDirectory.appending("config.json")

    @Flag(help: "Whether to build the prebuilt artifacts")
    var build = false

    @Flag(help: "Whether to sign the manifest")
    var sign = false

    @Option(name: .customLong("private-key-path"), help: "The path to certificate's private key (PEM encoded)")
    var privateKeyPathStr: String?

    @Option(name: .customLong("cert-chain-path"), help: "Path to a certificate (DER encoded) in the chain. The certificate used for signing must be first and the root certificate last.")
    var certChainPathStrs: [String] = []

    @Flag(help: .hidden)
    var testSigning: Bool = false

    @Flag(name: .customLong("include-path"), help: "Add includePath to manifest")
    var addIncludePath: Bool = false

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

    @Flag(help: "Whether to build the prebuilt artifacts")
    var build = false

    @Flag(help: "Whether to sign the manifest")
    var sign = false

    @Option(name: .customLong("private-key-path"), help: "The path to certificate's private key (PEM encoded)")
    var privateKeyPathStr: String?

    @Option(name: .customLong("cert-chain-path"), help: "Path to a certificate (DER encoded) in the chain. The certificate used for signing must be first and the root certificate last.")
    var certChainPathStrs: [String] = []

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
        let includesDir = stageDir.appending("include")

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

        if fileSystem.exists(includesDir) {
            try fileSystem.removeFileTree(includesDir)
        }

        for repo in prebuiltRepos {
            let repoDir = srcDir.appending(repo.url.lastPathComponent)
            let scratchDir = repoDir.appending(".build")
            let buildDir = scratchDir.appending("release")
            let srcModulesDir = buildDir.appending("Modules")
            let prebuiltDir = stageDir.appending(repo.url.lastPathComponent)

            try await shell("git clone \(repo.url)", cwd: srcDir)

            for version in repo.versions {
                let versionDir = prebuiltDir.appending(version.tag)
                if !fileSystem.exists(versionDir) {
                    try fileSystem.createDirectory(versionDir, recursive: true)
                }

                try await shell("git checkout \(version.tag)", cwd: repoDir)

                // Update package with the libraries
                let packageFile = repoDir.appending(component: "Package.swift")
                let workspace = try Workspace(fileSystem: fileSystem, location: .init(forRootPackage: repoDir, fileSystem: fileSystem))
                let package = try await workspace.loadRootPackage(
                    at: repoDir,
                    observabilityScope: ObservabilitySystem { _, diag in print(diag) }.topScope
                )

                // Gather the list of targets for the libraries' products
                let libraryTargets: [String: [Module]] = version.manifest.libraries.reduce(into: [:]) {
                    $0[$1.name] = package.targets(forProducts: $1.products)
                }

                var packageContents = try String(contentsOf: packageFile.asURL)
                for (library, targets) in libraryTargets {
                    packageContents += """
                        package.products += [
                            .library(name: "\(library)", type: .static, targets: [
                                \(targets.map({ "\"\($0.name)\"" }).joined(separator: ","))
                            ])
                        ]
                        """
                }
                try packageContents.write(to: packageFile.asURL, atomically: true, encoding: .utf8)

                var newLibraries: [Workspace.PrebuiltsManifest.Library] = []

                // Build
                for library in version.manifest.libraries {
                    let cModules = libraryTargets[library.name]?.compactMap({ $0 as? ClangModule }) ?? []

                    for platform in Workspace.PrebuiltsManifest.Platform.allCases {
                        guard canBuild(platform) else {
                            continue
                        }

                        try fileSystem.createDirectory(libDir, recursive: true)
                        try fileSystem.createDirectory(modulesDir, recursive: true)
                        try fileSystem.createDirectory(includesDir, recursive: true)

                        // Clean out the scratch dir
                        if fileSystem.exists(scratchDir) {
                            try fileSystem.removeFileTree(scratchDir)
                        }

                        // Build
                        let cmd = "swift build -c release -debug-info-format none --arch \(platform.arch) --product \(library.name)"
                        try await shell(cmd, cwd: repoDir)

                        // Copy the library to staging
                        let lib = "lib\(library.name).a"
                        try fileSystem.copy(from: buildDir.appending(lib), to: libDir.appending(lib))

                        // Copy the swiftmodules
                        for file in try fileSystem.getDirectoryContents(srcModulesDir) {
                            try fileSystem.copy(from: srcModulesDir.appending(file), to: modulesDir.appending(file))
                        }

                        // Do a deep copy of the C module headers
                        for cModule in cModules {
                            let srcIncludeDir = cModule.includeDir
                            let destIncludeDir = includesDir.appending(cModule.name)

                            try fileSystem.createDirectory(destIncludeDir, recursive: true)
                            try fileSystem.enumerate(directory: srcIncludeDir) { srcPath in
                                let destPath = destIncludeDir.appending(srcPath.relative(to: srcIncludeDir))
                                try fileSystem.createDirectory(destPath.parentDirectory)
                                try fileSystem.copy(from: srcPath, to: destPath)
                            }
                        }

                        // Zip it up
                        let contentDirs = ["lib", "Modules"] + (cModules.isEmpty ? [] : ["include"])
#if os(Windows)
                        let zipFile = versionDir.appending("\(swiftVersion)-\(library.name)-\(platform).zip")
                        try await shell("tar -acf \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                        let contents = try ByteString(Data(contentsOf: zipFile.asURL))
#elseif os(Linux)
                        let tarFile = versionDir.appending("\(swiftVersion)-\(library.name)-\(platform).tar.gz")
                        try await shell("tar -zcf \(tarFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                        let contents = try ByteString(Data(contentsOf: tarFile.asURL))
#else
                        let zipFile = versionDir.appending("\(swiftVersion)-\(library.name)-\(platform).zip")
                        try await shell("zip -r \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                        let contents = try ByteString(Data(contentsOf: zipFile.asURL))
#endif

                        let checksum = SHA256().hash(contents).hexadecimalRepresentation
                        let artifact: Workspace.PrebuiltsManifest.Library.Artifact =
                            .init(platform: platform, checksum: checksum)

                        let artifactJsonFile = versionDir.appending("\(swiftVersion)-\(library.name)-\(platform).zip.json")
                        try fileSystem.writeFileContents(artifactJsonFile, data: encoder.encode(artifact))

                        try fileSystem.removeFileTree(libDir)
                        try fileSystem.removeFileTree(modulesDir)
                        try fileSystem.removeFileTree(includesDir)
                    }

                    let decoder = JSONDecoder()
                    let newLibrary = Workspace.PrebuiltsManifest.Library(
                        name: library.name,
                        products: library.products,
                        cModules: cModules.map({ $0.name }),
                        includePath: addIncludePath ? cModules.map({ $0.includeDir.relative(to: repoDir ) }) : nil,
                    )
                    newLibraries.append(newLibrary)

                    try await shell("git restore .", cwd: repoDir)
                }

                let manifest = Workspace.PrebuiltsManifest(libraries: newLibraries)
                let manifestFile = versionDir.appending("\(swiftVersion)-prebuilts.json")
                try fileSystem.writeFileContents(manifestFile, data: encoder.encode(manifest))
            }
        }

        try fileSystem.changeCurrentWorkingDirectory(to: stageDir)
        try fileSystem.removeFileTree(srcDir)
    }

    mutating func sign() async throws {
        let fileSystem = localFileSystem
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let decoder = JSONDecoder()

        guard let swiftVersion = try computeSwiftVersion() else {
            print("Unable to determine swift compiler version")
            return
        }

        for repo in prebuiltRepos {
            let prebuiltDir = stageDir.appending(repo.url.lastPathComponent)
            for version in repo.versions {
                let versionDir = prebuiltDir.appending(version.tag)
                let prebuiltsFile = versionDir.appending("\(swiftVersion)-prebuilts.json")
                let manifestFile = versionDir.appending("\(swiftVersion)-manifest.json")

                // Load generated manifest
                let manifestContents: Data = try fileSystem.readFileContents(prebuiltsFile)
                var manifest = try decoder.decode(Workspace.PrebuiltsManifest.self, from: manifestContents)
                manifest.libraries = try manifest.libraries.map({
                    var library = $0
                    library.artifacts = try fileSystem.getDirectoryContents(versionDir)
                        .filter({ $0.hasSuffix(".zip.json")})
                        .compactMap({
                            let data: Data = try fileSystem.readFileContents(versionDir.appending($0))
                            return try? decoder.decode(Workspace.PrebuiltsManifest.Library.Artifact.self, from: data)
                        })
                    return library
                })

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

                    let signature = try await signer.sign(
                        manifest: manifest,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath,
                        fileSystem: fileSystem
                    )

                    let signedManifest = Workspace.SignedPrebuiltsManifest(manifest: manifest, signature: signature)
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
    func targets(forProducts productNames: [String]) -> [Module] {
        var targets: [String: Module] = [:]
        for productName in productNames {
            if let product = products.first(where: { $0.name == productName }) {
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
        }
        return Array(targets.values)
    }
}
