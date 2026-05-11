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

import Testing
import Foundation
import Basics
import struct TSCBasic.SHA256
import struct TSCBasic.ByteString
import let TSCBasic.stdoutStream
import struct TSCUtility.Version
import PackageGraph
import PackageModel
import Workspace
import _InternalTestSupport

@Suite struct PrebuiltsTests {
    let swiftVersion = "swift-\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

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
                    checksum: SHA256().hash(ByteString(artifact)).hexadecimalRepresentation,
                    products: [
                        "SwiftSyntaxMacrosTestSupport",
                        "SwiftCompilerPlugin",
                        "SwiftSyntaxMacros"
                    ],
                    includePath: [
                        .init("Sources/_SwiftSyntaxCShims/include")
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
                observabilityScope: ObservabilitySystem({ _, diagnostic in print(diagnostic) }, outputStream: stdoutStream, logLevel: .debug).topScope
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
                            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                        ],
                        type: .test
                    ),
                ],
                dependencies: [
                    .sourceControl(
                        url: swiftSyntaxURL,
                        requirement: .exact(try #require(Version(swiftSyntaxVersion)))
                    )
                ]
            )

            let swiftSyntax = try MockPackage(
                name: "swift-syntax",
                url: swiftSyntaxURL,
                targets: [
                    MockTarget(name: "SwiftSyntaxMacros"),
                ],
                products: [
                    MockProduct(name: "SwiftSyntaxMacros", modules: ["SwiftSyntaxMacros"]),
                ],
                versions: ["600.0.1", "600.0.2", "601.0.0"]
            )

            try await run(signedManifest, rootCertPath, rootPackage, swiftSyntax)
        }
    }

    func checkPrebuilts(graph: ModulesGraph) throws {
        // Check that the prebuilt module/product got added to the graph
        let prebuiltModule = try #require(graph.module(for: "MacroSupport"))
        let binary = try #require(prebuiltModule.underlying as? BinaryModule)
        if case .prebuilt(let library) = binary.kind {
            #expect(library.libraryName == "MacroSupport")
        } else {
            Issue.record("MacroSupport is not a prebuilt")
        }

        let prebuiltProduct = try #require(graph.product(for: "MacroSupport"))
        #expect(prebuiltProduct.type == .library(.automatic))

        for module in graph.allModules {
            if ["FooMacros", "FooTests"].contains(module.name) {
                // Makes sure the dep on the prebuilts product got added
                // and it and source products are conditioned correctly
                do {
                    let conditions: [PackageCondition] = try #require(module.dependencies.compactMap({
                        guard case let .product(product, conditions: conditions) = $0, product.name == "MacroSupport" else {
                            return nil
                        }
                        return conditions
                    }).first)
                    #expect(try conditions.contains(where: {
                        let platformConditions = try #require($0.platformsCondition)
                        return platformConditions.includeIfPrebuiltsSupported == true
                    }))
                }

                do {
                    let conditions: [PackageCondition] = try #require(module.dependencies.compactMap({
                        guard case let .product(product, conditions: conditions) = $0, product.name == "SwiftSyntaxMacros" else {
                            return nil
                        }
                        return conditions
                    }).first)
                    #expect(try conditions.contains(where: {
                        let platformConditions = try #require($0.platformsCondition)
                        return platformConditions.includeIfPrebuiltsSupported == false
                    }))
                }
            } else {
                // Make sure Macro support didn't get added to other modules deps
                #expect(!module.dependencies.contains(where: {
                    switch $0 {
                    case .product(let product, conditions: _):
                        return product.name == "MacroSupport"
                    case .module:
                        return false
                    }
                }))
            }
        }
    }

    func checkNoPrebuilts(graph: ModulesGraph) throws {
        // Make sure prebuilt product/module wasn't added to the grpah
        #expect(graph.product(for: "MacroSupport") == nil)
        #expect(graph.module(for: "MacroSupport") == nil)
    }

    @Test func successPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                ),
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func versionChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    // make sure it's the updated one
                    #expect(request.url == "https://download.swift.org/prebuilts/swift-syntax/601.0.0/\(self.swiftVersion).json")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }

            // Change the version of swift syntax to one that doesn't have prebuilts
            try await workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
            let key = MockManifestLoader.Key(url: sandbox.appending(components: "roots", rootPackage.name).pathString)
            let oldManifest = try #require(workspace.manifestLoader.manifests[key])
            let oldSCM: PackageDependency.SourceControl
            if case let .sourceControl(scm) = oldManifest.dependencies[0] {
                oldSCM = scm
            } else {
                Issue.record("not source control")
                return
            }
            let newDep = PackageDependency.sourceControl(
                identity: oldSCM.identity,
                nameForTargetDependencyResolutionOnly: oldSCM.nameForTargetDependencyResolutionOnly,
                location: oldSCM.location,
                requirement: .exact(Version("601.0.0")),
                productFilter: oldSCM.productFilter
            )
            let newManifest = oldManifest.with(dependencies: [newDep])
            workspace.manifestLoader.manifests[key] = newManifest

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }

            // Change it back
            try await workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
            workspace.manifestLoader.manifests[key] = oldManifest

            try await workspace.checkPackageGraph(roots: [rootPackage.name]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func sshURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1", swiftSyntaxURL: "git@github.com:swiftlang/swift-syntax.git") {
            prebuilts, rootCertPath, rootPackage, swiftSyntax in

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func redirectURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1", swiftSyntaxURL: "https://github.com/apple/swift-syntax.git") {
            prebuilts, rootCertPath, rootPackage, swiftSyntax in

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func cachedArtifact() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip")
        try fs.writeFileContents(cacheFile, data: artifact)

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    Issue.record("Unexpect download of archive")
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func unsupportedSwiftSyntaxVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.2") { _, rootCertPath, rootPackage, swiftSyntax in
            let secondFetch = SendableBox(false)

            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.2/\(self.swiftVersion).json" {
                    let secondFetch = await secondFetch.value
                    #expect(!secondFetch, "unexpected second fetch")
                    return .notFound()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }

            await secondFetch.set(true)

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func unsupportedArch() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { _, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    // Pretend it's not there.
                    return .notFound()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func unsupportedSwiftVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { _, rootCertPath, rootPackage, swiftSyntax in
            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    // Pretend it's a different swift version
                    return .notFound()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func badSignature() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            // Make a change in the manifest
            var manifest = prebuilts.manifest
            manifest.libraries[0].checksum = "BAD"
            let badManifest = Workspace.SignedPrebuiltsManifest(
                manifest: manifest,
                signature: prebuilts.signature
            )
            let manifestData = try JSONEncoder().encode(badManifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                #expect(diagnostics.contains(where: { $0.message == "Failed to decode prebuilt manifest: invalidSignature" }))
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func badChecksumHttp() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            let fakeArtifact = Data([56])

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: fakeArtifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func badChecksumCache() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, rootCertPath, rootPackage, swiftSyntax in
            let fakeArtifact = Data([56])
            let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport.zip")
            try fs.writeFileContents(cacheFile, data: fakeArtifact)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: try JSONEncoder().encode(prebuilts))
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                #expect(archivePath == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                #expect(destination == sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                    hostPlatform: .macos_universal,
                    rootCertPath: rootCertPath
                )
            )

            try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func badManifest() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { prebuilts, _, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(prebuilts)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    let badManifestData = manifestData + Data("bad".utf8)
                    try fileSystem.writeFileContents(destination, data: badManifestData)
                    return .okay()
                } else {
                    Issue.record("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                Issue.record("Unexpected call to archiver")
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
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }

    @Test func disabled() async throws {
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
                #expect(diagnostics.filter({ $0.severity == .error }).isEmpty)
                try checkNoPrebuilts(graph: modulesGraph)
            }
        }
    }
}
