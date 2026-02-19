//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageGraph
import PackageModel
@testable import SBOMModel
import Testing

@Suite(
    .tags(
        .Feature.SBOM
    )
)
struct PURLTests {
    struct PURLStringTestCase {
        let purl: PURL
        let expectedString: String
        let description: String
    }

    static let stringRepresentationTestCases: [PURLStringTestCase] = [
        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: nil,
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage",
            description: "Basic PURL with scheme, type, and name only"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: "apple",
                name: "swift-package-manager",
                version: nil,
                qualifiers: nil,
                subpath: nil
            ),
            expectedString: "pkg:swift/apple/swift-package-manager",
            description: "PURL with namespace"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: "1.0.0",
                qualifiers: nil,
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage@1.0.0",
            description: "PURL with version"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: ["arch": "arm64"],
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage?arch=arm64",
            description: "PURL with single qualifier"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: ["os": "macos", "arch": "arm64"],
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage?arch=arm64&os=macos",
            description: "PURL with multiple qualifiers"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: nil,
                subpath: "Sources/MyModule"
            ),
            expectedString: "pkg:swift/MyPackage#Sources/MyModule",
            description: "PURL with subpath"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: "apple",
                name: "swift-package-manager",
                version: "5.9.0",
                qualifiers: ["arch": "arm64", "os": "macos"],
                subpath: "Sources/PackageModel"
            ),
            expectedString: "pkg:swift/apple/swift-package-manager@5.9.0?arch=arm64&os=macos#Sources/PackageModel",
            description: "Complete PURL with all components"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: "kitty",
                name: "meowmeow",
                version: "18.0.0",
                qualifiers: [:],
                subpath: nil
            ),
            expectedString: "pkg:swift/kitty/meowmeow@18.0.0",
            description: "PURL with empty qualifiers dictionary"
        ),

        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: nil,
                subpath: "Meow/MeowMeow/MeowMeowMeow/Meow/Meow.swift"
            ),
            expectedString: "pkg:swift/MyPackage#Meow/MeowMeow/MeowMeowMeow/Meow/Meow.swift",
            description: "PURL with complex subpath"
        ),
        // Test "unknown" version handling - should be omitted from string
        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: "unknown",
                qualifiers: nil,
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage",
            description: "PURL with 'unknown' version (should be omitted)"
        ),

        // Test qualifier ordering - qualifiers should be sorted alphabetically
        PURLStringTestCase(
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: nil,
                name: "MyPackage",
                version: nil,
                qualifiers: ["zebra": "last", "alpha": "first", "middle": "mid"],
                subpath: nil
            ),
            expectedString: "pkg:swift/MyPackage?alpha=first&middle=mid&zebra=last",
            description: "PURL with qualifiers in alphabetical order"
        ),
    ]

    @Test("PURL string representation", arguments: stringRepresentationTestCases)
    func purlStringRepresentation(testCase: PURLStringTestCase) throws {
        let actualString = testCase.purl.description
        #expect(
            actualString == testCase.expectedString,
            "Expected '\(testCase.expectedString)' but got '\(actualString)' for case \(testCase.description)"
        )
    }

    // MARK: - CustomStringConvertible Protocol Conformance Tests

    @Test("PURL conforms to CustomStringConvertible")
    func purlConformsToCustomStringConvertible() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            name: "TestPackage"
        )

        // Verify that PURL can be used as CustomStringConvertible
        let _: CustomStringConvertible = purl

        // Verify description property is accessible
        let description = purl.description
        #expect(!description.isEmpty)
    }

    @Test("PURL description is consistent")
    func purlDescriptionIsConsistent() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            namespace: "github.com/apple",
            name: "swift-package-manager",
            version: "1.0.0",
            qualifiers: ["os": "macos"],
            subpath: "Sources"
        )

        // Multiple calls to description should return the same value
        let description1 = purl.description
        let description2 = purl.description
        #expect(description1 == description2)
    }

    @Test("PURL description can be used in string interpolation")
    func purlDescriptionInStringInterpolation() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            name: "MyPackage",
            version: "1.0.0"
        )

        let interpolated = "Package URL: \(purl)"
        #expect(interpolated == "Package URL: pkg:swift/MyPackage@1.0.0")
    }

    @Test("PURL description handles special characters in components")
    func purlDescriptionWithSpecialCharacters() {
        // Test with hyphens, underscores, and colons (common in package names)
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            namespace: "github.com/my-org",
            name: "my_package:product-name",
            version: "1.0.0-beta.1"
        )

        let description = purl.description
        #expect(description.contains("my-org"))
        #expect(description.contains("my_package:product-name"))
        #expect(description.contains("1.0.0-beta.1"))
    }

    @Test("PURL description with all nil optional components")
    func purlDescriptionWithAllNilOptionals() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            namespace: nil,
            name: "MinimalPackage",
            version: nil,
            qualifiers: nil,
            subpath: nil
        )

        #expect(purl.description == "pkg:swift/MinimalPackage")
    }

    @Test("PURL description format follows PURL specification")
    func purlDescriptionFollowsPURLSpec() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            namespace: "github.com/apple",
            name: "swift-package-manager",
            version: "5.9.0",
            qualifiers: ["arch": "arm64"],
            subpath: "Sources/PackageModel"
        )

        let description = purl.description

        // Verify PURL format: scheme:type/namespace/name@version?qualifiers#subpath
        #expect(description.hasPrefix("pkg:"))
        #expect(description.contains("swift/"))
        #expect(description.contains("github.com/apple/"))
        #expect(description.contains("swift-package-manager"))
        #expect(description.contains("@5.9.0"))
        #expect(description.contains("?arch=arm64"))
        #expect(description.contains("#Sources/PackageModel"))
    }

    @Test("PURL description with multiple qualifiers maintains alphabetical order")
    func purlDescriptionQualifierOrdering() {
        let purl = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            qualifiers: [
                "zoo": "value1",
                "apple": "value2",
                "middle": "value3",
                "beta": "value4",
            ]
        )

        let description = purl.description

        // Verify qualifiers appear in alphabetical order
        let qualifierPart = description.split(separator: "?").last?.split(separator: "#").first
        #expect(qualifierPart == "apple=value2&beta=value4&middle=value3&zoo=value1")
    }

    @Test("PURL description equality matches struct equality")
    func purlDescriptionEqualityMatchesStructEquality() {
        let purl1 = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            version: "1.0.0"
        )

        let purl2 = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            version: "1.0.0"
        )

        let purl3 = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            version: "2.0.0"
        )

        // Equal PURLs should have equal descriptions
        #expect(purl1 == purl2)
        #expect(purl1.description == purl2.description)

        // Different PURLs should have different descriptions
        #expect(purl1 != purl3)
        #expect(purl1.description != purl3.description)
    }

    @Test("PURL description with empty qualifiers dictionary is same as nil qualifiers")
    func purlDescriptionEmptyQualifiersEqualsNil() {
        let purlWithNil = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            qualifiers: nil
        )

        let purlWithEmpty = PURL(
            scheme: "pkg",
            type: "swift",
            name: "Package",
            qualifiers: [:]
        )

        // Both should produce the same description (no qualifiers section)
        #expect(purlWithNil.description == purlWithEmpty.description)
        #expect(purlWithNil == purlWithEmpty)
        #expect(!purlWithNil.description.contains("?"))
        #expect(!purlWithEmpty.description.contains("?"))
    }

    struct PURLNamespaceTestCase {
        let location: String
        let expectedNamespace: String?
    }

    static let packageNamespaceTestCases: [PURLNamespaceTestCase] = [
        // HTTPS URLs with .git extension
        PURLNamespaceTestCase(
            location: "https://github.com/apple/swift-system.git",
            expectedNamespace: "github.com/apple"
        ),
        PURLNamespaceTestCase(
            location: "https://github.com/swiftlang/swift-llbuild.git",
            expectedNamespace: "github.com/swiftlang"
        ),
        PURLNamespaceTestCase(
            location: "https://github.com/swiftlang/swift-package-manager.git",
            expectedNamespace: "github.com/swiftlang"
        ),
        PURLNamespaceTestCase(
            location: "https://gitlab.com/myorg/mypackage.git",
            expectedNamespace: "gitlab.com/myorg"
        ),
        // HTTPS URLs without .git extension
        PURLNamespaceTestCase(
            location: "https://github.com/apple/swift-system",
            expectedNamespace: "github.com/apple"
        ),
        PURLNamespaceTestCase(
            location: "https://github.com/swiftlang/swift-llbuild",
            expectedNamespace: "github.com/swiftlang"
        ),
        // SSH URLs with .git extension
        PURLNamespaceTestCase(
            location: "git@github.com:apple/swift-system.git",
            expectedNamespace: "github.com/apple"
        ),
        PURLNamespaceTestCase(
            location: "git@gitlab.com:myorg/mypackage.git",
            expectedNamespace: "gitlab.com/myorg"
        ),
        // SSH URLs without .git extension
        PURLNamespaceTestCase(
            location: "git@github.com:apple/swift-system",
            expectedNamespace: "github.com/apple"
        ),
        PURLNamespaceTestCase(
            location: "git@github.com:swiftlang/swiftly",
            expectedNamespace: "github.com/swiftlang"
        ),
        // Registry identities
        PURLNamespaceTestCase(
            location: "org.foo",
            expectedNamespace: "org"
        ),
        PURLNamespaceTestCase(
            location: "com.example.package",
            expectedNamespace: "com.example"
        ),
        PURLNamespaceTestCase(
            location: "scope.package-name",
            expectedNamespace: "scope"
        ),
        PURLNamespaceTestCase(
            location: "mona.LinkedList",
            expectedNamespace: "mona"
        ),
        PURLNamespaceTestCase(
            location: "org.swift.swift-package-manager",
            expectedNamespace: "org.swift"
        ),
        PURLNamespaceTestCase(
            location: "io.github.myorg.mypackage",
            expectedNamespace: "io.github.myorg"
        ),
        // Local file paths - should have no namespace (path goes in qualifier instead)
        PURLNamespaceTestCase(
            location: "/Users/username/MyPackage",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "/swift-system",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "/path/to/package",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "/special.character/in/path.to/package",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "/path/to/MyLocalPackage",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "/path/to/git/repo",
            expectedNamespace: nil
        ),
        // Edge cases
        PURLNamespaceTestCase(
            location: "",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "invalid",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "https://github.com/",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "git@github.com:",
            expectedNamespace: nil
        ),
        PURLNamespaceTestCase(
            location: "user@email.com",
            expectedNamespace: nil
        ),
    ]

    @Test("Extract namespace", arguments: packageNamespaceTestCases)
    func extractNamespaceFromLocation(testCase: PURLNamespaceTestCase) async throws {
        let version = SBOMComponent.Version(
            revision: "1.0.0",
            commit: SBOMCommit(sha: "sha", repository: testCase.location)
        )
        let actual = await PURL.extractNamespace(from: version)
        #expect(actual == testCase.expectedNamespace)
    }

    @Test("Create PURL from ResolvedPackage")
    func createPURLFromResolvedPackage() async throws {
        let packageIdentity = PackageIdentity.plain("swift-package-manager")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "TestModule")
        let package = SBOMTestModulesGraph.createPackage(
            identity: packageIdentity,
            displayName: "swift-package-manager",
            path: "/swift-package-manager",
            modules: [module],
            products: []
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedModule]),
            products: []
        )
        
        let purl = await PURL.from(package: resolvedPackage, version: SBOMComponent.Version(revision: "1.0.0", commit: nil))

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == nil)
        #expect(purl.name == "swift-package-manager")
        #expect(purl.version == "1.0.0")
        #expect(purl.description == "pkg:swift/swift-package-manager@1.0.0")
    }

    @Test("Create PURL from ResolvedProduct with package location")
    func createPURLFromResolvedProduct() async throws {
        let packageIdentity = PackageIdentity.plain("swift-package-manager")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "SwiftPMDataModel")
        let productType = ProductType.library(.automatic)
        let product = try Product(
            package: packageIdentity,
            name: "SwiftPMDataModel",
            type: productType,
            modules: [module]
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: packageIdentity,
            product: product,
            modules: IdentifiableSet([resolvedModule])
        )
        
        let purl = await PURL.from(
            product: resolvedProduct,
            version: SBOMComponent.Version(
                revision: "1.0.0",
                commit: SBOMCommit(sha: "sha", repository: "https://github.com/swiftlang/swift-package-manager.git")
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "github.com/swiftlang")
        #expect(purl.name == "swift-package-manager:SwiftPMDataModel")
        #expect(purl.version == "1.0.0")
        #expect(purl.description == "pkg:swift/github.com/swiftlang/swift-package-manager:SwiftPMDataModel@1.0.0")
    }

    @Test("Create PURL from ResolvedProduct with local package")
    func createPURLFromResolvedProductLocalPackage() async throws {
        let packageIdentity = PackageIdentity.plain("swift-package-manager")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "SwiftPMDataModel")
        let productType = ProductType.library(.automatic)
        let product = try Product(
            package: packageIdentity,
            name: "SwiftPMDataModel",
            type: productType,
            modules: [module]
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: packageIdentity,
            product: product,
            modules: IdentifiableSet([resolvedModule])
        )
        
        let localPath = "/Users/someuser/myCode/SwiftPM/"
        let purl = await PURL.from(
            product: resolvedProduct,
            version: SBOMComponent.Version(revision: "1.0.0", commit: SBOMCommit(sha: "sha", repository: localPath))
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.name == "swift-package-manager:SwiftPMDataModel")
        #expect(purl.namespace == nil) // No namespace for local paths
        #expect(purl.version == "1.0.0")
        #expect(purl.qualifiers == ["path": localPath])
        let actualDescription = purl.description
        #expect(actualDescription == "pkg:swift/swift-package-manager:SwiftPMDataModel@1.0.0?path=/Users/someuser/myCode/SwiftPM/")
    }

    @Test("Create PURL from ResolvedProduct with SSH URL")
    func createPURLFromResolvedProductSSH() async throws {
        let packageIdentity = PackageIdentity.plain("swiftly")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "swiftly")
        let productType = ProductType.library(.automatic)
        let product = try Product(
            package: packageIdentity,
            name: "swiftly",
            type: productType,
            modules: [module]
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: packageIdentity,
            product: product,
            modules: IdentifiableSet([resolvedModule])
        )
        
        let purl = await PURL.from(
            product: resolvedProduct,
            version: SBOMComponent.Version(
                revision: "1.0.0",
                commit: SBOMCommit(sha: "sha", repository: "git@github.com:swiftlang/swiftly.git")
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "github.com/swiftlang")
        #expect(purl.name == "swiftly:swiftly")
        #expect(purl.version == "1.0.0")
        #expect(purl.description == "pkg:swift/github.com/swiftlang/swiftly:swiftly@1.0.0")
    }

    @Test("Create PURL from registry package")
    func createPURLFromRegistryPackage() async throws {
        let packageIdentity = PackageIdentity.plain("org.example.mypackage")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "MyPackage")
        let package = SBOMTestModulesGraph.createPackage(
            identity: packageIdentity,
            displayName: "mypackage",
            path: "/path/to/registry/packages/org.example.mypackage",
            modules: [module],
            products: []
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedModule]),
            products: []
        )
        
        let registryEntry = SBOMRegistryEntry(
            url: URL(string: "https://swift.org"),
            scope: "org.example",
            name: "mypackage",
            version: "1.2.3"
        )
        
        let purl = await PURL.from(
            package: resolvedPackage,
            version: SBOMComponent.Version(
                revision: "1.2.3",
                commit: nil,
                entry: registryEntry
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "org.example")
        #expect(purl.name == "mypackage")
        #expect(purl.version == "1.2.3")
        #expect(purl.qualifiers == nil)
        #expect(purl.description == "pkg:swift/org.example/mypackage@1.2.3")
    }

    @Test("Create PURL from registry product")
    func createPURLFromRegistryProduct() async throws {
        let packageIdentity = PackageIdentity.plain("com.company.networking")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "HTTPClient")
        let productType = ProductType.library(.automatic)
        let product = try Product(
            package: packageIdentity,
            name: "HTTPClient",
            type: productType,
            modules: [module]
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: packageIdentity,
            product: product,
            modules: IdentifiableSet([resolvedModule])
        )
        
        let registryEntry = SBOMRegistryEntry(
            url: URL(string: "https://swift.org"),
            scope: "com.company",
            name: "networking",
            version: "2.0.0"
        )
        
        let purl = await PURL.from(
            product: resolvedProduct,
            version: SBOMComponent.Version(
                revision: "2.0.0",
                commit: nil,
                entry: registryEntry
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "com.company")
        #expect(purl.name == "networking:HTTPClient")
        #expect(purl.version == "2.0.0")
        #expect(purl.qualifiers == nil)
        #expect(purl.description == "pkg:swift/com.company/networking:HTTPClient@2.0.0")
    }

    @Test("Create PURL from single-scope registry package")
    func createPURLFromSingleScopeRegistryPackage() async throws {
        let packageIdentity = PackageIdentity.plain("mona.LinkedList")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "LinkedList")
        let package = SBOMTestModulesGraph.createPackage(
            identity: packageIdentity,
            displayName: "LinkedList",
            path: "/path/to/registry/packages/mona.LinkedList",
            modules: [module],
            products: []
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedModule]),
            products: []
        )
        
        let registryEntry = SBOMRegistryEntry(
            url: URL(string: "https://swift.org"),
            scope: "mona",
            name: "LinkedList",
            version: "3.1.4"
        )
        
        let purl = await PURL.from(
            package: resolvedPackage,
            version: SBOMComponent.Version(
                revision: "3.1.4",
                commit: nil,
                entry: registryEntry
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "mona")
        #expect(purl.name == "LinkedList")
        #expect(purl.version == "3.1.4")
        #expect(purl.qualifiers == nil)
        #expect(purl.description == "pkg:swift/mona/LinkedList@3.1.4")
    }

    @Test("Create PURL from registry package with hyphenated name")
    func createPURLFromRegistryPackageWithHyphenatedName() async throws {
        let packageIdentity = PackageIdentity.plain("org.swift.swift-package-manager")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "SwiftPM")
        let package = SBOMTestModulesGraph.createPackage(
            identity: packageIdentity,
            displayName: "swift-package-manager",
            path: "/path/to/registry/packages/org.swift.swift-package-manager",
            modules: [module],
            products: []
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedModule]),
            products: []
        )
        
        let registryEntry = SBOMRegistryEntry(
            url: URL(string: "https://swift.org"),
            scope: "org.swift",
            name: "swift-package-manager",
            version: "5.9.0"
        )
        
        let purl = await PURL.from(
            package: resolvedPackage,
            version: SBOMComponent.Version(
                revision: "5.9.0",
                commit: nil,
                entry: registryEntry
            )
        )

        #expect(purl.scheme == "pkg")
        #expect(purl.type == "swift")
        #expect(purl.namespace == "org.swift")
        #expect(purl.name == "swift-package-manager")
        #expect(purl.version == "5.9.0")
        #expect(purl.qualifiers == nil)
        #expect(purl.description == "pkg:swift/org.swift/swift-package-manager@5.9.0")
    }

    struct PURLQualifiersTestCase {
        let location: String
        let expectedQualifiers: [String: String]?
    }

    static let qualifiersTestCases: [PURLQualifiersTestCase] = [
        // Local absolute paths should have path qualifier
        PURLQualifiersTestCase(
            location: "/Users/jdoe/workspace/project/lib/foo.a",
            expectedQualifiers: ["path": "/Users/jdoe/workspace/project/lib/foo.a"]
        ),
        PURLQualifiersTestCase(
            location: "/Users/username/MyPackage",
            expectedQualifiers: ["path": "/Users/username/MyPackage"]
        ),
        PURLQualifiersTestCase(
            location: "/path/to/package",
            expectedQualifiers: ["path": "/path/to/package"]
        ),
        PURLQualifiersTestCase(
            location: "/swift-system",
            expectedQualifiers: ["path": "/swift-system"]
        ),
        // Remote URLs should have no qualifiers
        PURLQualifiersTestCase(
            location: "https://github.com/apple/swift-system.git",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "https://github.com/swiftlang/swift-package-manager",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "git@github.com:apple/swift-system.git",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "git@github.com:swiftlang/swiftly",
            expectedQualifiers: nil
        ),
        // Registry identities should have no qualifiers
        PURLQualifiersTestCase(
            location: "org.foo",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "com.example.package",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "mona.LinkedList",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "org.swift.swift-package-manager",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "io.github.myorg.mypackage",
            expectedQualifiers: nil
        ),
        PURLQualifiersTestCase(
            location: "",
            expectedQualifiers: nil
        ),
    ]

    @Test("Extract qualifiers", arguments: qualifiersTestCases)
    func extractQualifiersFromLocation(testCase: PURLQualifiersTestCase) async throws {
        let commit = testCase.location.isEmpty ? nil : SBOMCommit(sha: "sha", repository: testCase.location)
        let version = SBOMComponent.Version(revision: "1.0.0", commit: commit)
        let actualQualifiers = await PURL.extractQualifiers(from: version)
        #expect(
            actualQualifiers == testCase.expectedQualifiers,
            "Expected \(String(describing: testCase.expectedQualifiers)) but got \(String(describing: actualQualifiers))"
        )
    }
}
