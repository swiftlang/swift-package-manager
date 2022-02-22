/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import SPMTestSupport
import TSCBasic
import XCTest

@testable import PackageCollections
@testable import PackageModel

final class PackageCollectionsModelTests: XCTestCase {
    func testLatestVersions() {
        let targets = [PackageCollectionsModel.Target(name: "Foo", moduleName: "Foo")]
        let products = [PackageCollectionsModel.Product(name: "Foo", type: .library(.automatic), targets: targets)]
        let toolsVersion = ToolsVersion(string: "5.2")!
        let manifests = [toolsVersion: PackageCollectionsModel.Package.Version.Manifest(
            toolsVersion: toolsVersion, packageName: "FooBar", targets: targets, products: products, minimumPlatformVersions: nil
        )]
        let versions: [PackageCollectionsModel.Package.Version] = [
            .init(version: .init(stringLiteral: "1.2.0"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "2.0.1"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "2.1.0-beta.3"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "2.1.0"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "3.0.0-beta.1"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
        ]

        XCTAssertEqual("2.1.0", versions.latestRelease?.version.description)
        XCTAssertEqual("3.0.0-beta.1", versions.latestPrerelease?.version.description)
    }

    func testNoLatestReleaseVersion() {
        let targets = [PackageCollectionsModel.Target(name: "Foo", moduleName: "Foo")]
        let products = [PackageCollectionsModel.Product(name: "Foo", type: .library(.automatic), targets: targets)]
        let toolsVersion = ToolsVersion(string: "5.2")!
        let manifests = [toolsVersion: PackageCollectionsModel.Package.Version.Manifest(
            toolsVersion: toolsVersion, packageName: "FooBar", targets: targets, products: products, minimumPlatformVersions: nil
        )]
        let versions: [PackageCollectionsModel.Package.Version] = [
            .init(version: .init(stringLiteral: "2.1.0-beta.3"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "3.0.0-beta.1"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
        ]

        XCTAssertNil(versions.latestRelease)
        XCTAssertEqual("3.0.0-beta.1", versions.latestPrerelease?.version.description)
    }

    func testNoLatestPrereleaseVersion() {
        let targets = [PackageCollectionsModel.Target(name: "Foo", moduleName: "Foo")]
        let products = [PackageCollectionsModel.Product(name: "Foo", type: .library(.automatic), targets: targets)]
        let toolsVersion = ToolsVersion(string: "5.2")!
        let manifests = [toolsVersion: PackageCollectionsModel.Package.Version.Manifest(
            toolsVersion: toolsVersion, packageName: "FooBar", targets: targets, products: products, minimumPlatformVersions: nil
        )]
        let versions: [PackageCollectionsModel.Package.Version] = [
            .init(version: .init(stringLiteral: "1.2.0"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "2.0.1"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
            .init(version: .init(stringLiteral: "2.1.0"), title: nil, summary: nil, manifests: manifests, defaultToolsVersion: toolsVersion, verifiedCompatibility: nil, license: nil, createdAt: nil),
        ]

        XCTAssertEqual("2.1.0", versions.latestRelease?.version.description)
        XCTAssertNil(versions.latestPrerelease)
    }

    func testSourceValidation() throws {
        let httpsSource = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "https://feed.mock.io")!)
        XCTAssertNil(httpsSource.validate(fileSystem: localFileSystem), "not expecting errors")

        let httpsSource2 = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "HTTPS://feed.mock.io")!)
        XCTAssertNil(httpsSource2.validate(fileSystem: localFileSystem), "not expecting errors")

        let httpsSource3 = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "HttpS://feed.mock.io")!)
        XCTAssertNil(httpsSource3.validate(fileSystem: localFileSystem), "not expecting errors")

        let httpSource = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "http://feed.mock.io")!)
        XCTAssertEqual(httpSource.validate(fileSystem: localFileSystem)?.count, 1, "expecting errors")

        let otherProtocolSource = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "ftp://feed.mock.io")!)
        XCTAssertEqual(otherProtocolSource.validate(fileSystem: localFileSystem)?.count, 1, "expecting errors")

        let brokenUrlSource = PackageCollectionsModel.CollectionSource(type: .json, url: URL(string: "blah")!)
        XCTAssertEqual(brokenUrlSource.validate(fileSystem: localFileSystem)?.count, 1, "expecting errors")
    }

    func testSourceValidation_localFile() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            // File must exist in local FS
            let path = fixturePath.appending(components: "JSON", "good.json")

            let source = PackageCollectionsModel.CollectionSource(type: .json, url: path.asURL)
            XCTAssertNil(source.validate(fileSystem: localFileSystem))
        }
    }

    func testSourceValidation_localFileDoesNotExist() throws {
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: URL(fileURLWithPath: "/foo/bar"))

        let messages = source.validate(fileSystem: localFileSystem)!
        XCTAssertEqual(1, messages.count)

        guard case .error = messages[0].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[0].message.range(of: "either a non-local path or the file does not exist", options: .caseInsensitive))
    }
}
