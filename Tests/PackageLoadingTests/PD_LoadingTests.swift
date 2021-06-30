//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import XCTest

import class TSCBasic.InMemoryFileSystem

class PackageDescriptionLoadingTests: XCTestCase, ManifestLoaderDelegate {
    lazy var manifestLoader = ManifestLoader(toolchain: try! UserToolchain.default, delegate: self)
    var parsedManifest = ThreadSafeBox<AbsolutePath>()
    
    public func willLoad(manifest: AbsolutePath) {
    }
    
    public func willParse(manifest: AbsolutePath) {
        parsedManifest.put(manifest)
    }

    var toolsVersion: ToolsVersion {
        fatalError("implement in subclass")
    }

    func loadAndValidateManifest(
        _ content: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        customManifestLoader: ManifestLoader? = nil,
        observabilityScope: ObservabilityScope,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> (manifest: Manifest, diagnostics: [Basics.Diagnostic]) {
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
        try fileSystem.writeFileContents(manifestPath, string: content)
        let manifest = try (customManifestLoader ?? manifestLoader).load(
            manifestPath: manifestPath,
            packageKind: packageKind,
            toolsVersion: toolsVersion,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        if manifest.toolsVersion != toolsVersion {
            throw StringError("Invalid manifest version")
        }

        let validator = ManifestValidator(manifest: manifest, sourceControlValidator: NOOPManifestSourceControlValidator(), fileSystem: fileSystem)
        let diagnostics = validator.validate()
        return (manifest: manifest, diagnostics: diagnostics)
    }
}

fileprivate struct NOOPManifestSourceControlValidator: ManifestSourceControlValidator {
    func isValidRefFormat(_ revision: String) -> Bool {
        true
    }

    func isValidDirectory(_ path: AbsolutePath) -> Bool {
        true
    }
}
