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
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

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
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

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
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

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
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

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
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

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

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testArchiving() throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        #if os(Linux)
        // needed for archiving
        guard SPM_posix_spawn_file_actions_addchdir_np_supported() else {
            throw XCTSkip("working directory not supported on this platform")
        }
        #endif

        let observability = ObservabilitySystem.makeForTesting()
        let publishTool = SwiftPackageRegistryTool.Publish()

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

            let archivePath = try publishTool.archiveSource(
                packageIdentity: packageIdentity,
                packageVersion: "1.3.5",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
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

            let archivePath = try publishTool.archiveSource(
                packageIdentity: packageIdentity,
                packageVersion: "1.5.4",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
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

            let archivePath = try publishTool.archiveSource(
                packageIdentity: packageIdentity,
                packageVersion: "0.3.1",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
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

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testArchiveSigning() async throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the
        // plugin APIs require).
        try XCTSkipIf(
            !UserToolchain.default.supportsSwiftConcurrency(),
            "skipping because test environment doesn't support concurrency"
        )

        let observabilityScope = ObservabilitySystem.makeForTesting().topScope

        try await withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("fake.zip")
            try localFileSystem.writeFileContents(archivePath, string: "test")

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

            // Generate signature
            let signaturePath = temporaryDirectory.appending(component: "signature")
            try PackageArchiveSigner.sign(
                archivePath: archivePath,
                signaturePath: signaturePath,
                mode: .certificate(
                    certificate: certificatePath,
                    intermediateCertificates: [intermediateCertificatePath],
                    privateKey: privateKeyPath
                ),
                signatureFormat: .cms_1_0_0,
                fileSystem: localFileSystem,
                observabilityScope: observabilityScope
            )

            // Read and validate signature
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            let archive = try localFileSystem.readFileContents(archivePath).contents

            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

            let signatureStatus = try await SignatureProvider.status(
                signature: signature,
                content: archive,
                format: .cms_1_0_0,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
            guard case .valid = signatureStatus else {
                return XCTFail("Expected signature status to be .valid but got \(signatureStatus)")
            }
        }

        // basic validation
        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("fake.zip")
            try localFileSystem.writeFileContents(archivePath, bytes: [])

            let signaturePath = temporaryDirectory.appending("signature")

            let result = try SwiftPMProduct.SwiftPackageRegistry.executeProcess(
                [
                    "sign",
                    archivePath.pathString,
                    signaturePath.pathString,
                ]
            )
            let error = try result.utf8stderrOutput()
            XCTAssertEqual(
                result.exitStatus,
                .terminated(code: 1),
                try! result.utf8Output() + result.utf8stderrOutput()
            )
            XCTAssertMatch(
                error,
                .contains(
                    "Either 'signing-identity' or 'private-key-path' (together with 'cert-chain-paths') must be provided"
                )
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
}
