//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import XCTest

class PackageDescriptionNextLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }

    func testImplicitFoundationImportFails() throws {
        let content = """
            import PackageDescription

            _ = FileManager.default

            let package = Package(name: "MyPackage")
            """

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") {
            if case ManifestParseError.invalidManifestFormat(let error, _, _) = $0 {
                XCTAssertMatch(error, .contains("cannot find 'FileManager' in scope"))
            } else {
                XCTFail("unexpected error: \($0)")
            }
        }
    }

    // MARK: - Manifest 2.0

    func testFileSystemDependencies() throws {
        let content = """
                import PackageManifest

                Package()
                    .dependencies {
                        FileSystem(at: "/foo")
                        FileSystem(at: "/bar")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0

        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
        XCTAssertEqual(deps["foo"], .fileSystem(path: .init("/foo")))
        XCTAssertEqual(deps["bar"], .fileSystem(path: .init("/bar")))

    }

    func testLocalSourceControlDependencies() throws {
        let content = """
                import PackageManifest

                Package()
                    .dependencies {
                        SourceControl(at: "/foo", branch: "main")
                        SourceControl(at: "/bar", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6")
                        SourceControl(at: "/baz", upToNextMajor: "1.0.1")
                        SourceControl(at: "/qux", exact: "1.0.1")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0

        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
        XCTAssertEqual(deps["foo"], .localSourceControl(path: .init("/foo"), requirement: .branch("main")))
        XCTAssertEqual(deps["bar"], .localSourceControl(path: .init("/bar"), requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        XCTAssertEqual(deps["baz"], .localSourceControl(path: .init("/baz"), requirement: .upToNextMajor(from: "1.0.1")))
        XCTAssertEqual(deps["qux"], .localSourceControl(path: .init("/qux"), requirement: .exact("1.0.1")))
    }

    func testRemoteSourceControlDependencies() throws {
        let content = """
                import PackageManifest

                Package()
                    .dependencies {
                        SourceControl(at: "http://localhost/foo", branch: "main")
                        SourceControl(at: "http://localhost/bar", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6")
                        SourceControl(at: "http://localhost/baz", upToNextMajor: "1.0.1")
                        SourceControl(at: "http://localhost/qux", exact: "1.0.1")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0

        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
        XCTAssertEqual(deps["foo"], .remoteSourceControl(url: URL(string: "http://localhost/foo")!, requirement: .branch("main")))
        XCTAssertEqual(deps["bar"], .remoteSourceControl(url: URL(string: "http://localhost/bar")!, requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        XCTAssertEqual(deps["baz"], .remoteSourceControl(url: URL(string: "http://localhost/baz")!, requirement: .upToNextMajor(from: "1.0.1")))
        XCTAssertEqual(deps["qux"], .remoteSourceControl(url: URL(string: "http://localhost/qux")!, requirement: .exact("1.0.1")))
    }

    func testRegistryDependencies() throws {
        let content = """
                import PackageManifest

                Package()
                    .dependencies {
                        Registry(identity: "baz", upToNextMajor: "1.0.1")
                        Registry(identity: "qux", exact: "1.0.1")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0

        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
        XCTAssertEqual(deps["baz"], .registry(identity: "baz", requirement: .upToNextMajor(from: "1.0.1")))
        XCTAssertEqual(deps["qux"], .registry(identity: "qux", requirement: .exact("1.0.1")))
    }

    func testSample1() throws {
        let content = """
                import PackageManifest

                Package()
                    .modules {
                        Executable("MyExecutable", public: true)
                            .include {
                                Internal(["MyDataModel", "MyUtilities"])
                                External("SomeModule", from: "some-package")
                            }
                        Library("MyLibrary", public: true)
                            .include {
                                Internal("MyDataModel", public: true)
                                External("SomeOtherModule", from: "some-other-package")
                            }
                        Library("MyDataModel")
                        Library("MyUtilities")
                        Library("MyTestUtilities")
                        Test("MyExecutableTests", for: "MyExecutable")
                            .include("MyTestUtilities")
                        Test("MyLibraryTests", for: "MyLibrary")
                    }
                    .dependencies {
                        SourceControl(at: "https://git-service.com/foo/some-package", upToNextMajor: "1.0.0")
                        SourceControl(at: "https://git-service.com/foo/some-other-package", upToNextMajor: "1.0.0")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0
        // FIXME
        print(manifest.dependencies)
        print(manifest.products)
        print(manifest.targets)
    }

    func testSample2() throws {
        let content = """
                import PackageManifest

                Package()
                    .minimumDeploymentTarget {
                        MacOS("10.15")
                        iOS("12.0")
                    }
                    .modules {
                        Executable("module-executable")
                            .include {
                                Internal("module-library", public: true)
                                Internal("module-library-2")
                            }
                        Library("module-library", public: true)
                            .customPath("custom/path")
                            .swiftSettings("swiftSettings")
                            .cxxSettings("cxxSettings")
                            .include {
                                External("foo", from: "remote-major-1")
                                External("bar", from: "remote-major-2")
                            }
                        Library("module-library-2")
                        Test("module-test", for: "module-library")
                            .sources("sources-1")
                            .exclude("exclude-1", "exclude-2")
                            .swiftSettings("swiftSettings")
                            .cxxSettings("cxxSettings")
                        Plugin("module-plugin", capability: .buildTool, public: true)
                            .customPath("custom/path")
                        Binary("module-binary", url: "https://somewhere/binary.zip", checksum: "checksum")
                    }
                    .dependencies {
                        FileSystem(at: "/tmp/foo")
                        SourceControl(at: "http://localhost/remote-major-1", upToNextMajor: "1.0.0")
                        SourceControl(at: "http://localhost/remote-major-2", upToNextMajor: "2.0.0")
                        SourceControl(at: "/tmp/local-branch", branch: "main")
                        Registry(identity: "foo/bar", exact: "1.0.5")
                        Registry(identity: "foo/baz", upToNextMajor: "3.0.0")
                    }
                """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadAndValidateManifest(content, observabilityScope: observability.topScope).0
        // FIXME
        print(manifest.dependencies)
        print(manifest.products)
        print(manifest.targets)
    }
}
