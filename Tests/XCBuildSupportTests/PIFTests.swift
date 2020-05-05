/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCUtility
import PackageModel
import Build
import XCBuildSupport
import SPMTestSupport

class PIFTests: XCTestCase {
    let topLevelObject = PIF.TopLevelObject(workspace:
        PIF.Workspace(
            guid: "workspace",
            name: "MyWorkspace",
            path: AbsolutePath("/path/to/workspace"),
            projects: [
                PIF.Project(
                    guid: "project",
                    name: "MyProject",
                    path: AbsolutePath("/path/to/workspace/project"),
                    projectDirectory: AbsolutePath("/path/to/workspace/project"),
                    developmentRegion: "fr",
                    buildConfigurations: [
                        PIF.BuildConfiguration(
                            guid: "project-config-debug-guid",
                            name: "Debug",
                            buildSettings: {
                                var settings = PIF.BuildSettings()
                                settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
                                settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
                                return settings
                            }()
                        ),
                        PIF.BuildConfiguration(
                            guid: "project-config-release-guid",
                            name: "Release",
                            buildSettings: {
                                var settings = PIF.BuildSettings()
                                settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
                                settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
                                settings[.GCC_OPTIMIZATION_LEVEL] = "s"
                                return settings
                            }()
                        ),
                    ],
                    targets: [
                        PIF.Target(
                            guid: "target-exe-guid",
                            name: "MyExecutable",
                            productType: .executable,
                            productName: "MyExecutable",
                            buildConfigurations: [
                                PIF.BuildConfiguration(
                                    guid: "target-exe-config-debug-guid",
                                    name: "Debug",
                                    buildSettings: {
                                        var settings = PIF.BuildSettings()
                                        settings[.TARGET_NAME] = "MyExecutable"
                                        settings[.EXECUTABLE_NAME] = "my-exe"
                                        return settings
                                    }()
                                ),
                                PIF.BuildConfiguration(
                                    guid: "target-exe-config-release-guid",
                                    name: "Release",
                                    buildSettings: {
                                        var settings = PIF.BuildSettings()
                                        settings[.TARGET_NAME] = "MyExecutable"
                                        settings[.EXECUTABLE_NAME] = "my-exe"
                                        settings[.SKIP_INSTALL] = "NO"
                                        return settings
                                    }()
                                ),
                            ],
                            buildPhases: [
                                PIF.SourcesBuildPhase(
                                    guid: "target-exe-sources-build-phase-guid",
                                    buildFiles: [
                                        PIF.BuildFile(
                                            guid: "target-exe-sources-build-file-guid",
                                            fileGUID: "exe-file-guid",
                                            platformFilters: []
                                        )
                                    ]
                                ),
                                PIF.FrameworksBuildPhase(
                                    guid: "target-exe-frameworks-build-phase-guid",
                                    buildFiles: [
                                        PIF.BuildFile(
                                            guid: "target-exe-frameworks-build-file-guid",
                                            targetGUID: "target-lib-guid",
                                            platformFilters: []
                                        )
                                    ]
                                )
                            ],
                            dependencies: [
                                .init(targetGUID: "target-lib-guid")
                            ],
                            impartedBuildSettings: PIF.BuildSettings()
                        ),
                        PIF.Target(
                            guid: "target-lib-guid",
                            name: "MyLibrary",
                            productType: .objectFile,
                            productName: "MyLibrary",
                            buildConfigurations: [
                                PIF.BuildConfiguration(
                                    guid: "target-lib-config-debug-guid",
                                    name: "Debug",
                                    buildSettings: {
                                        var settings = PIF.BuildSettings()
                                        settings[.TARGET_NAME] = "MyLibrary-Debug"
                                        return settings
                                    }()
                                ),
                                PIF.BuildConfiguration(
                                    guid: "target-lib-config-release-guid",
                                    name: "Release",
                                    buildSettings: {
                                        var settings = PIF.BuildSettings()
                                        settings[.TARGET_NAME] = "MyLibrary"
                                        return settings
                                    }()
                                ),
                            ],
                            buildPhases: [
                                PIF.SourcesBuildPhase(
                                    guid: "target-lib-sources-build-phase-guid",
                                    buildFiles: [
                                        PIF.BuildFile(
                                            guid: "target-lib-sources-build-file-guid",
                                            fileGUID: "lib-file-guid",
                                            platformFilters: []
                                        )
                                    ]
                                )
                            ],
                            dependencies: [],
                            impartedBuildSettings: {
                                var settings = PIF.BuildSettings()
                                settings[.OTHER_CFLAGS] = ["-fmodule-map-file=modulemap", "$(inherited)"]
                                return settings
                            }()
                        ),
                        PIF.AggregateTarget(
                            guid: "aggregate-target-guid",
                            name: "AggregateLibrary",
                            buildConfigurations: [
                                PIF.BuildConfiguration(
                                    guid: "aggregate-target-config-debug-guid",
                                    name: "Debug",
                                    buildSettings: PIF.BuildSettings()
                                ),
                                PIF.BuildConfiguration(
                                    guid: "aggregate-target-config-release-guid",
                                    name: "Release",
                                    buildSettings: PIF.BuildSettings()
                                ),
                            ],
                            buildPhases: [],
                            dependencies: [
                                .init(targetGUID: "target-lib-guid"),
                                .init(targetGUID: "target-exe-guid"),
                            ],
                            impartedBuildSettings: {
                                var settings = PIF.BuildSettings()
                                settings[.OTHER_CFLAGS] = ["-fmodule-map-file=modulemap", "$(inherited)"]
                                return settings
                            }()
                        )
                    ],
                    groupTree: PIF.Group(guid: "main-group-guid", path: "", children: [
                        PIF.FileReference(guid: "exe-file-guid", path: "main.swift"),
                        PIF.FileReference(guid: "lib-file-guid", path: "lib.swift"),
                    ])
                )
            ]
        )
    )

    func testRoundTrip() throws {
        // FIXME: Disabled because we need to store build settings in
        // sorted dictionary in order to get deterministic output
        // when encoding (SR-12587).
      #if false
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        }

        let workspace = topLevelObject.workspace
        let encodedData = try encoder.encode(workspace)
        let decodedWorkspace = try JSONDecoder().decode(PIF.Workspace.self, from: encodedData)

        let originalPIF = try encoder.encode(workspace)
        let decodedPIF = try encoder.encode(decodedWorkspace)

        let originalString = String(data: originalPIF, encoding: .utf8)!
        let decodedString = String(data: decodedPIF, encoding: .utf8)!

        XCTAssertEqual(originalString, decodedString)
      #endif
    }

    func testEncodable() throws {
        let encoder = JSONEncoder()
        encoder.userInfo[.encodeForXCBuild] = true
        try PIF.sign(topLevelObject.workspace)
        let data = try encoder.encode(topLevelObject)
        let json = try JSON(data: data)

        guard case .array(let objects) = json else {
            XCTFail("invalid json type")
            return
        }

        guard objects.count == 5 else {
            XCTFail("invalid number of objects")
            return
        }

        let workspace = objects[0]
        guard let workspaceContents = workspace["contents"] else {
            XCTFail("missing workspace contents")
            return
        }

        let project = objects[1]
        guard let projectContents = project["contents"] else {
            XCTFail("missing project contents")
            return
        }

        let exeTarget = objects[2]
        guard let exeTargetContents = exeTarget["contents"] else {
            XCTFail("missing exe target contents")
            return
        }

        let libTarget = objects[3]
        guard let libTargetContents = libTarget["contents"] else {
            XCTFail("missing lib target contents")
            return
        }

        let aggregateTarget = objects[4]
        guard let aggregateTargetContents = aggregateTarget["contents"] else {
            XCTFail("missing aggregate target contents")
            return
        }

        XCTAssertEqual(workspace["type"]?.string, "workspace")
        XCTAssertEqual(workspaceContents["guid"]?.string, "workspace@11")
        XCTAssertEqual(workspaceContents["path"]?.string, "/path/to/workspace")
        XCTAssertEqual(workspaceContents["name"]?.string, "MyWorkspace")
        XCTAssertEqual(workspaceContents["projects"]?.array, [project["signature"]!])

        XCTAssertEqual(project["type"]?.string, "project")
        XCTAssertEqual(projectContents["guid"]?.string, "project@11")
        XCTAssertEqual(projectContents["path"]?.string, "/path/to/workspace/project")
        XCTAssertEqual(projectContents["projectDirectory"]?.string, "/path/to/workspace/project")
        XCTAssertEqual(projectContents["projectName"]?.string, "MyProject")
        XCTAssertEqual(projectContents["projectIsPackage"]?.string, "true")
        XCTAssertEqual(projectContents["developmentRegion"]?.string, "fr")
        XCTAssertEqual(projectContents["defaultConfigurationName"]?.string, "Release")
        XCTAssertEqual(projectContents["targets"]?.array, [
            exeTarget["signature"]!,
            libTarget["signature"]!,
            aggregateTarget["signature"]!,
        ])

        if let configurations = projectContents["buildConfigurations"]?.array, configurations.count == 2 {
            let debugConfiguration = configurations[0]
            XCTAssertEqual(debugConfiguration["guid"]?.string, "project-config-debug-guid")
            XCTAssertEqual(debugConfiguration["name"]?.string, "Debug")
            let debugSettings = debugConfiguration["buildSettings"]
            XCTAssertEqual(debugSettings?["PRODUCT_NAME"]?.string, "$(TARGET_NAME)")
            XCTAssertEqual(debugSettings?["SUPPORTED_PLATFORMS"]?.array, [.string("$(AVAILABLE_PLATFORMS)")])

            let releaseConfiguration = configurations[1]
            XCTAssertEqual(releaseConfiguration["guid"]?.string, "project-config-release-guid")
            XCTAssertEqual(releaseConfiguration["name"]?.string, "Release")
            let releaseSettings = releaseConfiguration["buildSettings"]
            XCTAssertEqual(releaseSettings?["PRODUCT_NAME"]?.string, "$(TARGET_NAME)")
            XCTAssertEqual(releaseSettings?["SUPPORTED_PLATFORMS"]?.array, [.string("$(AVAILABLE_PLATFORMS)")])
        } else {
            XCTFail("invalid number of build configurations")
        }

        if let groupTree = projectContents["groupTree"] {
            XCTAssertEqual(groupTree["guid"]?.string, "main-group-guid")
            XCTAssertEqual(groupTree["sourceTree"]?.string, "<group>")
            XCTAssertEqual(groupTree["path"]?.string, "")
            XCTAssertEqual(groupTree["name"]?.string, "")

            if let children = groupTree["children"]?.array, children.count == 2 {
                let file1 = children[0]
                XCTAssertEqual(file1["guid"]?.string, "exe-file-guid")
                XCTAssertEqual(file1["sourceTree"]?.string, "<group>")
                XCTAssertEqual(file1["path"]?.string, "main.swift")
                XCTAssertEqual(file1["name"]?.string, "main.swift")

                let file2 = children[1]
                XCTAssertEqual(file2["guid"]?.string, "lib-file-guid")
                XCTAssertEqual(file2["sourceTree"]?.string, "<group>")
                XCTAssertEqual(file2["path"]?.string, "lib.swift")
                XCTAssertEqual(file2["name"]?.string, "lib.swift")
            } else {
                XCTFail("invalid number of groupTree children")
            }
        } else {
            XCTFail("missing project groupTree")
        }

        XCTAssertEqual(exeTarget["type"]?.string, "target")
        XCTAssertEqual(exeTargetContents["guid"]?.string, "target-exe-guid@11")
        XCTAssertEqual(exeTargetContents["name"]?.string, "MyExecutable")
        XCTAssertEqual(exeTargetContents["dependencies"]?.array, [JSON(["guid": "target-lib-guid@11"])])
        XCTAssertEqual(exeTargetContents["type"]?.string, "standard")
        XCTAssertEqual(exeTargetContents["productTypeIdentifier"]?.string, "com.apple.product-type.tool")
        XCTAssertEqual(exeTargetContents["buildRules"]?.array, [])
        XCTAssertEqual(exeTargetContents["impartedBuildProperties"]?.dictionary, ["buildSettings": JSON([:])])

        XCTAssertEqual(exeTargetContents["productReference"], JSON([
            "type": "file",
            "guid": "PRODUCTREF-target-exe-guid",
            "name": "MyExecutable"
        ]))

        if let configurations = exeTargetContents["buildConfigurations"]?.array, configurations.count == 2 {
            let debugConfiguration = configurations[0]
            XCTAssertEqual(debugConfiguration["guid"]?.string, "target-exe-config-debug-guid")
            XCTAssertEqual(debugConfiguration["name"]?.string, "Debug")
            let debugSettings = debugConfiguration["buildSettings"]
            XCTAssertEqual(debugSettings?["TARGET_NAME"]?.string, "MyExecutable")
            XCTAssertEqual(debugSettings?["EXECUTABLE_NAME"]?.string, "my-exe")

            let releaseConfiguration = configurations[1]
            XCTAssertEqual(releaseConfiguration["guid"]?.string, "target-exe-config-release-guid")
            XCTAssertEqual(releaseConfiguration["name"]?.string, "Release")
            let releaseSettings = releaseConfiguration["buildSettings"]
            XCTAssertEqual(releaseSettings?["TARGET_NAME"]?.string, "MyExecutable")
            XCTAssertEqual(releaseSettings?["EXECUTABLE_NAME"]?.string, "my-exe")
            XCTAssertEqual(releaseSettings?["SKIP_INSTALL"]?.string, "NO")
        } else {
            XCTFail("invalid number of build configurations")
        }

        if let buildPhases = exeTargetContents["buildPhases"]?.array, buildPhases.count == 2 {
            let buildPhase1 = buildPhases[0]
            XCTAssertEqual(buildPhase1["guid"]?.string, "target-exe-sources-build-phase-guid")
            XCTAssertEqual(buildPhase1["type"]?.string, "com.apple.buildphase.sources")
            if let sources = buildPhase1["buildFiles"]?.array, sources.count == 1 {
                XCTAssertEqual(sources[0]["guid"]?.string, "target-exe-sources-build-file-guid")
                XCTAssertEqual(sources[0]["fileReference"]?.string, "exe-file-guid")
            } else {
                XCTFail("invalid number of build files")
            }

            let buildPhase2 = buildPhases[1]
            XCTAssertEqual(buildPhase2["guid"]?.string, "target-exe-frameworks-build-phase-guid")
            XCTAssertEqual(buildPhase2["type"]?.string, "com.apple.buildphase.frameworks")
            if let frameworks = buildPhase2["buildFiles"]?.array, frameworks.count == 1 {
                XCTAssertEqual(frameworks[0]["guid"]?.string, "target-exe-frameworks-build-file-guid")
                XCTAssertEqual(frameworks[0]["targetReference"]?.string, "target-lib-guid@11")
            } else {
                XCTFail("invalid number of build files")
            }
        } else {
            XCTFail("invalid number of build configurations")
        }

        XCTAssertEqual(libTarget["type"]?.string, "target")
        XCTAssertEqual(libTargetContents["guid"]?.string, "target-lib-guid@11")
        XCTAssertEqual(libTargetContents["name"]?.string, "MyLibrary")
        XCTAssertEqual(libTargetContents["dependencies"]?.array, [])
        XCTAssertEqual(libTargetContents["type"]?.string, "standard")
        XCTAssertEqual(libTargetContents["productTypeIdentifier"]?.string, "com.apple.product-type.objfile")
        XCTAssertEqual(libTargetContents["buildRules"]?.array, [])

        XCTAssertEqual(libTargetContents["productReference"], JSON([
            "type": "file",
            "guid": "PRODUCTREF-target-lib-guid",
            "name": "MyLibrary"
        ]))

        XCTAssertEqual(
            libTargetContents["impartedBuildProperties"]?["buildSettings"]?["OTHER_CFLAGS"]?.array,
            [.string("-fmodule-map-file=modulemap"), .string("$(inherited)")]
        )

        if let configurations = libTargetContents["buildConfigurations"]?.array, configurations.count == 2 {
            let debugConfiguration = configurations[0]
            XCTAssertEqual(debugConfiguration["guid"]?.string, "target-lib-config-debug-guid")
            XCTAssertEqual(debugConfiguration["name"]?.string, "Debug")
            let debugSettings = debugConfiguration["buildSettings"]
            XCTAssertEqual(debugSettings?["TARGET_NAME"]?.string, "MyLibrary-Debug")

            let releaseConfiguration = configurations[1]
            XCTAssertEqual(releaseConfiguration["guid"]?.string, "target-lib-config-release-guid")
            XCTAssertEqual(releaseConfiguration["name"]?.string, "Release")
            let releaseSettings = releaseConfiguration["buildSettings"]
            XCTAssertEqual(releaseSettings?["TARGET_NAME"]?.string, "MyLibrary")
        } else {
            XCTFail("invalid number of build configurations")
        }

        if let buildPhases = libTargetContents["buildPhases"]?.array, buildPhases.count == 1 {
            let buildPhase1 = buildPhases[0]
            XCTAssertEqual(buildPhase1["guid"]?.string, "target-lib-sources-build-phase-guid")
            XCTAssertEqual(buildPhase1["type"]?.string, "com.apple.buildphase.sources")
            if let sources = buildPhase1["buildFiles"]?.array, sources.count == 1 {
                XCTAssertEqual(sources[0]["guid"]?.string, "target-lib-sources-build-file-guid")
                XCTAssertEqual(sources[0]["fileReference"]?.string, "lib-file-guid")
            } else {
                XCTFail("invalid number of build files")
            }
        } else {
            XCTFail("invalid number of build configurations")
        }

        XCTAssertEqual(aggregateTarget["type"]?.string, "target")
        XCTAssertEqual(aggregateTargetContents["guid"]?.string, "aggregate-target-guid@11")
        XCTAssertEqual(aggregateTargetContents["type"]?.string, "aggregate")
        XCTAssertEqual(aggregateTargetContents["name"]?.string, "AggregateLibrary")
        XCTAssertEqual(aggregateTargetContents["dependencies"]?.array, [
            JSON(["guid": "target-lib-guid@11"]),
            JSON(["guid": "target-exe-guid@11"]),
        ])
        XCTAssertEqual(aggregateTargetContents["buildRules"], nil)

        XCTAssertEqual(
            aggregateTargetContents["impartedBuildProperties"]?["buildSettings"]?["OTHER_CFLAGS"]?.array,
            [.string("-fmodule-map-file=modulemap"), .string("$(inherited)")]
        )

        if let configurations = aggregateTargetContents["buildConfigurations"]?.array, configurations.count == 2 {
            let debugConfiguration = configurations[0]
            XCTAssertEqual(debugConfiguration["guid"]?.string, "aggregate-target-config-debug-guid")
            XCTAssertEqual(debugConfiguration["name"]?.string, "Debug")
            let debugSettings = debugConfiguration["buildSettings"]
            XCTAssertNotNil(debugSettings)

            let releaseConfiguration = configurations[1]
            XCTAssertEqual(releaseConfiguration["guid"]?.string, "aggregate-target-config-release-guid")
            XCTAssertEqual(releaseConfiguration["name"]?.string, "Release")
            let releaseSettings = releaseConfiguration["buildSettings"]
            XCTAssertNotNil(releaseSettings)
        } else {
            XCTFail("invalid number of build configurations")
        }

        if let buildPhases = aggregateTargetContents["buildPhases"]?.array, buildPhases.count == 0 {
        } else {
            XCTFail("invalid number of build configurations")
        }
    }
}
