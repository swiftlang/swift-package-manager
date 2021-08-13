/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import PackageModel
import PackageLoading

class PackageDescription5_5LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_5
    }

    func testPackageDependencies() throws {
        let manifest = """
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "/foo5", branch: "main"),
                   .package(url: "/foo7", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6"),
               ]
            )
            """
        loadManifest(manifest, toolsVersion: .v5_5) { manifest in
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo5"], .scm(location: "/foo5", requirement: .branch("main")))
            XCTAssertEqual(deps["foo7"], .scm(location: "/foo7", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        }
    }

    func testPlatforms() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               platforms: [
                   .macOS(.v12), .iOS(.v15),
                   .tvOS(.v15), .watchOS(.v8),
                   .macCatalyst(.v15), .driverKit(.v21),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.platforms, [
                PlatformDescription(name: "macos", version: "12.0"),
                PlatformDescription(name: "ios", version: "15.0"),
                PlatformDescription(name: "tvos", version: "15.0"),
                PlatformDescription(name: "watchos", version: "8.0"),
                PlatformDescription(name: "maccatalyst", version: "15.0"),
                PlatformDescription(name: "driverkit", version: "21.0"),
            ])
        }
    }
    
    func testTargetNameAcrossProductDecls() throws {
        let manifest = """
        import PackageDescription
        let package = Package(
            name: "Host",
            products: [
                .executable(name: "host", targets: ["HostExecutable"]),
                .library(name: "libHost", targets: ["Host"]),
            ],
            dependencies: [
            ],
            targets: [
                .target(
                    name: "HostExecutable",
                    dependencies: ["Host"]
                ),
                .target(
                    name: "Host",
                    dependencies: []
                ),
                .testTarget(
                    name: "HostTests",
                    dependencies: ["Host"]),
            ]
        )

        """
        XCTAssertManifestLoadThrows(manifest, packageKind: .root, onCatch: { (err, result) in
            result.check(diagnostic: .equal("target 'Host' should have a different (case-insensitive) name from products: [host]."), behavior: .error)
        })
    }
    
    func testTargetNameInProductDecl() throws {
        let manifest = """
            import PackageDescription
            let package = Package(
                name: "xyz",
                products: [
                    .executable(name: "foo", targets: ["Foo"]),
                    .library(name: "Foo", targets: ["FooKit"]),
                ],
                targets: [
                    .target(name: "Foo"),
                    .target(name: "FooKit"),
                ]
            )
            """
        
        XCTAssertManifestLoadThrows(manifest, packageKind: .root, onCatch: { (err, result) in
            result.check(diagnostic: .equal("target 'Foo' should have a different (case-insensitive) name from products: [foo]."), behavior: .error)
        })
    }
    
    func testTargetNameWithNonExecutableProduct() throws {
        let manifest = """
            import PackageDescription
            let package = Package(
                name: "xyz",
                products: [
                    .library(name: "foo", targets: ["Foo"]),
                ],
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """
        
        XCTAssertManifestLoadNoThrows(manifest, packageKind: .root)
    }
    
    func testPluginsAreUnavailable() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .buildTool()
                   ),
               ]
            )
            """
        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("expected manifest loading to fail, but it succeeded")
        }
        catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("expected an invalidManifestFormat error, but got: \(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.6"))
        }
    }
}
