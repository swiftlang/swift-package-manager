/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import PackageModel
import SPMTestSupport

class ManifestTests: XCTestCase {
    func testRequiredTargets() throws {
        let products = [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
        ]

        let targets = [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: []),
            TargetDescription(name: "FooBar", dependencies: []),
        ]

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5_2,
                packageKind: .root,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.targetsRequired(for: .everything).map({ $0.name }).sorted(), [
                "Bar",
                "Baz",
                "Foo",
                "FooBar",
            ])
        }

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5_2,
                packageKind: .local,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.targetsRequired(for: .specific(["Foo", "Bar"])).map({ $0.name }).sorted(), [
                "Bar",
                "Baz",
                "Foo",
            ])
        }
    }

    func testRequiredDependencies() throws {
        let dependencies = [
            PackageDependencyDescription(name: "Bar1", url: "/Bar1", requirement: .upToNextMajor(from: "1.0.0")),
            PackageDependencyDescription(name: "Bar2", url: "/Bar2", requirement: .upToNextMajor(from: "1.0.0")),
            PackageDependencyDescription(name: "Bar3", url: "/Bar3", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo1"])
        ]

        let targets = [
            TargetDescription(name: "Foo1", dependencies: ["Foo2", "Bar1"]),
            TargetDescription(name: "Foo2", dependencies: [.product(name: "B2", package: "Bar2")]),
            TargetDescription(name: "Foo3", dependencies: ["Bar3"]),
        ]

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5,
                packageKind: .root,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.dependenciesRequired(for: .everything).map({ $0.declaration.name }).sorted(), [
                "Bar1",
                "Bar2",
                "Bar3",
            ])
        }

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5,
                packageKind: .local,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.dependenciesRequired(for: .specific(["Foo"])).map({ $0.declaration.name }).sorted(), [
                "Bar1", // Foo → Foo1 → Bar1
                "Bar2", // Foo → Foo1 → Foo2 → Bar2
                "Bar3", // Foo → Foo1 → Bar1 → could be from any package due to pre‐5.2 tools version.
            ])
        }

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5_2,
                packageKind: .root,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.dependenciesRequired(for: .everything).map({ $0.declaration.name }).sorted(), [
                "Bar1",
                "Bar2",
                "Bar3",
            ])
        }

        do {
            let manifest = Manifest.createManifest(
                name: "Foo",
                path: "/Foo",
                url: "/Foo",
                v: .v5_2,
                packageKind: .local,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.dependenciesRequired(for: .specific(["Foo"])).map({ $0.declaration.name }).sorted(), [
                "Bar1", // Foo → Foo1 → Bar1
                "Bar2", // Foo → Foo1 → Foo2 → Bar2
                // (Bar3 is unreachable.)
            ])
        }
    }
}
