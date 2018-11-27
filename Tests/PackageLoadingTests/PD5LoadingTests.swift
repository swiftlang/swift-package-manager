/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility
import TestSupport
import PackageModel
import PackageLoading

// FIXME: We should share the infra with other loading tests.
class PackageDescription5LoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(manifestResources: Resources.default)

    private func loadManifestThrowing(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: AbsolutePath.root.asString,
            manifestVersion: .v5,
            fileSystem: fs)
        guard m.manifestVersion == .v5 else {
            return XCTFail("Invalid manfiest version")
        }
        body(m)
    }

    private func loadManifest(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        do {
            try loadManifestThrowing(contents, line: line, body: body)
        } catch ManifestParseError.invalidManifestFormat(let error) {
            print(error)
            XCTFail(file: #file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    func testBasics() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["Foo"]),
                ],
                dependencies: [
                    .package(url: "/foo1", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1", .product(name: "product"), .target(name: "target")]),
                    .testTarget(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")

            // Check targets.
            let targets = Dictionary(items:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))
            let foo = targets["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.dependencies, ["dep1", .product(name: "product"), .target(name: "target")])

            let bar = targets["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])

            // Check dependencies.
            let deps = Dictionary(items: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))

            // Check products.
            let products = Dictionary(items: manifest.products.map{ ($0.name, $0) })

            let tool = products["tool"]!
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])
            XCTAssertEqual(tool.type, .executable)

            let fooProduct = products["Foo"]!
            XCTAssertEqual(fooProduct.name, "Foo")
            XCTAssertEqual(fooProduct.type, .library(.automatic))
            XCTAssertEqual(fooProduct.targets, ["Foo"])
        }
    }

    func testSwiftLanguageVersion() throws {
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v4, .v4_2, .v5]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.swiftLanguageVersions, [.v4, .v4_2, .v5])
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v3]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.unsupportedAPI(api, supportedVersions) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(api, "PackageDescription.SwiftVersion.v3")
            XCTAssertEqual(supportedVersions, [.v4_2])
        }
    }

    func testPlatforms() throws {
        // Sanity check.
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               _platforms: [
                   .macOS(.v10_13), .iOS(.version("12.2")),
                   .tvOS(.v12), .watchOS(.v3), .linux(), .all,
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.platforms, [
                PlatformDescription(name: "macos", version: "10.13"),
                PlatformDescription(name: "ios", version: "12.2"),
                PlatformDescription(name: "tvos", version: "12.0"),
                PlatformDescription(name: "watchos", version: "3.0"),
                PlatformDescription(name: "linux"),
                .all
            ])
        }

        // Test invalid custom versions.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               _platforms: [
                   .macOS(.version("11.2")), .iOS(.version("12.x.2")), .tvOS(.version("10..2")),
               ]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("Unexpected success")
        } catch ManifestParseError.runtimeManifestErrors(let errors) {
            XCTAssertEqual(errors, ["invalid macOS version string: 11.2", "invalid iOS version string: 12.x.2", "invalid tvOS version string: 10..2"])
        }

        // Duplicates.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               _platforms: [
                   .macOS(.v10_10), .macOS(.v10_12),
               ]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("Unexpected success")
        } catch ManifestParseError.runtimeManifestErrors(let errors) {
            XCTAssertEqual(errors, ["found multiple declaration for the platform: macos"])
        }

        // Empty.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               _platforms: []
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("Unexpected success")
        } catch ManifestParseError.runtimeManifestErrors(let errors) {
            XCTAssertEqual(errors, ["supported platforms can't be empty"])
        }
    }

    func testBuildSettings() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .target(
                       name: "Foo",
                       _cSettings: [
                           .headerSearchPath("path/to/foo"),
                           .define("C", .when(platforms: [.linux])),
                           .define("CC", to: "4", .when(platforms: [.linux], configuration: .release)),
                       ],
                       _cxxSettings: [
                           .headerSearchPath("path/to/bar"),
                           .define("CXX"),
                       ],
                       _swiftSettings: [
                           .define("SWIFT", .when(configuration: .release)),
                           .define("SWIFT_DEBUG", .when(platforms: [.watchOS], configuration: .debug)),
                       ],
                       _linkerSettings: [
                           .linkedLibrary("libz"),
                           .linkedFramework("CoreData", .when(platforms: [.macOS, .tvOS])),
                       ]
                   ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            let settings = manifest.targets[0].settings

            XCTAssertEqual(settings[0], .init(tool: .c, name: .headerSearchPath, value: ["path/to/foo"]))
            XCTAssertEqual(settings[1], .init(tool: .c, name: .define, value: ["C"], condition: .init(platformNames: ["linux"])))
            XCTAssertEqual(settings[2], .init(tool: .c, name: .define, value: ["CC=4"], condition: .init(platformNames: ["linux"], config: "release")))

            XCTAssertEqual(settings[3], .init(tool: .cxx, name: .headerSearchPath, value: ["path/to/bar"]))
            XCTAssertEqual(settings[4], .init(tool: .cxx, name: .define, value: ["CXX"]))

            XCTAssertEqual(settings[5], .init(tool: .swift, name: .define, value: ["SWIFT"], condition: .init(config: "release")))
            XCTAssertEqual(settings[6], .init(tool: .swift, name: .define, value: ["SWIFT_DEBUG"], condition: .init(platformNames: ["watchos"], config: "debug")))

            XCTAssertEqual(settings[7], .init(tool: .linker, name: .linkedLibrary, value: ["libz"]))
            XCTAssertEqual(settings[8], .init(tool: .linker, name: .linkedFramework, value: ["CoreData"], condition: .init(platformNames: ["macos", "tvos"])))
        }
    }
}
