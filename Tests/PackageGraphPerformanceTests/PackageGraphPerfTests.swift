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
import PackageDescription
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
            // Create package.
            let package: PackageDescription.Package
            if pkg == N {
                package = Package(name: name)
            } else {
                let depUrl = "/Foo\(pkg + 1)"
                package = Package(name: name, dependencies: [.Package(url: depUrl, majorVersion: 1)])
            }
            // Create manifest.
            let manifest = Manifest(
                path: AbsolutePath(url).appending(component: Manifest.filename),
                url: url,
                package: .v3(package),
                version: "1.0.0"
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
                root: PackageGraphRoot(manifests: rootManifests),
                externalManifests: externalManifests,
                diagnostics: diagnostics,
                fileSystem: fs)
            XCTAssertEqual(g.packages.count, N)
            XCTAssertFalse(diagnostics.hasErrors)
        }
    }
}
