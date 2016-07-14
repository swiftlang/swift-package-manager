/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basic
import PackageModel
import PackageDescription

@testable import Build

final class PackageVersionDataTests: XCTestCase {

    func makePackage(version: Version?) -> PackageModel.Package {
        let m = Manifest(path: "/path", url: "https://github.com/testPkg", package: PackageDescription.Package(name: "a"), products: [], version: version)
        return Package(manifest: m)
    }

    func testPackageData(_ package: PackageModel.Package, url: String, version: Version?) {
        var expected = "public let url: String = \"\(url)\"\n"
        expected += "public let version: (major: Int, minor: Int, patch: Int, prereleaseIdentifiers: [String], buildMetadata: String?) = "
        if let version = version {
            expected += "\(version.major, version.minor, version.patch, version.prereleaseIdentifiers, version.buildMetadataIdentifier)\n"
            expected += "public let versionString: String = \"\(version)\"\n"
        } else {
            expected += "(0, 0, 0, [], nil) \n"
            expected += "public let versionString: String = \"0.0.0\"\n"
        }

        let metadata = versionData(package: package)
        XCTAssertEqual(metadata, expected)
    }

    func testPackageVersionData() {
        let package = makePackage(version: Version(1, 2, 3))
        testPackageData(package, url: "https://github.com/testPkg", version: Version(1, 2, 3))
    }

    func testPackageEmptyVersionData() {
        let package = makePackage(version: nil)
        testPackageData(package, url: "https://github.com/testPkg", version: nil)
    }

    func testSavePackageVersionDataToFile() {
        mktmpdir { dir in
            let package = makePackage(version: nil)

            let m = Manifest(path: "/path", url: "https://github.com/rootPkg", package: PackageDescription.Package(name: "a"), products: [], version: nil)
            let rootPkg = Package(manifest: m)

            try generateVersionData(dir, rootPackage:rootPkg, externalPackages: [package])
            XCTAssertFileExists(dir.appending(components: ".build", "versionData", package.name + ".swift"))
        }
    }

    static var allTests = [
        ("testPackageVersionData", testPackageVersionData),
        ("testPackageEmptyVersionData", testPackageEmptyVersionData),
        ("testSavePackageVersionDataToFile", testSavePackageVersionDataToFile),
    ]
}
