//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
import PackageModel
@testable import Workspace
import Testing

import struct TSCUtility.Version

fileprivate struct WorkspaceStateTests {
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
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

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .issue("rdar://86857825", relationship: .defect),
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .issue("rdar://86857825", relationship: .defect),
        .tags(
            .TestSize.small,
        ),
    )
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

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func sourceArchiveDownloadRoundTrip() async throws {
        let fs = InMemoryFileSystem()

        let buildDir = AbsolutePath("/.build")
        let statePath = buildDir.appending("workspace-state.json")
        try fs.writeFileContents(
            statePath,
            string: """
            {
                "version": 7,
                "object": {
                    "artifacts": [],
                    "prebuilts": [],
                    "dependencies": [
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "swift-nio",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/apple/swift-nio.git",
                              "name": "swift-nio"
                            },
                            "state": {
                              "name": "sourceArchiveDownload",
                              "version": "2.40.0",
                              "revision": "abc123def456",
                              "tag": "2.40.0",
                              "hasSubmodules": false,
                              "checksum": null
                            },
                            "subpath": "swift-nio/2.40.0"
                        },
                        {
                            "basedOn": null,
                            "packageRef": {
                              "identity": "grpc-swift",
                              "kind": "remoteSourceControl",
                              "location": "https://github.com/grpc/grpc-swift.git",
                              "name": "grpc-swift"
                            },
                            "state": {
                              "name": "sourceArchiveDownload",
                              "version": "1.0.0",
                              "revision": "fff000aaa111",
                              "tag": "v1.0.0",
                              "hasSubmodules": true,
                              "checksum": "deadbeef"
                            },
                            "subpath": "grpc-swift/1.0.0"
                        }
                    ]
                }
            }
            """
        )

        let state = WorkspaceState(fileSystem: fs, storageDirectory: buildDir)
        let dependencies = await state.dependencies

        // Verify both dependencies loaded.
        let nio = dependencies[.plain("swift-nio")]
        #expect(nio != nil)
        if case .sourceArchiveDownload(let state) = nio?.state {
            #expect(state.version == .init(2, 40, 0))
            #expect(state.revision == "abc123def456")
            #expect(state.tag == "2.40.0")
            #expect(state.hasSubmodules == false)
            #expect(state.checksum == nil)
        } else {
            Issue.record("Expected sourceArchiveDownload state, got \(String(describing: nio?.state))")
        }

        let grpc = dependencies[.plain("grpc-swift")]
        #expect(grpc != nil)
        if case .sourceArchiveDownload(let state) = grpc?.state {
            #expect(state.version == .init(1, 0, 0))
            #expect(state.revision == "fff000aaa111")
            #expect(state.tag == "v1.0.0")
            #expect(state.hasSubmodules == true)
            #expect(state.checksum == "deadbeef")
        } else {
            Issue.record("Expected sourceArchiveDownload state, got \(String(describing: grpc?.state))")
        }

        // Round-trip: save and reload.
        try await state.save()
        let reloaded = WorkspaceState(fileSystem: fs, storageDirectory: buildDir)
        let reloadedDeps = await reloaded.dependencies

        let nioReloaded = reloadedDeps[.plain("swift-nio")]
        if case .sourceArchiveDownload(let state) = nioReloaded?.state {
            #expect(state.version == .init(2, 40, 0))
            #expect(state.revision == "abc123def456")
            #expect(state.tag == "2.40.0")
            #expect(state.hasSubmodules == false)
            #expect(state.checksum == nil)
        } else {
            Issue.record("Round-trip failed for swift-nio: \(String(describing: nioReloaded?.state))")
        }

        let grpcReloaded = reloadedDeps[.plain("grpc-swift")]
        if case .sourceArchiveDownload(let state) = grpcReloaded?.state {
            #expect(state.version == .init(1, 0, 0))
            #expect(state.hasSubmodules == true)
            #expect(state.checksum == "deadbeef")
        } else {
            Issue.record("Round-trip failed for grpc-swift: \(String(describing: grpcReloaded?.state))")
        }
    }

    @Test("sourceArchiveDownload dependency can be edited and preserves basedOn state")
    func sourceArchiveDownloadEditTransition() throws {
        let url = SourceControlURL("https://github.com/test/foo.git")
        let identity = PackageIdentity(url: url)
        let packageRef = PackageReference(identity: identity, kind: .remoteSourceControl(url))

        let original = try Workspace.ManagedDependency.sourceArchiveDownload(
            packageRef: packageRef,
            state: SourceArchiveDownloadState(version: Version(1, 0, 0), revision: "abc123", tag: "1.0.0", hasSubmodules: false, checksum: "deadbeef"),
            subpath: try RelativePath(validating: identity.description).appending(component: "1.0.0")
        )

        // Edit the dependency.
        let edited = try original.edited(
            subpath: try RelativePath(validating: "foo"),
            unmanagedPath: nil
        )

        // Verify edited state preserves the original as basedOn.
        guard case .edited(let basedOn, _) = edited.state else {
            Issue.record("Expected edited state, got: \(edited.state)")
            return
        }
        guard case .sourceArchiveDownload(let state) = basedOn?.state else {
            Issue.record("Expected basedOn sourceArchiveDownload, got: \(String(describing: basedOn?.state))")
            return
        }
        #expect(state.version == Version(1, 0, 0))
        #expect(state.revision == "abc123")
        #expect(state.tag == "1.0.0")
        #expect(state.hasSubmodules == false)
        #expect(state.checksum == "deadbeef")
    }
}

extension WorkspaceState {
    fileprivate init(fileSystem: FileSystem, storageDirectory: AbsolutePath) {
        self.init(fileSystem: fileSystem, storageDirectory: storageDirectory, initializationWarningHandler: { _ in })
    }
}
