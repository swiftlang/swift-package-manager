/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class PackageGraphPerfTests: XCTestCasePerf {

    func testLoading100Packages() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        let N = 100
        let files = (1...N).map { "/Foo\($0)/source.swift" }
        let fs = InMemoryFileSystem(emptyFiles: files)

        let identityResolver = DefaultIdentityResolver()
        var externalManifests = OrderedCollections.OrderedDictionary<PackageIdentity, (manifest: Manifest, fs: FileSystem)>()
        var rootManifest: Manifest!
        for pkg in 1...N {
            let name = "Foo\(pkg)"
            let location = "/" + name

            let dependencies: [PackageDependency]
            let targets: [TargetDescription]
            // Create package.
            if pkg == N {
                dependencies = []
                targets = [try TargetDescription(name: name, path: ".")]
            } else {
                let depName = "Foo\(pkg + 1)"
                let depUrl = "/\(depName)"
                dependencies = [.localSourceControl(deprecatedName: depName, path: .init(depUrl), requirement: .upToNextMajor(from: "1.0.0"))]
                targets = [try TargetDescription(name: name, dependencies: [.byName(name: depName, condition: nil)], path: ".")]
            }
            // Create manifest.
            let isRoot = pkg == 1
            let manifest = Manifest(
                displayName: name,
                path: AbsolutePath(location).appending(component: Manifest.filename),
                packageKind: isRoot ? .root(.init(location)) : .localSourceControl(.init(location)),
                packageLocation: location,
                platforms: [],
                version: "1.0.0",
                toolsVersion: .v4_2,
                dependencies: dependencies,
                products: [
                    try ProductDescription(name: name, type: .library(.automatic), targets: [name])
                ],
                targets: targets
            )
            if isRoot {
                rootManifest = manifest
            } else {
                let identity = try identityResolver.resolveIdentity(for: manifest.packageKind)
                externalManifests[identity] = (manifest, fs)
            }
        }

        measure {
            let observability = ObservabilitySystem.makeForTesting()
            let g = try! PackageGraph.load(
                root: PackageGraphRoot(input: PackageGraphRootInput(packages: [rootManifest.path]), manifests: [rootManifest.path: rootManifest]),
                identityResolver: identityResolver,
                externalManifests: externalManifests,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
            XCTAssertEqual(g.packages.count, N)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }
    }
}
