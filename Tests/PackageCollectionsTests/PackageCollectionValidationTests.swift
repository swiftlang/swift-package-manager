/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

@testable import PackageCollections
@testable import PackageCollectionsModel
import PackageModel

class PackageCollectionValidationTests: XCTestCase {
    typealias Model = PackageCollectionModel.V1

    func test_validationOK() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator()
        XCTAssertNil(validator.validate(collection: collection))
    }

    func test_validationFailed_noPackages() throws {
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: [],
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator()
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(1, messages.count)

        guard case .error = messages[0].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertTrue(messages[0].message.contains("contain at least one package"))
    }

    func test_validationFailed_tooManyPackages() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobaz.git")!,
                summary: "Package Foobaz",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobaz",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator(configuration: .init(maximumPackageCount: 1))
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(1, messages.count)

        guard case .warning = messages[0].level else {
            return XCTFail("Expected .warning")
        }
        XCTAssertNotNil(messages[0].message.range(of: "more than the recommended", options: .caseInsensitive))
    }

    func test_validationFailed_duplicateVersions_emptyProductsAndTargets() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [],
                        products: [],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator()
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(3, messages.count)

        guard case .error = messages[0].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[0].message.range(of: "duplicate version(s)", options: .caseInsensitive))

        guard case .error = messages[1].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[1].message.range(of: "does not contain any products", options: .caseInsensitive))

        guard case .error = messages[2].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[2].message.range(of: "does not contain any targets", options: .caseInsensitive))
    }

    func test_validationFailed_nonSemanticVersion() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "v1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator()
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(1, messages.count)

        guard case .error = messages[0].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[0].message.range(of: "non semantic version(s)", options: .caseInsensitive))
    }

    func test_validationFailed_tooManyMajorsAndMinors() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "2.0.0",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobaz.git")!,
                summary: "Package Foobaz",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.4.0",
                        packageName: "Foobaz",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobaz",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator(configuration: .init(maximumMajorVersionCount: 1, maximumMinorVersionCount: 1))
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(2, messages.count)

        guard case .warning = messages[0].level else {
            return XCTFail("Expected .warning")
        }
        XCTAssertNotNil(messages[0].message.range(of: "too many major versions", options: .caseInsensitive))

        guard case .warning = messages[1].level else {
            return XCTFail("Expected .warning")
        }
        XCTAssertNotNil(messages[1].message.range(of: "too many minor versions", options: .caseInsensitive))
    }

    func test_validationFailed_versionProductNoTargets() throws {
        let packages = [
            Model.Collection.Package(
                url: URL(string: "https://package-collection-tests.com/repos/foobar.git")!,
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        packageName: "Foobar",
                        targets: [.init(name: "Foo", moduleName: "Foo")],
                        products: [.init(name: "Bar", type: .library(.automatic), targets: [])],
                        toolsVersion: "5.2",
                        minimumPlatformVersions: nil,
                        verifiedCompatibility: nil,
                        license: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
        ]
        let collection = Model.Collection(
            name: "Test Package Collection",
            overview: "A test package collection",
            keywords: ["swift packages"],
            packages: packages,
            formatVersion: .v1_0,
            revision: 3,
            generatedAt: Date(),
            generatedBy: .init(name: "Jane Doe")
        )

        let validator = Model.Validator()
        let messages = validator.validate(collection: collection)!
        XCTAssertEqual(1, messages.count)

        guard case .error = messages[0].level else {
            return XCTFail("Expected .error")
        }
        XCTAssertNotNil(messages[0].message.range(of: "does not contain any targets", options: .caseInsensitive))
    }
}
