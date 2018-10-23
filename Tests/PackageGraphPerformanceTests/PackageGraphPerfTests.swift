/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph
import PackageModel
import TestSupport

class PackageGraphPerfTests: XCTestCasePerf {

    func testLoading100Packages() throws {
        let N = 100
        let files = (1...N).map { "/Foo\($0)/source.swift" }
        let fs = InMemoryFileSystem(emptyFiles: files)

        var externalManifests = [Manifest]()
        var rootManifests: [Manifest]!
        for pkg in 1...N {
            let name = "Foo\(pkg)"
            let url = "/" + name

            let dependencies: [PackageDependencyDescription]
            let targets: [TargetDescription]
            // Create package.
            if pkg == N {
                dependencies = []
                targets = [TargetDescription(name: name, path: ".")]
            } else {
                let depUrl = "/Foo\(pkg + 1)"
                dependencies = [PackageDependencyDescription(url: depUrl, requirement: .upToNextMajor(from: "1.0.0"))]
                targets = [TargetDescription(name: name, dependencies: [.byName(name: "Foo\(pkg + 1)")], path: ".")]
            }
            // Create manifest.
            let manifest = Manifest(
                name: name,
                path: AbsolutePath(url).appending(component: Manifest.filename),
                url: url,
                version: "1.0.0",
                manifestVersion: .v4,
                dependencies: dependencies,
                products: [
                    ProductDescription(name: name, targets: [name])
                ],
                targets: targets
            )
            if pkg == 1 {
                rootManifests = [manifest]
            } else {
                externalManifests.append(manifest)
            }
        }

        measure {
            let diagnostics = DiagnosticsEngine()
            let g = PackageGraphLoader().load(
                root: PackageGraphRoot(input: PackageGraphRootInput(packages: rootManifests.map({$0.path})), manifests: rootManifests),
                externalManifests: externalManifests,
                diagnostics: diagnostics,
                fileSystem: fs)
            XCTAssertEqual(g.packages.count, N)
            XCTAssertNoDiagnostics(diagnostics)
        }
    }
}
