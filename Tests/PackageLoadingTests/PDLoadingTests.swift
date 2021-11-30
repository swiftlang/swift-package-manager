/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import TSCUtility
import XCTest

class PackageDescriptionLoadingTests: XCTestCase, ManifestLoaderDelegate {
    lazy var manifestLoader = ManifestLoader(toolchain: ToolchainConfiguration.default, delegate: self)
    var parsedManifest = ThreadSafeBox<AbsolutePath>()
    
    public func willLoad(manifest: AbsolutePath) {
    }
    
    public func willParse(manifest: AbsolutePath) {
        parsedManifest.put(manifest)
    }

    var toolsVersion: ToolsVersion {
        fatalError("implement in subclass")
    }

    func loadManifest(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        observabilityScope: ObservabilityScope,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Manifest {
        try self.loadManifest(
            ByteString(encodingAsUTF8: contents),
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            observabilityScope: observabilityScope
        )
    }

    @available(macOS 12.0, *)
    func loadManifest(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        observabilityScope: ObservabilityScope,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> Manifest {
        try await self.loadManifest(
            ByteString(encodingAsUTF8: contents),
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            observabilityScope: observabilityScope
        )
    }

    func loadManifest(
        _ bytes: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        observabilityScope: ObservabilityScope,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Manifest {
        let packageKind = packageKind ?? .fileSystem(.root)
        let packagePath: AbsolutePath
        switch packageKind {
        case .root(let path):
            packagePath = path
        case .fileSystem(let path):
            packagePath = path
        case .localSourceControl(let path):
            packagePath = path
        case .remoteSourceControl, .registry:
            throw InternalError("invalid package kind \(packageKind)")
        }

        let toolsVersion = toolsVersion ?? self.toolsVersion
        let fileSystem = InMemoryFileSystem()
        let manifestPath = packagePath.appending(component: Manifest.filename)
        try fileSystem.writeFileContents(manifestPath, bytes: bytes)
        let manifest = try manifestLoader.load(
            at: packagePath,
            packageKind: packageKind,
            toolsVersion: toolsVersion,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        if manifest.toolsVersion != toolsVersion {
            XCTFail("Invalid manifest version", file: file, line: line)
        }

        return manifest
    }

    @available(macOS 12.0, *)
    func loadManifest(
        _ bytes: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        observabilityScope: ObservabilityScope,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> Manifest {
        let packageKind = packageKind ?? .fileSystem(.root)
        let packagePath: AbsolutePath
        switch packageKind {
        case .root(let path):
            packagePath = path
        case .fileSystem(let path):
            packagePath = path
        case .localSourceControl(let path):
            packagePath = path
        case .remoteSourceControl, .registry:
            throw InternalError("invalid package kind \(packageKind)")
        }

        let toolsVersion = toolsVersion ?? self.toolsVersion
        let fileSystem = InMemoryFileSystem()
        let manifestPath = packagePath.appending(component: Manifest.filename)
        try fileSystem.writeFileContents(manifestPath, bytes: bytes)
        let manifest = try await manifestLoader.load(
            at: packagePath,
            packageKind: packageKind,
            toolsVersion: toolsVersion,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        if manifest.toolsVersion != toolsVersion {
            XCTFail("Invalid manifest version", file: file, line: line)
        }

        return manifest
    }
}
