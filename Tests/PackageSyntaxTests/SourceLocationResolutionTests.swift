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
import PackageSyntax

final class SourceLocationResolutionTests: XCTestCase {
    func testInvalidExplicitPackageDependencyNameLocationResolution() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/foo.swift",
            "/Bar/Sources/Baar/bar.swift",
            "/Baz/Sources/Baaz/baz.swift"
        )

        var diags: [String] = []
        let diagnostics = DiagnosticsEngine(handlers: [{diag in
            guard diag.behavior == .error else { return }
            if let resolvedLocation = (diag.location as? ManifestSourceLocation)?.resolveToSourceLocation() {
                diags.append("\(resolvedLocation.file ?? "<unknown>"):\(resolvedLocation.line ?? 0):\(resolvedLocation.column ?? 0): \(diag.description)")
            } else {
                diags.append("\(diag.location.description): \(diag.description)")
            }
        }])

        let manifest = """
            // swift-tools-version:5.3
            import PackageDescription

            let package = Package(
                name: "Foo",
                dependencies: [
                    .package(name: "Baaz", url: "/Baz", from: "1.0.0"),
                    .package(name: "Baar", url: "/Bar", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "Foo",
                        dependencies: [.product(name: "Bar", package: "Baar"),
                                       .product(name: "Baz", package: "Baaz")]),
                ]
            )
            """

        let manifestPath = AbsolutePath("/Foo/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }

        let swiftCompiler = Resources.default.swiftCompiler
        let rootManifest = tsc_await { (completion: @escaping (Manifest)->Void) in
            let resources = try! UserManifestResources(swiftCompiler: swiftCompiler, swiftCompilerFlags: [])
            let loader = ManifestLoader(manifestResources: resources)
            let toolsVersion = try! ToolsVersionLoader().load(at: manifestPath.parentDirectory, fileSystem: fs)
            loader.load(
                package: manifestPath.parentDirectory,
                baseURL: manifestPath.parentDirectory.pathString,
                toolsVersion: toolsVersion,
                packageKind: .root,
                fileSystem: fs,
                on: .global(),
                completion: { result in completion(try! result.get()) }
            )
        }

        _ = try loadPackageGraph(fs: fs, diagnostics: diagnostics,
            manifests: [
                rootManifest,
                Manifest.createV4Manifest(
                    name: "Bar",
                    path: "/Bar",
                    url: "/Bar",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Baar", type: .library(.automatic), targets: ["Baar"])
                    ],
                    targets: [
                        TargetDescription(name: "Baar"),
                    ]),
                Manifest.createV4Manifest(
                    name: "Baz",
                    path: "/Baz",
                    url: "/Baz",
                    packageKind: .local,
                    products: [
                        ProductDescription(name: "Baaz", type: .library(.automatic), targets: ["Baaz"])
                    ],
                    targets: [
                        TargetDescription(name: "Baaz"),
                    ]),
            ]
        )

        XCTAssertEqual(diags, [
            "/Foo/Package.swift:7:9: \'Foo\' dependency on \'/Baz\' has an explicit name \'Baaz\' which does not match the name \'Baz\' set for \'/Baz\'",
            "/Foo/Package.swift:8:9: \'Foo\' dependency on \'/Bar\' has an explicit name \'Baar\' which does not match the name \'Bar\' set for \'/Bar\'"
        ])
    }
}
