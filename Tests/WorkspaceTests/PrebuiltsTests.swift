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
import let TSCBasic.stdoutStream
import struct TSCUtility.Version
import PackageGraph
import PackageModel
import Workspace
import XCTest
import _InternalTestSupport

final class PrebuiltsTests: XCTestCase {
    let swiftVersion = "swift-\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

    func with(
        fileSystem: FileSystem,
        artifact: Data,
        swiftSyntaxVersion: String,
        swiftSyntaxURL: String? = nil,
        run: (Workspace.SignedPrebuiltsManifest, AbsolutePath, MockPackage, MockPackage) async throws -> ()
    ) async throws {
        try await fixtureXCTest(name: "Signing") { fixturePath in
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
                observabilityScope: ObservabilitySystem({ _, diagnostic in print(diagnostic) }, outputStream: stdoutStream).topScope
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
            let includes = try XCTUnwrap(target.buildSettings.assignments[.PREBUILT_INCLUDE_PATHS]).flatMap(\.values)
            XCTAssertEqual(includes.count, 2)
            XCTAssertTrue(includes.contains("/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport/Modules".fixwin))
            XCTAssertTrue(includes.contains("/tmp/ws/.build/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include".fixwin))
            let libPaths = try XCTUnwrap(target.buildSettings.assignments[.PREBUILT_LIBRARY_PATHS]).flatMap(\.values)
            XCTAssertEqual(libPaths, ["/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport/lib".fixwin])
            let lib = try XCTUnwrap(target.buildSettings.assignments[.PREBUILT_LIBRARIES]).flatMap(\.values)
            XCTAssertEqual(lib, ["MacroSupport"])
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    // make sure it's the updated one
                    XCTAssertEqual(
                        request.url,
                        "https://download.swift.org/prebuilts/swift-syntax/601.0.0/\(self.swiftVersion).json"
                    )
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip")
        try fs.writeFileContents(cacheFile, data: artifact)

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: "600.0.1") { manifest, rootCertPath, rootPackage, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    XCTFail("Unexpect download of archive")
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.2/\(self.swiftVersion).json" {
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
            let httpClient = HTTPClient { request, progressHandler in
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    // Pretend it's not there.
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
                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
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
            manifest.libraries[0].checksum = "BAD"
            let badManifest = Workspace.SignedPrebuiltsManifest(
                manifest: manifest,
                signature: goodManifest.signature
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
                    hostPlatform: .macos_universal,
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
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
                    hostPlatform: .macos_universal,
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
            let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport.zip")
            try fs.writeFileContents(cacheFile, data: fakeArtifact)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
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

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
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

    // Test a macro that uses a library that doesn't use prebuilts which then uses a library that does works.
    // Also test plugins work
    func testIndirectLibrary() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()
        let swiftSyntaxVersion = "600.0.1"

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: swiftSyntaxVersion) { manifest, rootCertPath, _, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
                completion(.success(()))
            })

            let libraryURL = "https://github.com/swiftlang/Library"

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    .init(
                        name: "Foo",
                        targets: [
                            MockTarget(
                                name: "FooMacros",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                                    .product(name: "Intermediate", package: "Library"),
                                ],
                                type: .macro
                            ),
                            MockTarget(
                                name: "Foo",
                                dependencies: ["FooMacros"]
                            ),
                            MockTarget(
                                name: "FooClient",
                                dependencies: [
                                    "Foo",
                                ],
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
                        products: [
                            MockProduct(
                                name: "Library",
                                modules: [
                                    "Foo",
                                ]
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            ),
                            .sourceControl(
                                url: libraryURL,
                                requirement: .exact(try XCTUnwrap(Version("1.0.0")))
                            ),
                        ]
                    )
                ],
                packages: [
                    MockPackage(
                        name: "Library",
                        url: libraryURL,
                        targets: [
                            MockTarget(
                                name: "Base",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                ]
                            ),
                            MockTarget(
                                name: "Intermediate",
                                dependencies: [
                                    "Base",
                                ]
                            ),
                        ],
                        products: [
                            MockProduct(
                                name: "Intermediate",
                                modules: [
                                    "Intermediate"
                                ]
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            )
                        ],
                        versions: ["1.0.0"]
                    ),
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
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: true)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: true)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    // Test that if a library using prebuilts is exposed outside the root package that prebuilts are turned off
    func testLeakyLibrary() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()
        let swiftSyntaxVersion = "600.0.1"

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: swiftSyntaxVersion) { manifest, rootCertPath, _, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
                completion(.success(()))
            })

            let libraryURL = "https://github.com/swiftlang/Library"

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    .init(
                        name: "Foo",
                        targets: [
                            MockTarget(
                                name: "FooMacros",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                                    .product(name: "Intermediate", package: "Library"),
                                ],
                                type: .macro
                            ),
                            MockTarget(
                                name: "Foo",
                                dependencies: ["FooMacros"]
                            ),
                            MockTarget(
                                name: "FooClient",
                                dependencies: [
                                    "Foo",
                                    .product(name: "Plugin", package: "Library"),
                                ],
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
                            MockTarget(
                                name: "Leaking",
                                dependencies: [
                                    .product(name: "Intermediate", package: "Library"),
                                ]
                            )
                        ],
                        products: [
                            MockProduct(
                                name: "Library",
                                modules: [
                                    "Foo",
                                    "Leaking"
                                ]
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            ),
                            .sourceControl(
                                url: libraryURL,
                                requirement: .exact(try XCTUnwrap(Version("1.0.0")))
                            ),
                        ]
                    )
                ],
                packages: [
                    MockPackage(
                        name: "Library",
                        url: libraryURL,
                        targets: [
                            MockTarget(
                                name: "Base",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                ]
                            ),
                            MockTarget(
                                name: "Intermediate",
                                dependencies: [
                                    "Base",
                                ]
                            ),
                            MockTarget(
                                name: "Generator",
                                dependencies: [
                                    "Intermediate"
                                ],
                                type: .executable
                            ),
                            MockTarget(
                                name: "Plugin",
                                dependencies: [
                                    "Generator"
                                ],
                                type: .plugin,
                                pluginCapability: .buildTool
                            )
                        ],
                        products: [
                            MockProduct(
                                name: "Intermediate",
                                modules: [
                                    "Intermediate"
                                ]
                            ),
                            MockProduct(
                                name: "Plugin",
                                modules: [
                                    "Plugin",
                                ],
                                type: .plugin
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            )
                        ],
                        versions: ["1.0.0"]
                    ),
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
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "FooTests", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
                try checkSettings(rootPackage, "FooClient", usePrebuilt: false)
            }
        }
    }

    // Test that if a library using prebuilts is exposed outside root dependencies that prebuilts are turned off
    func testRootDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let artifact = Data()
        let swiftSyntaxVersion = "600.0.1"

        try await with(fileSystem: fs, artifact: artifact, swiftSyntaxVersion: swiftSyntaxVersion) { manifest, rootCertPath, _, swiftSyntax in
            let manifestData = try JSONEncoder().encode(manifest)

            let httpClient = HTTPClient { request, progressHandler in
                guard case .download(let fileSystem, let destination) = request.kind else {
                    throw StringError("invalid request \(request.kind)")
                }

                if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion).json" {
                    try fileSystem.writeFileContents(destination, data: manifestData)
                    return .okay()
                } else if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport.zip" {
                    try fileSystem.writeFileContents(destination, data: artifact)
                    return .okay()
                } else {
                    XCTFail("Unexpected URL \(request.url)")
                    return .notFound()
                }
            }

            let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
                XCTAssertEqual(archivePath, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport.zip"))
                XCTAssertEqual(destination, sandbox.appending(components: ".build", "prebuilts", "swift-syntax", "600.0.1", "\(self.swiftVersion)-MacroSupport"))
                completion(.success(()))
            })

            let libraryURL = "https://github.com/swiftlang/Library"

            let workspace = try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [],
                packages: [
                    .init(
                        name: "Foo",
                        targets: [
                            MockTarget(
                                name: "FooMacros",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                                    .product(name: "Intermediate", package: "Library"),
                                ],
                                type: .macro
                            ),
                            MockTarget(
                                name: "Foo",
                                dependencies: ["FooMacros"]
                            ),
                            MockTarget(
                                name: "FooClient",
                                dependencies: [
                                    "Foo",
                                    .product(name: "Plugin", package: "Library"),
                                ],
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
                            MockTarget(
                                name: "Leaking",
                                dependencies: [
                                    .product(name: "Intermediate", package: "Library"),
                                ]
                            )
                        ],
                        products: [
                            MockProduct(
                                name: "Library",
                                modules: [
                                    "Foo",
                                    "Leaking"
                                ]
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            ),
                            .sourceControl(
                                url: libraryURL,
                                requirement: .exact(try XCTUnwrap(Version("1.0.0")))
                            ),
                        ],
                        versions: [nil]
                    ),
                    MockPackage(
                        name: "Library",
                        url: libraryURL,
                        targets: [
                            MockTarget(
                                name: "Base",
                                dependencies: [
                                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                ]
                            ),
                            MockTarget(
                                name: "Intermediate",
                                dependencies: [
                                    "Base",
                                ]
                            ),
                            MockTarget(
                                name: "Generator",
                                dependencies: [
                                    "Intermediate"
                                ],
                                type: .executable
                            ),
                            MockTarget(
                                name: "Plugin",
                                dependencies: [
                                    "Generator"
                                ],
                                type: .plugin,
                                pluginCapability: .buildTool
                            )
                        ],
                        products: [
                            MockProduct(
                                name: "Intermediate",
                                modules: [
                                    "Intermediate"
                                ]
                            ),
                            MockProduct(
                                name: "Plugin",
                                modules: [
                                    "Plugin",
                                ],
                                type: .plugin
                            ),
                        ],
                        dependencies: [
                            .sourceControl(
                                url: "https://github.com/swiftlang/swift-syntax",
                                requirement: .exact(try XCTUnwrap(Version("600.0.1")))
                            )
                        ],
                        versions: ["1.0.0"]
                    ),
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

            let rootDep = PackageDependency.fileSystem(identity: .plain("Foo"), path: workspace.packagesDir.appending("Foo"))
            try await workspace.checkPackageGraph(roots: [], dependencies: [rootDep]) { modulesGraph, diagnostics in
                XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
                let rootPackage = try XCTUnwrap(modulesGraph.package(for: rootDep.identity))
                try checkSettings(rootPackage, "FooMacros", usePrebuilt: false)
                try checkSettings(rootPackage, "Foo", usePrebuilt: false)
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
