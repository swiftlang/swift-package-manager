//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Commands
import Foundation
import PackageLoading
import PackageModel
@testable import PackageRegistryTool
import PackageSigning
import SPMTestSupport
import TSCBasic
import TSCclibc // for SPM_posix_spawn_file_actions_addchdir_np_supported
import Workspace
import XCTest

let defaultRegistryBaseURL = URL("https://packages.example.com")
let customRegistryBaseURL = URL("https://custom.packages.example.com")

final class PackageRegistryToolTests: CommandsTestCase {
    @discardableResult
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: EnvironmentVariables? = nil
    ) throws -> (exitStatus: ProcessResult.ExitStatus, stdout: String, stderr: String) {
        var environment = env ?? [:]
        // don't ignore local packages when caching
        environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
        let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
            args,
            packagePath: packagePath,
            env: environment
        )
        return try (result.exitStatus, result.utf8Output(), result.utf8stderrOutput())
    }

    func testUsage() throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        let stdout = try execute(["-help"]).stdout
        XCTAssert(stdout.contains("USAGE: swift package-registry"), "got stdout:\n" + stdout)
    }

    func testSeeAlso() throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        let stdout = try execute(["--help"]).stdout
        XCTAssert(stdout.contains("SEE ALSO: swift package"), "got stdout:\n" + stdout)
    }

    func testVersion() throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        let stdout = try execute(["--version"]).stdout
        XCTAssert(stdout.contains("Swift Package Manager"), "got stdout:\n" + stdout)
    }

    func testLocalConfiguration() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                path: ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                let result = try execute(["set", "\(defaultRegistryBaseURL)"], packagePath: packageRoot)
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string,
                    "\(defaultRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            // Set new default registry
            do {
                let result = try execute(["set", "\(customRegistryBaseURL)"], packagePath: packageRoot)
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string,
                    "\(customRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            // Unset default registry
            do {
                let result = try execute(["unset"], packagePath: packageRoot)
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 0)
                XCTAssertEqual(json["version"], .int(1))
            }

            // Set registry for "foo" scope
            do {
                let result = try execute(
                    ["set", "\(customRegistryBaseURL)", "--scope", "foo"],
                    packagePath: packageRoot
                )
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["foo"]?.dictionary?["url"]?.string,
                    "\(customRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            // Set registry for "bar" scope
            do {
                let result = try execute(
                    ["set", "\(customRegistryBaseURL)", "--scope", "bar"],
                    packagePath: packageRoot
                )
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 2)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["foo"]?.dictionary?["url"]?.string,
                    "\(customRegistryBaseURL)"
                )
                XCTAssertEqual(
                    json["registries"]?.dictionary?["bar"]?.dictionary?["url"]?.string,
                    "\(customRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            // Unset registry for "foo" scope
            do {
                let result = try execute(["unset", "--scope", "foo"], packagePath: packageRoot)
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["bar"]?.dictionary?["url"]?.string,
                    "\(customRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            XCTAssertTrue(localFileSystem.exists(configurationFilePath))
        }
    }

    // TODO: Test global configuration

    func testSetMissingURL() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                path: ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                let result = try execute(["set", "--scope", "foo"], packagePath: packageRoot)
                XCTAssertNotEqual(result.exitStatus, .terminated(code: 0))
            }

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))
        }
    }

    func testSetInvalidURL() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                path: ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                let result = try execute(["set", "invalid"], packagePath: packageRoot)
                XCTAssertNotEqual(result.exitStatus, .terminated(code: 0))
            }

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))
        }
    }

    func testSetInvalidScope() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                path: ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                let result = try execute(
                    ["set", "--scope", "_invalid_", "\(defaultRegistryBaseURL)"],
                    packagePath: packageRoot
                )
                XCTAssertNotEqual(result.exitStatus, .terminated(code: 0))
            }

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))
        }
    }

    func testUnsetMissingEntry() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                path: ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            XCTAssertFalse(localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                let result = try execute(["set", "\(defaultRegistryBaseURL)"], packagePath: packageRoot)
                XCTAssertEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string,
                    "\(defaultRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            // Unset registry for missing "baz" scope
            do {
                let result = try execute(["unset", "--scope", "baz"], packagePath: packageRoot)
                XCTAssertNotEqual(result.exitStatus, .terminated(code: 0))

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                XCTAssertEqual(json["registries"]?.dictionary?.count, 1)
                XCTAssertEqual(
                    json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string,
                    "\(defaultRegistryBaseURL)"
                )
                XCTAssertEqual(json["version"], .int(1))
            }

            XCTAssertTrue(localFileSystem.exists(configurationFilePath))
        }
    }

    // TODO: Test example with login and password

    func testArchiving() throws {
        #if os(Linux)
        // needed for archiving
        guard SPM_posix_spawn_file_actions_addchdir_np_supported() else {
            throw XCTSkip("working directory not supported on this platform")
        }
        #endif

        let observability = ObservabilitySystem.makeForTesting()

        let packageIdentity = PackageIdentity.plain("org.package")
        let metadataFilename = SwiftPackageRegistryTool.Publish.metadataFilename

        // git repo
        try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            initGitRepo(packageDirectory)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "1.3.5",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            try validatePackageArchive(at: archivePath)
            XCTAssertTrue(archivePath.isDescendant(of: workingDirectory))
        }

        // not a git repo
        try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "1.5.4",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            try validatePackageArchive(at: archivePath)
        }

        // canonical metadata location
        try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            // metadata file
            try localFileSystem.writeFileContents(
                packageDirectory.appending(component: metadataFilename),
                bytes: ""
            )

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "0.3.1",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let extractedPath = try validatePackageArchive(at: archivePath)
            XCTAssertFileExists(extractedPath.appending(component: metadataFilename))
        }

        @discardableResult
        func validatePackageArchive(at archivePath: AbsolutePath) throws -> AbsolutePath {
            XCTAssertFileExists(archivePath)
            let archiver = ZipArchiver(fileSystem: localFileSystem)
            let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractPath)
            try tsc_await { archiver.extract(from: archivePath, to: extractPath, completion: $0) }
            try localFileSystem.stripFirstLevel(of: extractPath)
            XCTAssertFileExists(extractPath.appending("Package.swift"))
            return extractPath
        }
    }

    func testPublishingUnsignedPackage() throws {
        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "https://packages.example.com"

        // custom metadata path
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = temporaryDirectory.appending("metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--metadata-path=\(metadataPath.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        // canonical metadata path
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = packageDirectory.appending(SwiftPackageRegistryTool.Publish.metadataFilename)
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        // no metadata
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            XCTAssertFileExists(packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        func validateManifest(
            manifestFile: String,
            in archivePath: AbsolutePath,
            manifestContent: [UInt8]
        ) async throws {
            XCTAssertFileExists(archivePath)
            let archiver = ZipArchiver(fileSystem: localFileSystem)
            let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractPath)
            try tsc_await { archiver.extract(from: archivePath, to: extractPath, completion: $0) }
            try localFileSystem.stripFirstLevel(of: extractPath)

            let manifestInArchive = try localFileSystem.readFileContents(extractPath.appending(manifestFile)).contents
            XCTAssertEqual(manifestInArchive, manifestContent)
        }
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testPublishingSignedPackage() async throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        let observabilityScope = ObservabilitySystem.makeForTesting().topScope

        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "https://packages.example.com"
        let signatureFormat = SignatureFormat.cms_1_0_0

        // custom metadata path
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            XCTAssertFileExists(manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = temporaryDirectory.appending("metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--metadata-path=\(metadataPath.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await validateSignature(
                signature: signature,
                content: archive,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // metadata signature
            let metadata = try localFileSystem.readFileContents(metadataPath).contents
            let metadataSignaturePath = workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig")
            let metadataSignature = try localFileSystem.readFileContents(metadataSignaturePath).contents
            try await validateSignature(
                signature: metadataSignature,
                content: metadata,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }

        // canonical metadata path
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            XCTAssertFileExists(manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = packageDirectory.appending(SwiftPackageRegistryTool.Publish.metadataFilename)
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await validateSignature(
                signature: signature,
                content: archive,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // metadata signature
            let metadata = try localFileSystem.readFileContents(metadataPath).contents
            let metadataSignaturePath = workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig")
            let metadataSignature = try localFileSystem.readFileContents(metadataSignaturePath).contents
            try await validateSignature(
                signature: metadataSignature,
                content: metadata,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }

        // no metadata
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            XCTAssertFileExists(manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--package-path=\(packageDirectory.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ]
            )
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 0),
                try! result.utf8Output() + result.utf8stderrOutput()
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await validateSignature(
                signature: signature,
                content: archive,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // no metadata so no signature
            XCTAssertTrue(
                !localFileSystem
                    .exists(workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig"))
            )

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }
    }

    private func testRoots(callback: (Result<[[UInt8]], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let rootCA = try localFileSystem
                    .readFileContents(fixturePath.appending(components: "Certificates", "TestRootCA.cer")).contents
                callback(.success([rootCA]))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func validateSignature(
        signature: [UInt8],
        content: [UInt8],
        format: SignatureFormat = .cms_1_0_0,
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws {
        let signatureStatus = try await SignatureProvider.status(
            signature: signature,
            content: content,
            format: format,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: observabilityScope
        )
        guard case .valid = signatureStatus else {
            return XCTFail("Expected signature status to be .valid but got \(signatureStatus)")
        }
    }

    private func validateSignedManifest(
        manifestFile: String,
        in archivePath: AbsolutePath,
        manifestContent: [UInt8],
        format: SignatureFormat = .cms_1_0_0,
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws {
        XCTAssertFileExists(archivePath)
        let archiver = ZipArchiver(fileSystem: localFileSystem)
        let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
        try localFileSystem.createDirectory(extractPath)
        try tsc_await { archiver.extract(from: archivePath, to: extractPath, completion: $0) }
        try localFileSystem.stripFirstLevel(of: extractPath)

        let manifestSignature = try ManifestSignatureParser.parse(
            manifestPath: extractPath.appending(manifestFile),
            fileSystem: localFileSystem
        )
        XCTAssertNotNil(manifestSignature)
        XCTAssertEqual(manifestSignature!.contents, manifestContent)
        let signature = manifestSignature!.signature
        try await self.validateSignature(
            signature: signature,
            content: manifestContent,
            format: format,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: observabilityScope
        )
    }
}
