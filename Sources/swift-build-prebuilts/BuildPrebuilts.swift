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

@main
struct BuildPrebuilts: AsyncParsableCommand {
    @Option(help: "The directory to generate the artifacts to.")
    var stageDir = try! AbsolutePath(validating: FileManager.default.currentDirectoryPath).appending("stage")

    @Option(name: .customLong("version"), help: "swift-syntax versions to build. Multiple are allowed.")
    var versions: [String] = ["600.0.1", "601.0.1", "602.0.0"]

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

    mutating func run() async throws {
        if build {
            try await build()
        }

        if sign || testSigning {
            try await sign()
        }
    }

    mutating func build() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let hostPlatform = PrebuiltsPlatform.hostPlatform else {
            print("Unable to determine host platform")
            return
        }

        let fileSystem = localFileSystem
        let hostToolchain = try UserToolchain(
            swiftSDK: SwiftSDK.hostSwiftSDK(
                environment: Environment.current,
                fileSystem: fileSystem
            ),
            environment: Environment.current
        )

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

        // For now, hardcode what we're building prebuilts for
        let id = "swift-syntax"
        let libraryName = "MacroSupport"
        let repoDir = srcDir.appending(id)
        let scratchDir = repoDir.appending(".build")
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
            try fileSystem.writeFileContents(packageFile, string: packageContents)

            // Build
            let cModules = libraryTargets.compactMap({ $0 as? ClangModule })

            for platform in hostPlatform.supportedPlatforms {
                try fileSystem.createDirectory(libDir, recursive: true)
                try fileSystem.createDirectory(modulesDir, recursive: true)

                let lib = "lib\(libraryName).a"
                let destLib = platform.os == .windows ? "\(libraryName).lib" : lib

                // Clean out the scratch dir
                if fileSystem.exists(scratchDir) {
                    try fileSystem.removeFileTree(scratchDir)
                }

                // Build
                if platform.os == .macos {
                    // Create universal binaries for macOS
                    for arch in ["arm64", "x86_64"] {
                        let cmd = "swift build -c release -debug-info-format none --arch \(arch) --product \(libraryName)"
                        try await shell(cmd, cwd: repoDir)
                    }

                    let armTriple = "arm64-apple-macos"
                    let armDir = scratchDir.appending("arm64-apple-macosx", "release")
                    let armModulesDir = armDir.appending("Modules")
                    let x86Triple = "x86_64-apple-macos"
                    let x86Dir = scratchDir.appending("x86_64-apple-macosx", "release")
                    let x86ModulesDir = x86Dir.appending("Modules")

                    // Universal swiftmodules
                    for swiftmodule in try fileSystem.getDirectoryContents(armModulesDir).filter({ $0.hasSuffix(".swiftmodule") }) {
                        let moduleDir = modulesDir.appending(swiftmodule)
                        let projectDir = moduleDir.appending("Project")
                        try fileSystem.createDirectory(projectDir, recursive: true)
                        let moduleName = swiftmodule.replacingOccurrences(of: ".swiftmodule", with: "")
                        try fileSystem.copy(from: armModulesDir.appending(swiftmodule), to: moduleDir.appending(armTriple + ".swiftmodule"))
                        try fileSystem.copy(from: x86ModulesDir.appending(swiftmodule), to: moduleDir.appending(x86Triple + ".swiftmodule"))
                        try fileSystem.copy(from: armModulesDir.appending(moduleName + ".abi.json"), to: moduleDir.appending(armTriple + ".abi.json"))
                        try fileSystem.copy(from: x86ModulesDir.appending(moduleName + ".abi.json"), to: moduleDir.appending(x86Triple + ".abi.json"))
                        try fileSystem.copy(from: armModulesDir.appending(moduleName + ".swiftdoc"), to: moduleDir.appending(armTriple + ".swiftdoc"))
                        try fileSystem.copy(from: x86ModulesDir.appending(moduleName + ".swiftdoc"), to: moduleDir.appending(x86Triple + ".swiftdoc"))
                        try fileSystem.copy(from: armModulesDir.appending(moduleName + ".swiftsourceinfo"), to: projectDir.appending(armTriple + ".swiftsourceinfo"))
                        try fileSystem.copy(from: x86ModulesDir.appending(moduleName + ".swiftsourceinfo"), to: projectDir.appending(x86Triple + ".swiftsourceinfo"))
                    }

                    // lipo the archive
                    let armLib = armDir.appending(lib)
                    let x86Lib = x86Dir.appending(lib)
                    let cmd = "lipo -create -output \(lib) \(armLib) \(x86Lib)"
                    try await shell(cmd, cwd: libDir)
                } else {
                    let archArg: String
                    if let arch = platform.arch {
                        archArg = "--arch \(arch)"
                    } else {
                        archArg = ""
                    }
                    let cmd = "swift build -c release \(archArg) -debug-info-format none --product \(libraryName)"
                    try await shell(cmd, cwd: repoDir)

                    let buildDir = scratchDir.appending("release")
                    let srcModulesDir = buildDir.appending("Modules")

                    // Copy the swiftmodules
                    for file in try fileSystem.getDirectoryContents(srcModulesDir) {
                        try fileSystem.copy(from: srcModulesDir.appending(file), to: modulesDir.appending(file))
                    }

                    // Copy the library to staging
                    try fileSystem.copy(from: buildDir.appending(lib), to: libDir.appending(destLib))
                }

                // Name of the prebuilt
                let prebuiltName = try platform.prebuiltName(hostToolchain: hostToolchain)

                // Zip it up
                let contentDirs = ["lib", "Modules"]
                let contents: ByteString
                switch platform.os {
                case .macos:
                    let zipFile = versionDir.appending("\(prebuiltName)-\(libraryName).zip")
                    try await shell("zip -r \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                    contents = try ByteString(fileSystem.readFileContents(zipFile))
                case .windows:
                    let zipFile = versionDir.appending("\(prebuiltName)-\(libraryName).zip")
                    try await shell("tar -acf \(zipFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                    contents = try ByteString(fileSystem.readFileContents(zipFile))
                case .linux:
                    let tarFile = versionDir.appending("\(prebuiltName)-\(libraryName).tar.gz")
                    try await shell("tar -zcf \(tarFile.pathString) \(contentDirs.joined(separator: " "))", cwd: stageDir)
                    contents = try ByteString(fileSystem.readFileContents(tarFile))
                }

                // Manifest fragment for the zip file
                let checksum = SHA256().hash(contents).hexadecimalRepresentation
                let library = Workspace.PrebuiltsManifest.Library(
                    name: libraryName,
                    checksum: checksum,
                    products: package.products.map(\.name),
                    includePath: cModules.map({ $0.includeDir.relative(to: repoDir) })
                )
                let manifest = Workspace.PrebuiltsManifest(libraries: [library])

                let unsignedJsonFile = versionDir.appending("\(prebuiltName).unsigned")
                try fileSystem.writeFileContents(unsignedJsonFile, data: encoder.encode(manifest))

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

        func make(path: String) throws -> AbsolutePath {
            if let path = try? AbsolutePath(validating: path) {
                // It's already absolute
                return path
            }

            return try AbsolutePath(validating: FileManager.default.currentDirectoryPath)
                .appending(RelativePath(validating: path))
        }

        guard let privateKeyPathStr else {
            fatalError("No private key path provided")
        }

        let certChainPaths = try certChainPathStrs.map { try make(path: $0) }

        guard let rootCertPath = certChainPaths.last else {
            fatalError("No certificates provided")
        }

        let privateKeyPath = try make(path: privateKeyPathStr)

        let id = "swift-syntax"
        let prebuiltDir = stageDir.appending(id)
        for version in try fileSystem.getDirectoryContents(prebuiltDir) {
            let versionDir = prebuiltDir.appending(version)

            for file in try fileSystem.getDirectoryContents(versionDir).filter({ $0.hasSuffix(".unsigned") }) {
                let unsignedJsonFile = versionDir.appending(file)
                let signedJsonFile = versionDir.appending(unsignedJsonFile.basenameWithoutExt + ".json")

                let unsignedData: Data = try fileSystem.readFileContents(unsignedJsonFile)
                let manifest = try decoder.decode(Workspace.PrebuiltsManifest.self, from: unsignedData)

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
                    try fileSystem.writeFileContents(signedJsonFile, data: encoder.encode(signedManifest))
                }
            }
        }
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

extension PrebuiltsPlatform {
    public var supportedPlatforms: [Self] {
        switch os {
        case .macos:
            // Universal binaries on Mac
            return [.macos_universal]
        case .windows:
            // Windows can build both archs
            return [.windows_aarch64, .windows_x86_64]
        case .linux:
            return [self]
        }
    }
}
