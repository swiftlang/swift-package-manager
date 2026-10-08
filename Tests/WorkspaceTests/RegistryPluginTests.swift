//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import Testing
@testable import Workspace

struct RegistryPluginTests {
    @Test
    func `registry transformation preserves plugin products`() async throws {
        for mode in [WorkspaceConfiguration.SourceControlToRegistryDependencyTransformation.identity, .swizzle] {
            let workspace = try await MockWorkspace(
                sandbox: AbsolutePath("/tmp/ws/"),
                fileSystem: InMemoryFileSystem(),
                roots: [
                    MockPackage(
                        name: "Root",
                        path: "root",
                        targets: [
                            MockTarget(name: "RootTarget", pluginUsages: [
                                .plugin(name: "BuildToolPlugin", package: "PluginPackage"),
                                .plugin(name: "LocalPlugin", package: nil),
                            ]),
                            MockTarget(name: "LocalPlugin", type: .plugin, pluginCapability: .buildTool),
                        ],
                        products: [],
                        dependencies: [
                            .sourceControl(url: "https://git/org/PluginPackage", requirement: .exact("1.0.0")),
                        ],
                        toolsVersion: .v6_0,
                    ),
                ],
                packages: [
                    MockPackage(
                        name: "PluginPackage",
                        url: "https://git/org/PluginPackage",
                        targets: [
                            MockTarget(name: "BuildToolPlugin", type: .plugin, pluginCapability: .buildTool),
                        ],
                        products: [
                            MockProduct(name: "BuildToolPlugin", modules: ["BuildToolPlugin"], type: .plugin),
                        ],
                        versions: ["1.0.0"],
                        toolsVersion: .v6_0,
                    ),
                    MockPackage(
                        name: "PluginPackage",
                        identity: "org.pluginpackage",
                        alternativeURLs: ["https://git/org/PluginPackage"],
                        targets: [
                            MockTarget(name: "BuildToolPlugin", type: .plugin, pluginCapability: .buildTool),
                        ],
                        products: [
                            MockProduct(name: "BuildToolPlugin", modules: ["BuildToolPlugin"], type: .plugin),
                        ],
                        versions: ["1.0.0"],
                        toolsVersion: .v6_0,
                    ),
                ],
            )
            workspace.sourceControlToRegistryDependencyTransformation = mode

            try await workspace.checkPackageGraph(roots: ["root"]) { graph, diagnostics in
                expectNoDiagnostics(diagnostics)
                try PackageGraphTester(graph) { result in
                    result.check(packages: "org.pluginpackage", "Root")
                    try result.checkTarget("RootTarget") { target in
                        target.check(dependencies: "BuildToolPlugin", "LocalPlugin")
                    }
                }
            }
            let dependencies = try await workspace.getOrCreateWorkspace().state.dependencies
            let dependency = try #require(dependencies[.plain("org.pluginpackage")])
            switch mode {
            case .identity:
                guard case .sourceControlCheckout(let checkout) = dependency.state else {
                    Issue.record("Expected a Git checkout, found \(dependency.state)")
                    return
                }
                #expect(checkout.version == "1.0.0")
            case .swizzle:
                guard case .registryDownload(let version, _) = dependency.state else {
                    Issue.record("Expected a registry download, found \(dependency.state)")
                    return
                }
                #expect(version == "1.0.0")
            case .disabled:
                Issue.record("Unexpected disabled registry transformation")
            }
        }
    }
}
