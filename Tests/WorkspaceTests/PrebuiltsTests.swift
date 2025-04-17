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
import PackageModel
import Workspace
import XCTest
import _InternalTestSupport

final class PrebuiltsTests: XCTestCase {
    let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

    func initData(artifact: Data, swiftSyntaxVersion: String) throws -> (Workspace.PrebuiltsManifest, MockPackage, MockPackage) {
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
                    ]
                )
            ],
            dependencies: [
                .sourceControl(
                    url: "https://github.com/swiftlang/swift-syntax",
                    requirement: .exact(try XCTUnwrap(Version(swiftSyntaxVersion)))
                )
            ]
        )

        let swiftSyntax = try MockPackage(
            name: "swift-syntax",
            url: "https://github.com/swiftlang/swift-syntax",
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
            versions: ["600.0.1", "600.0.2"]
        )

        return (manifest, rootPackage, swiftSyntax)
    }

    func checkSettings(_ target: Module, usePrebuilt: Bool) throws {
        if usePrebuilt {
            let swiftFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS]).flatMap({ $0.values })
            XCTAssertTrue(swiftFlags.contains("-I\(AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64/Modules").pathString)"))
            XCTAssertTrue(swiftFlags.contains("-I\(AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64/include/_SwiftSyntaxCShims").pathString)"))
            let ldFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_LDFLAGS]).flatMap({ $0.values })
            XCTAssertTrue(ldFlags.contains(AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64/lib/libMacroSupport.a").pathString))
        } else {
            XCTAssertNil(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS])
            XCTAssertNil(target.buildSettings.assignments[.OTHER_LDFLAGS])
        }
    }

    func testSuccessPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
                try fileSystem.writeFileContents(destination, data: manifestData)
                return .okay()
            } else if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                try fileSystem.writeFileContents(destination, data: artifact)
                return .okay()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, AbsolutePath("/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip").pathString)
            XCTAssertEqual(destination.pathString, AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64").pathString)
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
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: Triple("arm64-apple-macosx15.0")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: true)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: true)
        }
    }

    func testCachedArtifact() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip")
        try fs.writeFileContents(cacheFile, data: artifact)

        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
                try fileSystem.writeFileContents(destination, data: manifestData)
                return .okay()
            } else if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                XCTFail("Unexpect download of archive")
                try fileSystem.writeFileContents(destination, data: artifact)
                return .okay()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, AbsolutePath("/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip").pathString)
            XCTAssertEqual(destination.pathString, AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64").pathString)
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
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: Triple("arm64-apple-macosx15.0")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: true)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: true)
        }
    }

    func testUnsupportedSwiftSyntaxVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (_, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.2")

        let httpClient = HTTPClient { request, progressHandler in
            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.2/\(self.swiftVersion)-manifest.json" {
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
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }
    }

    func testUnsupportedArch() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
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
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: Triple("86_64-unknown-linux-gnu")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }
    }

    func testUnsupportedSwiftVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (_, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")

        let httpClient = HTTPClient { request, progressHandler in
            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
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
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }

    }

    func testBadChecksumHttp() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let fakeArtifact = Data([56])

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
                try fileSystem.writeFileContents(destination, data: manifestData)
                return .okay()
            } else if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
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
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: Triple("arm64-apple-macosx15.0")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }
    }

    func testBadChecksumCache() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let fakeArtifact = Data([56])
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip")
        try fs.writeFileContents(cacheFile, data: fakeArtifact)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
                try fileSystem.writeFileContents(destination, data: manifestData)
                return .okay()
            } else if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                try fileSystem.writeFileContents(destination, data: artifact)
                return .okay()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, AbsolutePath("/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip").pathString)
            XCTAssertEqual(destination.pathString, AbsolutePath("/tmp/ws/.build/prebuilts/swift-syntax/\(self.swiftVersion)-MacroSupport-macos_aarch64").pathString)
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
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: Triple("arm64-apple-macosx15.0")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: true)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: true)
        }
    }

    func testBadManifest() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (manifest, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")
        let manifestData = try JSONEncoder().encode(manifest)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://github.com/dschaefer2/swift-syntax/releases/download/600.0.1/\(self.swiftVersion)-manifest.json" {
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
                httpClient: httpClient,
                archiver: archiver
            )
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }
    }

    func testDisabled() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let (_, rootPackage, swiftSyntax) = try initData(artifact: artifact, swiftSyntaxVersion: "600.0.1")

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                rootPackage
            ],
            packages: [
                swiftSyntax
            ],
            customHostTriple: Triple("arm64-apple-macosx15.0")
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            let macroTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooMacros" }))
            try checkSettings(macroTarget, usePrebuilt: false)
            let testTarget = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == "FooTests" }))
            try checkSettings(testTarget, usePrebuilt: false)
        }
    }
}
