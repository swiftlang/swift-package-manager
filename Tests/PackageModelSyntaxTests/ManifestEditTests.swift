//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
import PackageModel
import PackageModelSyntax
import _InternalTestSupport
@_spi(FixItApplier) import SwiftIDEUtils
import SwiftParser
import SwiftSyntax
import struct TSCUtility.Version
import XCTest

/// Assert that applying the given edit/refactor operation to the manifest
/// produces the expected manifest source file and the expected auxiliary
/// files.
func assertManifestRefactor(
    _ originalManifest: SourceFileSyntax,
    expectedManifest: SourceFileSyntax,
    expectedAuxiliarySources: [RelativePath: SourceFileSyntax] = [:],
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: (SourceFileSyntax) throws -> PackageEditResult
) rethrows {
    let edits = try operation(originalManifest)
    let editedManifestSource = FixItApplier.apply(
        edits: edits.manifestEdits,
        to: originalManifest
    )

    let editedManifest = Parser.parse(source: editedManifestSource)
    assertStringsEqualWithDiff(
        editedManifest.description,
        expectedManifest.description,
        file: file,
        line: line
    )

    // Check all of the auxiliary sources.
    for (auxSourcePath, auxSourceSyntax) in edits.auxiliaryFiles {
        guard let expectedSyntax = expectedAuxiliarySources[auxSourcePath] else {
            XCTFail("unexpected auxiliary source file \(auxSourcePath)")
            return
        }

        assertStringsEqualWithDiff(
            auxSourceSyntax.description,
            expectedSyntax.description,
            file: file,
            line: line
        )
    }

    XCTAssertEqual(
        edits.auxiliaryFiles.count,
        expectedAuxiliarySources.count,
        "didn't get all of the auxiliary files we expected"
    )
}

class ManifestEditTests: XCTestCase {
    static let swiftSystemURL: String = "https://github.com/apple/swift-system.git"
    static let swiftSystemPackageDependency: MappablePackageDependency.Kind = .sourceControl(
        name: nil,
        location: swiftSystemURL,
        requirement: .branch("main")
    )
    func testAddPackageDependencyExistingComma() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1"),
                ]
            )
            """, expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", branch: "main"),
                ]
            )
            """) { manifest in
                try AddPackageDependency.addPackageDependency(
                    .sourceControl(name: nil, location: Self.swiftSystemURL, requirement: .branch("main")),
                    to: manifest
                )
            }
    }

    func testAddPackageDependencyExistingNoComma() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1")
                ]
            )
            """, expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", exact: "510.0.0"),
                ]
            )
            """) { manifest in
                try AddPackageDependency.addPackageDependency(
                    .sourceControl(name: nil, location: Self.swiftSystemURL, requirement: .exact("510.0.0")),
                    to: manifest
                )
            }
    }

    func testAddPackageDependencyExistingAppended() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1")
                ] + []
            )
            """, expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                  .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1"),
                  .package(url: "https://github.com/apple/swift-system.git", from: "510.0.0"),
                ] + []
            )
            """) { manifest in
                let versionRange = Range<Version>.upToNextMajor(from: Version(510, 0, 0))

                return try AddPackageDependency.addPackageDependency(
                    .sourceControl(name: nil, location: Self.swiftSystemURL, requirement: .range(versionRange)),
                    to: manifest
                )
        }
    }

    func testAddPackageDependencyExistingOneLine() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [ .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1") ]
            )
            """, expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [ .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.1"), .package(url: "https://github.com/apple/swift-system.git", from: "510.0.0"),]
            )
            """) { manifest in
                let versionRange = Range<Version>.upToNextMajor(from: Version(510, 0, 0))

                return try AddPackageDependency.addPackageDependency(
                    .sourceControl(name: nil, location: Self.swiftSystemURL, requirement: .range(versionRange)),
                    to: manifest
                )
        }
    }
    func testAddPackageDependencyExistingEmpty() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [ ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", "508.0.0" ..< "510.0.0"),
                ]
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                .sourceControl(name: nil, location: Self.swiftSystemURL, requirement: .range(Version(508,0,0)..<Version(510,0,0))),
                to: manifest
            )
        }
    }

    func testAddPackageDependencyNoExistingAtEnd() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages"
            )
            """, 
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", branch: "main"),
                ]
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: manifest
            )
        }
    }

    func testAddPackageDependencyNoExistingMiddle() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: []
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-system.git", branch: "main"),
                ],
                targets: []
            )
            """) { manifest in
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: manifest
            )
        }
    }

    func testAddPackageDependencyErrors() {
        XCTAssertThrows(
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: """
                // swift-tools-version: 5.5
                let package: Package = .init(
                    name: "packages"
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .cannotFindPackage = error {
                return true
            } else {
                return false
            }
        }

        XCTAssertThrows(
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: """
                // swift-tools-version: 5.5
                let package = Package(
                    name: "packages",
                    dependencies: blah
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .cannotFindArrayLiteralArgument(argumentName: "dependencies", node: _) = error {
                return true
            } else {
                return false
            }
        }

        XCTAssertThrows(
            try AddPackageDependency.addPackageDependency(
                Self.swiftSystemPackageDependency,
                to: """
                // swift-tools-version: 5.4
                let package = Package(
                    name: "packages"
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .oldManifest(.v5_4, .v5_5) = error {
                return true
            } else {
                return false
            }
        }
    }

    func testAddLibraryProduct() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .target(name: "MyLib"),
                ],
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                products: [
                    .library(
                        name: "MyLib",
                        type: .dynamic,
                        targets: [ "MyLib" ]
                    ),
                ],
                targets: [
                    .target(name: "MyLib"),
                ],
            )
            """) { manifest in
            try AddProduct.addProduct(
                ProductDescription(
                    name: "MyLib",
                    type: .library(.dynamic),
                    targets: [ "MyLib" ]
                ),
                to: manifest
            )
        }
    }

    func testAddLibraryTarget() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages"
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .target(name: "MyLib"),
                ]
            )
            """,
            expectedAuxiliarySources: [
                RelativePath("Sources/MyLib/MyLib.swift") : """

                """
            ]) { manifest in
            try AddTarget.addTarget(
                TargetDescription(name: "MyLib"),
                to: manifest
            )
        }
    }

    func testAddLibraryTargetWithDependencies() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages"
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .target(
                        name: "MyLib",
                        dependencies: [
                            "OtherLib",
                            .product(name: "SwiftSyntax", package: "swift-syntax"),
                            .target(name: "TargetLib")
                        ]
                    ),
                ]
            )
            """,
            expectedAuxiliarySources: [
                RelativePath("Sources/MyLib/MyLib.swift") : """
                import OtherLib
                import SwiftSyntax
                import TargetLib

                """
            ]) { manifest in
            try AddTarget.addTarget(
                TargetDescription(name: "MyLib",
                                  dependencies: [
                                    .byName(name: "OtherLib", condition: nil),
                                    .product(name: "SwiftSyntax", package: "swift-syntax"),
                                    .target(name: "TargetLib", condition: nil)
                                  ]),
                to: manifest
            )
        }
    }

    func testAddExecutableTargetWithDependencies() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    // These are the targets
                    .target(name: "MyLib")
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    // These are the targets
                    .target(name: "MyLib"),
                    .executableTarget(
                        name: "MyProgram target-name",
                        dependencies: [
                            .product(name: "SwiftSyntax", package: "swift-syntax"),
                            .target(name: "TargetLib"),
                            "MyLib"
                        ]
                    ),
                ]
            )
            """,
            expectedAuxiliarySources: [
                RelativePath("Sources/MyProgram target-name/MyProgram target-name.swift") : """
                import MyLib
                import SwiftSyntax
                import TargetLib

                @main
                struct MyProgram_target_nameMain {
                    static func main() {
                        print("Hello, world")
                    }
                }
                """
            ]) { manifest in
            try AddTarget.addTarget(
                TargetDescription(
                    name: "MyProgram target-name",
                    dependencies: [
                        .product(name: "SwiftSyntax", package: "swift-syntax"),
                        .target(name: "TargetLib", condition: nil),
                        .byName(name: "MyLib", condition: nil)
                    ],
                    type: .executable
                ),
                to: manifest
            )
        }
    }

    func testAddMacroTarget() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            import PackageDescription

            let package = Package(
                name: "packages"
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            import CompilerPluginSupport
            import PackageDescription

            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0-latest"),
                ],
                targets: [
                    .macro(
                        name: "MyMacro target-name",
                        dependencies: [
                            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
                        ]
                    ),
                ]
            )
            """,
            expectedAuxiliarySources: [
                RelativePath("Sources/MyMacro target-name/MyMacro target-name.swift") : """
                import SwiftCompilerPlugin
                import SwiftSyntaxMacros

                struct MyMacro_target_name: Macro {
                    /// TODO: Implement one or more of the protocols that inherit
                    /// from Macro. The appropriate macro protocol is determined
                    /// by the "macro" declaration that MyMacro_target_name implements.
                    /// Examples include:
                    ///     @freestanding(expression) macro --> ExpressionMacro
                    ///     @attached(member) macro         --> MemberMacro
                }
                """,
                RelativePath("Sources/MyMacro target-name/ProvidedMacros.swift") : """
                import SwiftCompilerPlugin

                @main
                struct MyMacro_target_nameMacros: CompilerPlugin {
                    let providingMacros: [Macro.Type] = [
                        MyMacro_target_name.self,
                    ]
                }
                """
                ]
        ) { manifest in
            try AddTarget.addTarget(
                TargetDescription(name: "MyMacro target-name", type: .macro),
                to: manifest
            )
        }
    }

    func testAddSwiftTestingTestTarget() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages"
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(name: "MyTest target-name"),
                ]
            )
            """,
            expectedAuxiliarySources: [
                RelativePath("Tests/MyTest target-name/MyTest target-name.swift") : """
                import Testing

                @Suite
                struct MyTest_target_nameTests {
                    @Test("MyTest_target_name tests")
                    func example() {
                        #expect(42 == 17 + 25)
                    }
                }
                """
            ]) { manifest in
            try AddTarget.addTarget(
                TargetDescription(
                    name: "MyTest target-name",
                    type: .test
                ),
                to: manifest,
                configuration: .init(
                    testHarness: .swiftTesting
                )
            )
        }
    }

    func testAddTargetDependency() throws {
        try assertManifestRefactor("""
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/swiftlang/swift-example.git", from: "1.2.3"),
                ],
                targets: [
                    .testTarget(
                        name: "MyTest"
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                dependencies: [
                    .package(url: "https://github.com/swiftlang/swift-example.git", from: "1.2.3"),
                ],
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                            .product(name: "SomethingOrOther", package: "swift-example"),
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddTargetDependency.addTargetDependency(
                .product(name: "SomethingOrOther", package: "swift-example"),
                targetName: "MyTest",
                to: manifest
            )
        }
    }

    func testAddSwiftSettings() throws {
        XCTAssertThrows(
            try AddSwiftSetting.upcomingFeature(
                to: "MyTest",
                name: "ExistentialAny",
                manifest: """
                // swift-tools-version: 5.5
                let package = Package(
                    name: "packages",
                    targets: [
                        .executableTarget(
                            name: "MyTest"
                        )
                    ]
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .oldManifest(.v5_5, .v5_8) = error {
                return true
            } else {
                return false
            }
        }

        XCTAssertThrows(
            try AddSwiftSetting.upcomingFeature(
                to: "OtherTest",
                name: "ExistentialAny",
                manifest: """
                // swift-tools-version: 5.8
                let package = Package(
                    name: "packages",
                    targets: [
                        .executableTarget(
                            name: "MyTest"
                        )
                    ]
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .cannotFindTarget("OtherTest") = error {
                return true
            } else {
                return false
            }
        }

        XCTAssertThrows(
            try AddSwiftSetting.upcomingFeature(
                to: "MyPlugin",
                name: "ExistentialAny",
                manifest: """
                // swift-tools-version: 5.8
                let package = Package(
                    name: "packages",
                    targets: [
                        .plugin(
                            name: "MyPlugin",
                            capability: .buildTool
                        )
                    ]
                )
                """
            )
        ) { (error: ManifestEditError) in
            if case .cannotAddSettingsToPluginTarget = error {
                return true
            } else {
                return false
            }
        }


        try assertManifestRefactor("""
            // swift-tools-version: 5.8
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ]
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.8
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .enableUpcomingFeature("ExistentialAny:migratable"),
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddSwiftSetting.upcomingFeature(
                to: "MyTest",
                name: "ExistentialAny:migratable",
                manifest: manifest
            )
        }

        try assertManifestRefactor("""
            // swift-tools-version: 5.8
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .enableExperimentalFeature("Extern")
                        ]
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 5.8
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .enableExperimentalFeature("Extern"),
                            .enableExperimentalFeature("TrailingComma"),
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddSwiftSetting.experimentalFeature(
                to: "MyTest",
                name: "TrailingComma",
                manifest: manifest
            )
        }

        try assertManifestRefactor("""
            // swift-tools-version: 6.2
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ]
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 6.2
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .strictMemorySafety,
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddSwiftSetting.strictMemorySafety(
                to: "MyTest",
                manifest: manifest
            )
        }

        try assertManifestRefactor("""
            // swift-tools-version: 6.0
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ]
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 6.0
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .swiftLanguageMode(.v5),
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddSwiftSetting.languageMode(
                to: "MyTest",
                mode: .init(string: "5")!,
                manifest: manifest
            )
        }
        
        // Custom language mode
        try assertManifestRefactor("""
            // swift-tools-version: 6.0
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ]
                    ),
                ]
            )
            """,
            expectedManifest: """
            // swift-tools-version: 6.0
            let package = Package(
                name: "packages",
                targets: [
                    .testTarget(
                        name: "MyTest",
                        dependencies: [
                        ],
                        swiftSettings: [
                            .swiftLanguageMode(.version("6.2")),
                        ]
                    ),
                ]
            )
            """) { manifest in
            try AddSwiftSetting.languageMode(
                to: "MyTest",
                mode: .init(string: "6.2")!,
                manifest: manifest
            )
        }
    }
}
/// Assert that applying the moveSingleTargetSources operation to the manifest
/// produces the expected file system.
func assertFileSystemRefactor(
    _ manifest: String,
    inputFileLayout: [AbsolutePath] = [],
    expectedFileLayout: [AbsolutePath] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let mockFileSystem = InMemoryFileSystem();
    for path in inputFileLayout {
        try mockFileSystem.writeFileContents(path, string: "print(\"Hello, world!\")")
    }

    try AddTarget.moveSingleTargetSources(
        packagePath: AbsolutePath("/"),
        manifest: Parser.parse(source: manifest),
        fileSystem: mockFileSystem
    )

    for path in expectedFileLayout {
        XCTAssertTrue(mockFileSystem.exists(path))
    }

    let unexpectedFiles = inputFileLayout.filter { !expectedFileLayout.contains($0) }
    for path in unexpectedFiles {
        XCTAssertFalse(mockFileSystem.exists(path))
    }
}

class SingleTargetSourceTests: XCTestCase {
    func testMoveSingleTargetSources() throws {
        try assertFileSystemRefactor(
            """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .executableTarget(name: "Foo"),
                ]
            )
            """,
            inputFileLayout: [AbsolutePath("/Sources/Foo.swift")],
            expectedFileLayout: [AbsolutePath("/Sources/Foo/Foo.swift")]
        )
    }

    func testMoveSingleTargetSourcesNoTargets() throws {
        try assertFileSystemRefactor(
            """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages"
            )
            """,
            inputFileLayout: [AbsolutePath("/Sources/Foo.swift")],
            expectedFileLayout: [AbsolutePath("/Sources/Foo.swift")]
        )
    }

    func testMoveSingleTargetSourcesAlreadyOrganized() throws {
        try assertFileSystemRefactor(
            """
            // swift-tools-version: 5.5
            let package = Package(
                name: "packages",
                targets: [
                    .executableTarget(name: "Foo"),
                ]
            )
            """,
            inputFileLayout: [AbsolutePath("/Sources/Foo/Foo.swift")],
            expectedFileLayout: [AbsolutePath("/Sources/Foo/Foo.swift")]
        )
    }

    func testMoveSingleTargetSourcesInvalidManifestTargets() throws {
        XCTAssertThrowsError(
            try assertFileSystemRefactor(
                """
                // swift-tools-version: 5.5
                let package = Package(
                    name: "packages",
                    targets: "invalid"
                )
                """
            )
        ) { error in
            XCTAssertTrue(error is ManifestEditError)
        }
    }

    func testMoveSingleTargetSourcesInvalidManifestToolsVersion() throws {
        XCTAssertThrowsError(
            try assertFileSystemRefactor(
                """
                // swift-tools-version: 5.4
                let package = Package(
                    name: "packages",
                    targets: []
                )
                """
            )
        ) { error in
            XCTAssertTrue(error is ManifestEditError)
        }
    }

    func testMoveSingleTargetSourcesInvalidManifestTarget() throws {
        XCTAssertThrowsError(
            try assertFileSystemRefactor(
                """
                // swift-tools-version: 5.4
                let package = Package(
                    name: "packages",
                    targets: [.executableTarget(123)]
                )
                """
            )
        ) { error in
            XCTAssertTrue(error is ManifestEditError)
        }
    }

    func testMoveSingleTargetSourcesInvalidManifestPackage() throws {
        XCTAssertThrowsError(
            try assertFileSystemRefactor(
                """
                // swift-tools-version: 5.5
                """
            )
        ) { error in
            XCTAssertTrue(error is ManifestEditError)
        }
    }
}


// FIXME: Copy-paste from _SwiftSyntaxTestSupport

/// Asserts that the two strings are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
public func assertStringsEqualWithDiff(
    _ actual: String,
    _ expected: String,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected {
        return
    }

    failStringsEqualWithDiff(
        actual,
        expected,
        message,
        additionalInfo: additionalInfo(),
        file: file,
        line: line
    )
}

/// Asserts that the two data are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
public func assertDataEqualWithDiff(
    _ actual: Data,
    _ expected: Data,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected {
        return
    }

    // NOTE: Converting to `Stirng` here looses invalid UTF8 sequence difference,
    // but at least we can see something is different.
    failStringsEqualWithDiff(
        String(decoding: actual, as: UTF8.self),
        String(decoding: expected, as: UTF8.self),
        message,
        additionalInfo: additionalInfo(),
        file: file,
        line: line
    )
}

/// `XCTFail` with `diff`-style output.
public func failStringsEqualWithDiff(
    _ actual: String,
    _ expected: String,
    _ message: String = "",
    additionalInfo: @autoclosure () -> String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let stringComparison: String

    // Use `CollectionDifference` on supported platforms to get `diff`-like line-based output. On
    // older platforms, fall back to simple string comparison.
    if #available(macOS 10.15, *) {
        let actualLines = actual.components(separatedBy: .newlines)
        let expectedLines = expected.components(separatedBy: .newlines)

        let difference = actualLines.difference(from: expectedLines)

        var result = ""

        var insertions = [Int: String]()
        var removals = [Int: String]()

        for change in difference {
            switch change {
            case .insert(let offset, let element, _):
                insertions[offset] = element
            case .remove(let offset, let element, _):
                removals[offset] = element
            }
        }

        var expectedLine = 0
        var actualLine = 0

        while expectedLine < expectedLines.count || actualLine < actualLines.count {
            if let removal = removals[expectedLine] {
                result += "–\(removal)\n"
                expectedLine += 1
            } else if let insertion = insertions[actualLine] {
                result += "+\(insertion)\n"
                actualLine += 1
            } else {
                result += " \(expectedLines[expectedLine])\n"
                expectedLine += 1
                actualLine += 1
            }
        }

        stringComparison = result
    } else {
        // Fall back to simple message on platforms that don't support CollectionDifference.
        stringComparison = """
        Expected:
        \(expected)

        Actual:
        \(actual)
        """
    }

    var fullMessage = """
        \(message.isEmpty ? "Actual output does not match the expected" : message)
        \(stringComparison)
        """
    if let additional = additionalInfo() {
        fullMessage = """
        \(fullMessage)
        \(additional)
        """
    }
    XCTFail(fullMessage, file: file, line: line)
}
