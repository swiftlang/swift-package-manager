//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
@testable import Workspace
import Testing

fileprivate struct WorkspaceStateTests {
    @Test
    func v4Format() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 4,
                "object": {
                    "artifacts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remote",
                              "location": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-tools-support-core",
                              "kind": "remote",
                              "location": "https://github.com/apple/swift-tools-support-core.git",
                              "name": "swift-tools-support-core"
                            },
                            "state": {
                              "checkoutState": {
                                "branch": "main",
                                "revision": "f9bbd6b80d67408021576adf6247e17c2e957d92",
                                "version": null
                              },
                              "name": "checkout"
                            },
                            "subpath": "swift-tools-support-core"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-argument-parser",
                              "kind": "local",
                              "location": "/Users/tomerd/code/swift/swift-argument-parser",
                              "name": "swift-argument-parser"
                            },
                            "state": {
                              "name": "local"
                            },
                            "subpath": "swift-argument-parser"
                        }
                    ]
                }
            }
            """
        )

        let dependencies = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).dependencies
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("yams") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-tools-support-core") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-argument-parser") }))
    }

    @Test
    func v4FormatWithPath() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 4,
                "object": {
                    "artifacts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remote",
                              "path": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-tools-support-core",
                              "kind": "remote",
                              "path": "https://github.com/apple/swift-tools-support-core.git",
                              "name": "swift-tools-support-core"
                            },
                            "state": {
                              "checkoutState": {
                                "branch": "main",
                                "revision": "f9bbd6b80d67408021576adf6247e17c2e957d92",
                                "version": null
                              },
                              "name": "checkout"
                            },
                            "subpath": "swift-tools-support-core"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-argument-parser",
                              "kind": "local",
                              "path": "/Users/tomerd/code/swift/swift-argument-parser",
                              "name": "swift-argument-parser"
                            },
                            "state": {
                              "name": "local"
                            },
                            "subpath": "swift-argument-parser"
                        }
                    ]
                }
            }
            """
        )

        let dependencies = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).dependencies
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("yams") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-tools-support-core") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-argument-parser") }))
    }

    @Test
    func v5Format() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 5,
                "object": {
                    "artifacts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-tools-support-core",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/apple/swift-tools-support-core.git",
                              "name": "swift-tools-support-core"
                            },
                            "state": {
                              "checkoutState": {
                                "branch": "main",
                                "revision": "f9bbd6b80d67408021576adf6247e17c2e957d92"
                              },
                              "name": "checkout"
                            },
                            "subpath": "swift-tools-support-core"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-argument-parser",
                              "kind": "fileSystem",
                              "location": "/Users/tomerd/code/swift/swift-argument-parser",
                              "name": "swift-argument-parser"
                            },
                            "state": {
                              "name": "local",
                              "path": "/Users/tomerd/code/swift/swift-argument-parser"
                            },
                            "subpath": "swift-argument-parser"
                        }
                    ]
                }
            }
            """
        )

        let dependencies = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).dependencies
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("yams") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-tools-support-core") }))
        #expect(dependencies.contains(where: { $0.packageRef.identity == .plain("swift-argument-parser") }))
    }

    @Test
    func savedDependenciesAreSorted() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 5,
                "object": {
                    "artifacts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-argument-parser",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/apple/swift-argument-parser.git",
                              "name": "swift-argument-parser"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "83b23d940471b313427da226196661856f6ba3e0",
                                "version": "0.4.4"
                              },
                              "name": "checkout"
                            },
                            "subpath": "swift-argument-parser"
                        }
                    ]
                }
            }
            """
        )

        let state = WorkspaceState(fileSystem: fs, storageDirectory: buildDir)
        try await state.save()

        let serialized: String = try fs.readFileContents(statePath)

        let argpRange = try #require(serialized.range(of: "swift-argument-parser"))
        let yamsRange = try #require(serialized.range(of: "yams"))

        #expect(argpRange.lowerBound < yamsRange.lowerBound)
    }

    @Test
    func artifacts() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 5,
                "object": {
                    "artifacts": [
                        {
                            "packageRef": {
                              "identity": "foo",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/org/foo.git",
                              "name": "foo"
                            },
                            "targetName": "foo",
                            "source": {
                                "type": "remote",
                                "url": "https://github.com/org/binary1.zip",
                                "checksum": "77AFD0BA-D1CF-4628-A43B-B6E66F44448A"
                            },
                            "path": "/path/to/binary1"
                        },
                        {
                            "packageRef": {
                              "identity": "foo",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/org/foo.git",
                              "name": "foo"
                            },
                            "targetName": "bar",
                            "source": {
                                "type": "remote",
                                "url": "https://github.com/org/binary2.zip",
                                "checksum": "77AFD0BA-D1CF-4628-A43B-B6E66F44448A"
                            },
                            "path": "/path/to/binary2"
                        },
                        {
                            "packageRef": {
                              "identity": "bar",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/org/bar.git",
                              "name": "bar"
                            },
                            "targetName": "bar",
                            "source": {
                                "type": "remote",
                                "url": "https://github.com/org/binary3.zip",
                                "checksum": "77AFD0BA-D1CF-4628-A43B-B6E66F44448A"
                            },
                            "path": "/path/to/binary3"
                        }
                    ],
                    "dependencies": []
                }
            }
            """
        )

        let artifacts = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).artifacts
        #expect(artifacts.contains(where: { $0.packageRef.identity == .plain("foo") && $0.targetName == "foo" }))
        #expect(artifacts.contains(where: { $0.packageRef.identity == .plain("foo") && $0.targetName == "bar" }))
        #expect(artifacts.contains(where: { $0.packageRef.identity == .plain("bar") && $0.targetName == "bar" }))
    }

    // rdar://86857825
    @Test
    func duplicateDependenciesDoNotCrash() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 5,
                "object": {
                    "artifacts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "yams",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/jpsim/Yams.git",
                              "name": "Yams"
                            },
                            "state": {
                              "checkoutState": {
                                "revision": "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
                                "version": "4.0.6"
                              },
                              "name": "checkout"
                            },
                            "subpath": "Yams"
                        },
                    ]
                }
            }
            """
        )

        let dependencies = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).dependencies
        // empty since we have dups so we warn and fail the loading
        // TODO: test for diagnostics when we can get them from the WorkspaceState initializer
        #expect(dependencies.isEmpty)
    }

    // rdar://86857825
    @Test
    func duplicateArtifactsDoNotCrash() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 5,
                "object": {
                    "artifacts": [
                        {
                            "packageRef": {
                              "identity": "foo",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/org/foo.git",
                              "name": "foo"
                            },
                            "targetName": "foo",
                            "source": {
                                "type": "remote",
                                "url": "https://github.com/org/binary1.zip",
                                "checksum": "77AFD0BA-D1CF-4628-A43B-B6E66F44448A"
                            },
                            "path": "/path/to/binary1"
                        },
                        {
                            "packageRef": {
                              "identity": "foo",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/org/foo.git",
                              "name": "foo"
                            },
                            "targetName": "foo",
                            "source": {
                                "type": "remote",
                                "url": "https://github.com/org/binary2.zip",
                                "checksum": "77AFD0BA-D1CF-4628-A43B-B6E66F44448A"
                            },
                            "path": "/path/to/binary2"
                        }
                    ],
                    "dependencies": []
                }
            }
            """
        )

        let artifacts = await WorkspaceState(fileSystem: fs, storageDirectory: buildDir).artifacts
        // empty since we have dups so we warn and fail the loading
        // TODO: test for diagnostics when we can get them from the WorkspaceState initializer
        #expect(artifacts.isEmpty)
    }
}

extension WorkspaceState {
    fileprivate init(fileSystem: FileSystem, storageDirectory: AbsolutePath) {
        self.init(fileSystem: fileSystem, storageDirectory: storageDirectory, initializationWarningHandler: { _ in })
    }
}
