/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch

import TSCBasic
import PackageLoading
import PackageModel
import SourceControl
import TSCUtility

/// Local package container.
///
/// This class represent packages that are referenced locally in the file system.
/// There is no need to perform any git operations on such packages and they
/// should be used as-is. Infact, they might not even have a git repository.
/// Examples: Root packages, local dependencies, edited packages.
public class LocalPackageContainer: BasePackageContainer  {

    /// The file system that shoud be used to load this package.
    let fs: FileSystem

    private var _manifest: Manifest? = nil
    private func loadManifest() throws -> Manifest {
        if let manifest = _manifest {
            return manifest
        }

        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: AbsolutePath(identifier.path), fileSystem: fs)

        // Validate the tools version.
        try toolsVersion.validateToolsVersion(self.currentToolsVersion, packagePath: identifier.path)

        // Load the manifest.
        _manifest = try manifestLoader.load(
            package: AbsolutePath(identifier.path),
            baseURL: identifier.path,
            version: nil,
            toolsVersion: toolsVersion,
            packageKind: identifier.kind,
            fileSystem: fs)
        return _manifest!
    }

    public override func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return try loadManifest().dependencyConstraints(productFilter: productFilter, config: config)
    }

    public override func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try loadManifest()
        return identifier.with(newName: manifest.name)
    }

    public init(
        _ identifier: Identifier,
        config: SwiftPMConfig,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fs: FileSystem = localFileSystem
    ) {
        assert(URL.scheme(identifier.path) == nil, "unexpected scheme \(URL.scheme(identifier.path)!) in \(identifier.path)")
        self.fs = fs
        super.init(
            identifier,
            config: config,
            manifestLoader: manifestLoader,
            toolsVersionLoader: toolsVersionLoader,
            currentToolsVersion: currentToolsVersion
        )
    }
}

extension LocalPackageContainer: CustomStringConvertible  {
    public var description: String {
        return "LocalPackageContainer(\(identifier.path))"
    }
}
