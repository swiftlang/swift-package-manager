//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

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
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "v1.3.0",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobaz.git",
                summary: "Package Foobaz",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobaz",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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

    func test_validationFailed_noVersions() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [],
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
        XCTAssertNotNil(messages[0].message.range(of: "does not have any versions", options: .caseInsensitive))
    }

    func test_validationFailed_duplicateVersions_emptyProductsAndTargets() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [],
                                products: [],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "x1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "2.0.0",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                ],
                readmeURL: nil,
                license: nil
            ),
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobaz.git",
                summary: "Package Foobaz",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.4.0",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobaz",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
                    ),
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobaz",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Baz", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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

    func test_validationFailed_versionEmptyManifests() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [:],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
        XCTAssertNotNil(messages[0].message.range(of: "does not have any manifests", options: .caseInsensitive))
    }

    func test_validationFailed_versionProductNoTargets() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: [])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.2",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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

    func test_validationFailed_manifestToolsVersionMismatch() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.1": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.1",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
        XCTAssertNotNil(messages[0].message.range(of: "manifest tools version 5.2 does not match 5.1", options: .caseInsensitive))
    }

    func test_validationFailed_missingDefaultManifest() throws {
        let packages = [
            Model.Collection.Package(
                url: "https://package-collection-tests.com/repos/foobar.git",
                summary: "Package Foobar",
                keywords: ["test package"],
                versions: [
                    Model.Collection.Package.Version(
                        version: "1.3.2",
                        summary: nil,
                        manifests: [
                            "5.2": Model.Collection.Package.Version.Manifest(
                                toolsVersion: "5.2",
                                packageName: "Foobar",
                                targets: [.init(name: "Foo", moduleName: "Foo")],
                                products: [.init(name: "Bar", type: .library(.automatic), targets: ["Foo"])],
                                minimumPlatformVersions: nil
                            ),
                        ],
                        defaultToolsVersion: "5.1",
                        verifiedCompatibility: nil,
                        license: nil,
                        author: nil,
                        signer: nil,
                        createdAt: nil
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
        XCTAssertNotNil(messages[0].message.range(of: "missing the default manifest", options: .caseInsensitive))
    }
}
