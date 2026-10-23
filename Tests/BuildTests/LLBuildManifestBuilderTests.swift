//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
@testable import Build
import LLBuildManifest

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

import PackageModel
import struct SPMBuildCore.BuildParameters

import _InternalBuildTestSupport
@_spi(SwiftPMInternal)
import _InternalTestSupport

import Testing

struct LLBuildManifestBuilderTests {
    @Test
    func createProductCommand() async throws {
        let pkg = AbsolutePath("/pkg")
        let fs = InMemoryFileSystem(
            emptyFiles:
                pkg.appending(components: "Sources", "exe", "main.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        // macOS, release build

        var plan = try await mockBuildPlan(
            environment: BuildEnvironment(
                platform: .macOS,
                configuration: .release
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        var result = try BuildPlanResult(plan: plan)
        var buildProduct = try result.buildProduct(for: "exe")

        var llbuild = LLBuildManifestBuilder(
            plan,
            fileSystem: localFileSystem,
            observabilityScope: observability.topScope
        )
        try llbuild.createProductCommand(buildProduct)

        var basicReleaseCommandNames = [
            AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/release/exe.product/Objects.LinkFileList").pathString,
            "<exe-\(plan.destinationBuildParameters.triple)-release.exe>",
            "C.exe-\(plan.destinationBuildParameters.triple)-release.exe",
        ]

        #expect(llbuild.manifest.commands.map(\.key).sorted() == basicReleaseCommandNames.sorted())

        // macOS, debug build

        plan = try await mockBuildPlan(
            environment: BuildEnvironment(
                platform: .macOS,
                configuration: .debug
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        let entitlementsCommandName = "C.exe-\(plan.destinationBuildParameters.triple)-debug.exe-entitlements"
        var basicDebugCommandNames = [
            AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe.product/Objects.LinkFileList").pathString,
            "<exe-\(plan.destinationBuildParameters.triple)-debug.exe>",
            "C.exe-\(plan.destinationBuildParameters.triple)-debug.exe",
        ]

        #expect(llbuild.manifest.commands.map(\.key).sorted() == (basicDebugCommandNames + [
            AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe-entitlement.plist").pathString,
            entitlementsCommandName,
        ]).sorted())

        let entitlementsCommand = try #require(
            llbuild.manifest.commands[entitlementsCommandName]?.tool as? ShellTool,
            "unexpected entitlements command type"
        )

        #expect(entitlementsCommand.inputs == [
            .file("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe", isMutated: true),
            .file("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe-entitlement.plist"),
        ])
        #expect(entitlementsCommand.outputs == [
            .virtual("exe-\(plan.destinationBuildParameters.triple)-debug.exe-CodeSigning"),
        ])

        // Linux, release build

        plan = try await mockBuildPlan(
            environment: BuildEnvironment(
                platform: .linux,
                configuration: .release
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        basicReleaseCommandNames = [
            AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/release/exe.product/Objects.LinkFileList").pathString,
            "<exe-\(plan.destinationBuildParameters.triple)-release.exe>",
            "C.exe-\(plan.destinationBuildParameters.triple)-release.exe",
        ]

        #expect(llbuild.manifest.commands.map(\.key).sorted() == basicReleaseCommandNames.sorted())

        // Linux, debug build

        plan = try await mockBuildPlan(
            environment: BuildEnvironment(
                platform: .linux,
                configuration: .debug
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        basicDebugCommandNames = [
            AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe.product/Objects.LinkFileList").pathString,
            "<exe-\(plan.destinationBuildParameters.triple)-debug.exe>",
            "C.exe-\(plan.destinationBuildParameters.triple)-debug.exe",
        ]

        #expect(llbuild.manifest.commands.map(\.key).sorted() == basicDebugCommandNames.sorted())
    }

    /// Verifies that two modules with the same name but different triples don't share same build manifest keys.
    @Test
    func toolsBuildTriple() async throws {
        let (graph, fs, scope) = try macrosPackageGraph()
        let productsTriple = Triple.x86_64MacOS
        let toolsTriple = Triple.arm64Linux

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                buildSystemKind: .native,
                shouldLinkStaticSwiftStdlib: true,
                triple: productsTriple
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                buildSystemKind: .native,
                triple: toolsTriple
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        let builder = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: scope)
        let manifest = try builder.generateManifest(at: "/manifest")

        #expect(manifest.commands["C.SwiftSyntax-aarch64-unknown-linux-gnu-debug-tool.module"] != nil)
        // Ensure that Objects.LinkFileList is -tool suffixed.
        #expect(manifest.commands[AbsolutePath("/path/to/build/aarch64-unknown-linux-gnu/debug/MMIOMacros-tool.product/Objects.LinkFileList").pathString] != nil)
    }

    /// Verifies the DLLs in an artifact bundle are copied to the output directory on Windows only
    @Test func windowsDLLsInArtifactBundle() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPkg/Sources/MyExe/MyExe.swift"
            ]
        )

        try fs.writeFileContents("/MyPkg/my.artifactbundle/info.json", string: """
            {
              "schemaVersion": "1.0",
              "artifacts": {
                "MyBinaryLib": {
                  "version": "1",
                  "type": "staticLibrary",
                  "variants": [
                    {
                      "path": "x86_64-unknown-windows-msvc/MyBinaryLib.lib",
                      "staticLibraryMetadata": {
                        "headerPaths": [
                          "include"
                        ]
                      },
                      "supportedTriples": [
                        "x86_64-unknown-windows-msvc"
                      ]
                    },
                    {
                      "path": "arm64-apple-macosx/libMyBinaryLib.a",
                      "staticLibraryMetadata": {
                        "headerPaths": [
                          "include"
                        ]
                      },
                      "supportedTriples": [
                        "arm64-apple-macosx"
                      ]
                    },
                  ]
                },
                "MyBinaryLib.DLL": {
                  "type": "experimentalWindowsDLL",
                  "version": "1.0.0",
                  "variants": [
                    {
                      "path": "x86_64-unknown-windows-msvc/MyBinaryLib.dll",
                      "supportedTriples": [
                        "x86_64-unknown-windows-msvc"
                      ]
                    }
                  ]
                }
              }
            }
            """)

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "MyPkg",
                    path: "/MyPkg",
                    products: [
                        .init(name: "MyExe", type: .executable, targets: ["MyExe"])
                    ],
                    targets: [
                        .init(name: "MyBinaryLib", path: "dist", type: .binary),
                        .init(name: "MyExe", dependencies: ["MyBinaryLib"], type: .executable),
                    ]
                )
            ],
            binaryArtifacts: [
                .plain("MyPkg"): [
                    "MyBinaryLib": .init(
                        kind: .artifactsArchive(types: [
                            .staticLibrary,
                            .executable,
                        ]),
                        originURL: nil, path: "/MyPkg/my.artifactbundle")
                ]
            ],
            observabilityScope: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics)

        let windowsPlan = try await mockBuildPlan(
            triple: .x86_64Windows,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics)

        let windowsBuild = LLBuildManifestBuilder(windowsPlan, fileSystem: fs, observabilityScope: observability.topScope)
        #expect(!observability.hasErrorDiagnostics)
        let windowsManifest = try windowsBuild.generateManifest(at: "/windows.manifest")

        let windowsLink = try #require(windowsManifest.commands["C.MyExe-x86_64-unknown-windows-msvc-debug.exe"])
        let windowsLinkTool = try #require(windowsLink.tool as? ShellTool)
        #expect(windowsLinkTool.arguments.contains("-lMyBinaryLib"))

        let dll: AbsolutePath = "/path/to/build/x86_64-unknown-windows-msvc/debug/MyBinaryLib.dll"
        let windowsDLLCopy = try #require(windowsManifest.commands[dll.pathString])
        let windowsDLLCopyTool = try #require(windowsDLLCopy.tool as? CopyTool)
        let windowsDLLOutput: Node = .file("/path/to/build/x86_64-unknown-windows-msvc/debug/MyBinaryLib.dll")
        #expect(
            windowsDLLCopyTool.inputs == [.file("/MyPkg/my.artifactbundle/x86_64-unknown-windows-msvc/MyBinaryLib.dll")]
            && windowsDLLCopyTool.outputs == [windowsDLLOutput]
        )

        // Make sure the copy command is consumed in the build graph
        let consumerCommand = try #require(windowsManifest.commands.filter({ $0.value.tool.inputs.contains(windowsDLLOutput) }).only)
        #expect(consumerCommand.key == "C.MyExe-x86_64-unknown-windows-msvc-debug.module")

        let macosPlan = try await mockBuildPlan(
            triple: .arm64MacOS,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics)

        let macosBuild = LLBuildManifestBuilder(macosPlan, fileSystem: fs, observabilityScope: observability.topScope)
        #expect(!observability.hasErrorDiagnostics)
        let macosManifest = try macosBuild.generateManifest(at: "/macos.manifest")

        let macosLink = try #require(macosManifest.commands["C.MyExe-arm64-apple-macosx-debug.exe"])
        let macosLinkTool = try #require(macosLink.tool as? ShellTool)
        #expect(macosLinkTool.arguments.contains("-lMyBinaryLib"))

        #expect(!macosManifest.commands.contains(where: {
            $0.value.tool.inputs.contains(.file("/MyPkg/my.artifactbundle/x86_64-unknown-windows-msvc/MyBinaryLib.dll"))
        }))
    }

    /// Verifies that the binary frameworks a module depends on are listed in a stable, sorted order in the
    /// compile command inputs and in the link arguments. llbuild includes the ordered inputs and arguments in its
    /// command signatures, so any variation between plans would make it rebuild the module unnecessarily.
    @Test func binaryTargetInputsAndLinkArgumentsAreDeterministic() async throws {
        let pkg = AbsolutePath("/Pkg")
        // Declared in an order that differs from the sorted one.
        let frameworks = ["Zeta", "Gamma", "Alpha", "Epsilon", "Beta", "Delta"]
        let sortedFrameworks = frameworks.sorted()

        let fs = InMemoryFileSystem(
            emptyFiles:
            pkg.appending(components: "Sources", "Library", "Library.swift").pathString,
            pkg.appending(components: "Sources", "CLibrary", "library.c").pathString,
            pkg.appending(components: "Sources", "CLibrary", "include", "library.h").pathString
        )
        for framework in frameworks {
            let xcframework = pkg.appending(component: "\(framework).xcframework")
            try fs.createDirectory(
                xcframework.appending(components: "macos-arm64", "\(framework).framework"),
                recursive: true
            )
            try fs.writeFileContents(xcframework.appending(component: "Info.plist"), string: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>AvailableLibraries</key>
                    <array>
                        <dict>
                            <key>LibraryIdentifier</key>
                            <string>macos-arm64</string>
                            <key>LibraryPath</key>
                            <string>\(framework).framework</string>
                            <key>SupportedArchitectures</key>
                            <array>
                                <string>arm64</string>
                            </array>
                            <key>SupportedPlatform</key>
                            <string>macos</string>
                        </dict>
                    </array>
                    <key>CFBundlePackageType</key>
                    <string>XFWK</string>
                    <key>XCFrameworkFormatVersion</key>
                    <string>1.0</string>
                </dict>
                </plist>
                """)
        }

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: pkg,
                    products: [
                        ProductDescription(name: "Library", type: .library(.dynamic), targets: ["Library"]),
                        ProductDescription(name: "CLibrary", type: .library(.dynamic), targets: ["CLibrary"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Library",
                            dependencies: frameworks.map { .byName(name: $0, condition: nil) }
                        ),
                        TargetDescription(
                            name: "CLibrary",
                            dependencies: frameworks.map { .byName(name: $0, condition: nil) }
                        ),
                    ] + frameworks.map {
                        try TargetDescription(name: $0, path: "\($0).xcframework", type: .binary)
                    }
                ),
            ],
            binaryArtifacts: [
                .plain("pkg"): Dictionary(uniqueKeysWithValues: frameworks.map {
                    ($0, .init(kind: .xcframework, originURL: nil, path: pkg.appending(component: "\($0).xcframework")))
                }),
            ],
            observabilityScope: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics)

        func generateManifest() async throws -> LLBuildManifest {
            let plan = try await mockBuildPlan(
                triple: .arm64MacOS,
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
            let builder = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            return try builder.generateManifest(at: "/manifest")
        }
        func frameworkInputs(of command: Command) -> [String] {
            command.tool.inputs.filter { $0.kind == .directory && $0.name.hasSuffix(".framework") }.map(\.name)
        }
        func linkedFrameworks(of command: Command) throws -> [String] {
            let arguments = try #require(command.tool as? ShellTool).arguments
            return zip(arguments, arguments.dropFirst()).filter { $0.0 == "-framework" }.map(\.1)
        }

        let manifest = try await generateManifest()
        #expect(!observability.hasErrorDiagnostics)

        let buildPath = AbsolutePath("/path/to/build/arm64-apple-macosx/debug")
        let expectedInputs = sortedFrameworks.map { buildPath.appending(component: "\($0).framework").pathString }

        let swiftCompile = try #require(manifest.commands["C.Library-arm64-apple-macosx-debug.module"])
        #expect(frameworkInputs(of: swiftCompile) == expectedInputs)

        let clangCompiles = manifest.commands.values.filter { $0.tool is ClangTool }
        #expect(clangCompiles.count == 1)
        let clangCompile = try #require(clangCompiles.first)
        #expect(frameworkInputs(of: clangCompile) == expectedInputs)

        let libraryLink = try #require(manifest.commands["C.Library-arm64-apple-macosx-debug.dylib"])
        #expect(try linkedFrameworks(of: libraryLink) == sortedFrameworks)
        let clibraryLink = try #require(manifest.commands["C.CLibrary-arm64-apple-macosx-debug.dylib"])
        #expect(try linkedFrameworks(of: clibraryLink) == sortedFrameworks)

        // Planning the same graph again must produce identical inputs and link arguments for every command.
        let secondManifest = try await generateManifest()
        #expect(!observability.hasErrorDiagnostics)
        #expect(secondManifest.commands.mapValues(\.tool.inputs) == manifest.commands.mapValues(\.tool.inputs))
        #expect(
            secondManifest.commands.compactMapValues { ($0.tool as? ShellTool)?.arguments }
                == manifest.commands.compactMapValues { ($0.tool as? ShellTool)?.arguments }
        )
    }
}
