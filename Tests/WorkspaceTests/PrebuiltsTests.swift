//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

///
/// Tests for the macro prebuilts features that will use a prebuilt library for swift-syntax dependencies for macros.
///

import Basics
import struct TSCBasic.SHA256
import struct TSCBasic.ByteString
import struct TSCUtility.Version
import PackageGraph
import PackageModel
import Workspace
import XCTest
import _InternalTestSupport

final class PrebuiltsTests: XCTestCase {
    let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

    func with(
        fileSystem: FileSystem,
        artifact: Data,
        swiftSyntaxVersion: String,
        swiftSyntaxURL: String? = nil,
        run: (Workspace.SignedPrebuiltsManifest, AbsolutePath, MockPackage, MockPackage) async throws -> ()
    ) async throws {
        try await fixture(name: "Signing") { fixturePath in
            let swiftSyntaxURL = swiftSyntaxURL ?? "https://github.com/swiftlang/swift-syntax"

            let manifest = Workspace.PrebuiltsManifest(libraries: [
                .init(
                    name: "MacroSupport",
                    products: [
                        "SwiftSyntaxMacrosTestSupport",
                        "SwiftCompilerPlugin",
                        "SwiftSyntaxMacros"
                    ],
                    cModules: [
                        "_SwiftSyntaxCShims"
                    ],
                    artifacts: [
                        .init(
                            platform: .macos_aarch64,
                            checksum: SHA256().hash(ByteString(artifact)).hexadecimalRepresentation
                        )
                    ]
                )
            ])

            let certsPath = fixturePath.appending("Certificates")

            let certPaths = [
                certsPath.appending("Test_rsa.cer"),
                certsPath.appending("TestIntermediateCA.cer"),
                certsPath.appending("TestRootCA.cer"),
            ]
            let privateKeyPath = certsPath.appending("Test_rsa_key.pem")

            // Copy into in memory file system
            for path in certPaths + [privateKeyPath] {
                try fileSystem.writeFileContents(path, data: Data(contentsOf: path.asURL))
            }

            let rootCertPath = certPaths.last!
            let trustDir = certsPath.appending("Trust")
            try fileSystem.createDirectory(trustDir, recursive: true)
            try fileSystem.copy(from: rootCertPath, to: trustDir.appending(rootCertPath.basename))

            let signer = ManifestSigning(
                trustedRootCertsDir: trustDir,
                observabilityScope: ObservabilitySystem { _, diagnostic in print(diagnostic) }.topScope
            )

            let signature = try await signer.sign(
                manifest: manifest,
                certChainPaths: certPaths,
                certPrivateKeyPath: privateKeyPath,
                fileSystem: fileSystem
            )

            // Make sure the signing is valid
            try await signer.validate(manifest: manifest, signature: signature, fileSystem: fileSystem)

            let signedManifest = Workspace.SignedPrebuiltsManifest(manifest: manifest, signature: signature)

            let rootPackage = try MockPackage(
                name: "Foo",
                targets: [
                    MockTarget(
                        name: "FooMacros",
                        dependencies: [
                            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                        ],
                        type: .macro
                    ),
                    MockTarget(
                        name: "Foo",
                        dependencies: ["FooMacros"]
                    ),
                    MockTarget(
                        name: "FooClient",
                        dependencies: ["Foo"],
                        type: .executable
                    ),
                    MockTarget(
                        name: "FooTests",
                        dependencies: [
                            "FooMacros",
                            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                        ],
                        type: .test
                    ),
                ],
                dependencies: [
                    .sourceControl(
                        url: swiftSyntaxURL,
                        requirement: .exact(try XCTUnwrap(Version(swiftSyntaxVersion)))
                    )
                ]
            )

            let swiftSyntax = try MockPackage(
                name: "swift-syntax",
                url: swiftSyntaxURL,
                targets: [
                    MockTarget(name: "SwiftSyntaxMacrosTestSupport"),
                    MockTarget(name: "SwiftCompilerPlugin"),
                    MockTarget(name: "SwiftSyntaxMacros"),
                ],
                products: [
                    MockProduct(name: "SwiftSyntaxMacrosTestSupport", modules: ["SwiftSyntaxMacrosTestSupport"]),
                    MockProduct(name: "SwiftCompilerPlugin", modules: ["SwiftCompilerPlugin"]),
                    MockProduct(name: "SwiftSyntaxMacros", modules: ["SwiftSyntaxMacros"]),
                ],
                versions: ["600.0.1", "600.0.2", "601.0.0"]
            )

            try await run(signedManifest, rootCertPath, rootPackage, swiftSyntax)
        }
    }

    func checkSettings(_ rootPackage: ResolvedPackage, _ targetName: String, usePrebuilt: Bool) throws {
        let target = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == targetName }))
        if usePrebuilt {
            let swiftFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS]).flatMap({ $0.values })
            XCTAssertTrue(swiftFlags.contains("-I/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64/Modules".fixwin))
            XCTAssertTrue(swiftFlags.contains("-I/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64/include/_SwiftSyntaxCShims".fixwin))
            let ldFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_LDFLAGS]).flatMap({ $0.values })
            XCTAssertTrue(ldFlags.contains("/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64/lib/libMacroSupport.a".fixwin))
        } else {
            XCTAssertNil(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS])
            XCTAssertNil(target.buildSettings.assignments[.OTHER_LDFLAGS])
        }
    }

    func testSuccessPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                ),
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testVersionChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    // make sure it's the updated one
                    XCTAssertEqual(
                        request.url,
                        "https://download.swift.org/prebuilts/swift-syntax/601.0.0/\(self.swiftVersion)-manifest.json"
                    )
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }

            // Change the version of swift syntax to one that doesn't have prebuilts
            try await workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
            let key = MockManifestLoader.Key(url: sandbox.appending(components: "roots", rootPackage.name).pathString)
            let oldManifest = try XCTUnwrap(workspace.manifestLoader.manifests[key])
            let oldSCM: PackageDependency.SourceControl
            if case let .sourceControl(scm) = oldManifest.dependencies[0] {
                oldSCM = scm
            } else {
                XCTFail("not source control")
                return
            }
            let newDep = PackageDependency.sourceControl(
                identity: oldSCM.identity,
                nameForTargetDependencyResolutionOnly: oldSCM.nameForTargetDependencyResolutionOnly,
                location: oldSCM.location,
                requirement: .exact(try XCTUnwrap(Version("601.0.0"))),
                productFilter: oldSCM.productFilter
            )
            let newManifest = oldManifest.with(dependencies: [newDep])
            workspace.manifestLoader.manifests[key] = newManifest

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }

            // Change it back
            try await workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
            workspace.manifestLoader.manifests[key] = oldManifest

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testSSHURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1", swiftSyntaxURL: "git@github.com:swiftlang/swift-syntax.git") {
            manifest, rootCertPath, rootPackage, swiftSyntax in

            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testRedirectURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1", swiftSyntaxURL: "https://github.com/apple/swift-syntax.git") {
            manifest, rootCertPath, rootPackage, swiftSyntax in

            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }
    func testCachedArtifact() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip")
        try fs.writeFileContents(cacheFile, data: artifact)

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    XCTFail("Unexpect download of archive")
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testUnsupportedSwiftSyntaxVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.2") { _, rootCertPath, rootPackage, swiftSyntax in
            let secondFetch = SendableBox(false)
            
            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.2/\(self.swiftVersion)-manifest.json" {
                    let secondFetch = await secondFetch.value
                    XCTAssertFalse(secondFetch, "unexpected second fetch")
                    return .notFound()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }
            
            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })
            
            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    rootCertPath: rootCertPath
                )
            )
            
            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
            
            await secondFetch.set(true)
            
            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testUnsupportedArch() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .ubuntu_noble_x86_64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testUnsupportedSwiftVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { _, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    // Pretend it's a different swift version
                    return .notFound()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testBadSignature() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { goodManifest, rootCertPath, rootPackage, swiftSyntax in
            // Make a change in the manifest
            var manifest = goodManifest.manifest
            var artifacts = try XCTUnwrap(manifest.libraries[0].artifacts)
            artifacts[0] = .init(platform: artifacts[0].platform, checksum: "BAD")
            manifest.libraries[0].artifacts = artifacts
            let badManifest = Workspace.SignedPrebuiltsManifest(
                manifest: manifest,
                signature: goodManifest.signature
            )
            let manifestData = try JSONEncoder().encode(badManifest)

            let fakeArtifact = Data([56])

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: fakeArtifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                XCTAssertTrue(diagnostics.contains(where: { $0.message == "Failed to decode prebuilt manifest: invalidSignature" }))
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testBadChecksumHttp() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let fakeArtifact = Data([56])

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: fakeArtifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testBadChecksumCache() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let fakeArtifact = Data([56])
            let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip")
            try fs.writeFileContents(cacheFile, data: fakeArtifact)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport-macos_aarch64"))
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver,
                    hostPlatform: .macos_aarch64,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testBadManifest() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, _, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-manifest.json" {
                    let badManifestData = manifestData + Data("bad".utf8)
                    try fileSystem.writeFileContents(destination, data: badManifestData)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTFail("Unexpected call to archiver")
                completion(.success(()))
            })

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ],
                prebuiltsManager: .init(
                    swiftVersion: swiftVersion,
                    httpClient: httpClient,
                    archiver: archiver
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    func testDisabled() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { _, _, rootPackage, swiftSyntax in
            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    rootPackage
                ],
                packages: [
                    swiftSyntax
                ]
            )
            
            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }
}

extension String {
    var fixwin: String {
        #if os(Windows)
        return self.replacingOccurrences(of: "/", with: "\\")
        #else
        return self
        #endif
    }
}
