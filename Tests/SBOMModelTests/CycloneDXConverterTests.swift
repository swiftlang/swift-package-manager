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

import Foundation
@testable import SBOMModel
import Testing

struct CycloneDXConverterTests {
    @Test("convertToCycloneDXPedigree with nil commits")
    func convertToCycloneDXPedigreeWithNilCommits() async throws {
        let originator = SBOMOriginator(commits: nil)
        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)
        #expect(result.commits == nil)
    }

    @Test("convertToCycloneDXPedigree with empty commits")
    func convertToCycloneDXPedigreeWithEmptyCommits() async throws {
        let originator = SBOMOriginator(commits: [])
        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)
        #expect(result.commits?.isEmpty == true)
    }

    @Test("convertToCycloneDXPedigree with single commit without authors")
    func convertToCycloneDXPedigreeWithSingleCommitNoAuthors() async throws {
        let originator = SBOMOriginator(commits: [SBOMCommit(
            sha: "abc123",
            repository: "https://github.com/swiftlang/swift-package-manager",
            url: "https://github.com/swiftlang/swift-package-manager/commit/abc123",
            authors: nil,
            message: "Initial commit"
        )])
        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)

        let cdxCommits = try #require(result.commits)
        #expect(cdxCommits.count == 1)

        let cdxCommit = cdxCommits[0]
        #expect(cdxCommit.uid == "abc123")
        #expect(cdxCommit.url == "https://github.com/swiftlang/swift-package-manager")
        #expect(cdxCommit.author == nil)
        #expect(cdxCommit.message == "Initial commit")
    }

    @Test("convertToCycloneDXPedigree with single commit with authors")
    func convertToCycloneDXPedigreeWithSingleCommitWithAuthors() async throws {
        let originator = SBOMOriginator(commits: [
            SBOMCommit(
                sha: "def456",
                repository: "https://github.com/swiftlang/swift-package-manager",
                url: "https://github.com/swiftlang/swift-package-manager/commit/def456",
                authors: [SBOMPerson(
                    id: SBOMIdentifier(value: "author1"),
                    name: "John Doe",
                    email: "john@example.com"
                )],
                message: "Add new feature"
            ),
        ])

        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)

        let cdxCommits = try #require(result.commits)
        #expect(cdxCommits.count == 1)

        let cdxCommit = cdxCommits[0]
        #expect(cdxCommit.uid == "def456")
        #expect(cdxCommit.url == "https://github.com/swiftlang/swift-package-manager")
        #expect(cdxCommit.message == "Add new feature")

        let cdxAuthor = try #require(cdxCommit.author)
        #expect(cdxAuthor.name == "John Doe")
        #expect(cdxAuthor.email == "john@example.com")
    }

    @Test("convertToCycloneDXPedigree with multiple commits")
    func convertToCycloneDXPedigreeWithMultipleCommits() async throws {
        let author1 = SBOMPerson(
            id: SBOMIdentifier(value: "author1"),
            name: "John Doe",
            email: "john@example.com"
        )
        let author2 = SBOMPerson(
            id: SBOMIdentifier(value: "author2"),
            name: "Jane Smith",
            email: "jane@example.com"
        )

        let commit1 = SBOMCommit(
            sha: "abc123",
            repository: "https://github.com/swiftlang/swift-package-manager",
            url: "https://github.com/swiftlang/swift-package-manager/commit/abc123",
            authors: [author1],
            message: "First commit"
        )
        let commit2 = SBOMCommit(
            sha: "def456",
            repository: "https://github.com/swiftlang/swift-package-manager",
            url: nil,
            authors: [author2],
            message: "Second commit"
        )

        let originator = SBOMOriginator(commits: [commit1, commit2])

        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)

        let cdxCommits = try #require(result.commits)
        #expect(cdxCommits.count == 2)

        let cdxCommit1 = cdxCommits[0]
        #expect(cdxCommit1.uid == "abc123")
        #expect(cdxCommit1.url == "https://github.com/swiftlang/swift-package-manager")
        #expect(cdxCommit1.message == "First commit")
        let cdxAuthor1 = try #require(cdxCommit1.author)
        #expect(cdxAuthor1.name == "John Doe")

        let cdxCommit2 = cdxCommits[1]
        #expect(cdxCommit2.uid == "def456")
        #expect(cdxCommit2.url == "https://github.com/swiftlang/swift-package-manager")
        #expect(cdxCommit2.message == "Second commit")
        let cdxAuthor2 = try #require(cdxCommit2.author)
        #expect(cdxAuthor2.name == "Jane Smith")
    }

    @Test("convertToCycloneDXPedigree uses first author only")
    func convertToCycloneDXPedigreeUsesFirstAuthorOnly() async throws {
        let author1 = SBOMPerson(
            id: SBOMIdentifier(value: "author1"),
            name: "John Doe",
            email: "john@example.com"
        )
        let author2 = SBOMPerson(
            id: SBOMIdentifier(value: "author2"),
            name: "Jane Smith",
            email: "jane@example.com"
        )

        let commit = SBOMCommit(
            sha: "abc123",
            repository: "https://github.com/swiftlang/swift-package-manager",
            url: nil,
            authors: [author1, author2],
            message: "Commit with multiple authors"
        )
        let originator = SBOMOriginator(commits: [commit])
        let result = try await CycloneDXConverter.convertToCycloneDXPedigree(from: originator)

        let cdxCommits = try #require(result.commits)
        #expect(cdxCommits.count == 1)
        let cdxCommit = cdxCommits[0]
        let cdxAuthor = try #require(cdxCommit.author)
        #expect(cdxAuthor.name == "John Doe")
        #expect(cdxAuthor.email == "john@example.com")
    }

    @Test("convertToCycloneDXComponent with all categories")
    func convertToCycloneDXComponentWithAllCategories() async throws {
        let categories: [(SBOMComponent.Category, CycloneDXComponent.Category)] = [
            (.application, .application),
            (.framework, .framework),
            (.library, .library),
            (.file, .file),
        ]

        for (sbomCategory, expectedCDXCategory) in categories {
            let component = SBOMComponent(
                category: sbomCategory,
                id: SBOMIdentifier(value: "test-id"),
                purl: "pkg:swift/test@1.0.0",
                name: "TestComponent",
                version: SBOMComponent.Version(revision: "1.0.0"),
                originator: SBOMOriginator(commits: nil),
                scope: .runtime,
                entity: .product
            )

            let result = try await CycloneDXConverter.convertToCycloneDXComponent(from: component)

            #expect(result.type == expectedCDXCategory)
            #expect(result.bomRef == "test-id")
            #expect(result.name == "TestComponent")
            #expect(result.version == "1.0.0")
            #expect(result.scope == .required)
            #expect(result.purl == "pkg:swift/test@1.0.0")
        }
    }

    @Test("convertToCycloneDXComponent with all entities")
    func convertToCycloneDXComponentWithAllEntities() async throws {
        let entities: [(SBOMComponent.Entity, String)] = [
            (.package, SBOMComponent.Entity.package.rawValue),
            (.product, SBOMComponent.Entity.product.rawValue),
        ]

        for (sbomEntity, sbomEntityString) in entities {
            let component = SBOMComponent(
                category: .library,
                id: SBOMIdentifier(value: "test-id"),
                purl: "pkg:swift/test@1.0.0",
                name: "TestComponent",
                version: SBOMComponent.Version(revision: "1.0.0"),
                originator: SBOMOriginator(commits: nil),
                scope: .test,
                entity: sbomEntity
            )

            let result = try await CycloneDXConverter.convertToCycloneDXComponent(from: component)

            #expect(result.type == .library)
            #expect(result.scope == .excluded)
            #expect(result.bomRef == "test-id")
            #expect(result.name == "TestComponent")
            #expect(result.version == "1.0.0")
            #expect(result.purl == "pkg:swift/test@1.0.0")
            let properties = try #require(result.properties)
            #expect(properties.count == 1)
            #expect(properties[0].name == "swift-entity")
            #expect(properties[0].value == sbomEntityString)
        }
    }

    @Test("convertToCycloneDXComponent with all scopes")
    func convertToCycloneDXComponentWithAllScopes() async throws {
        let scopes: [(SBOMComponent.Scope?, CycloneDXComponent.Scope)] = [
            (.runtime, .required),
            (.optional, .optional),
            (.test, .excluded),
            (nil, .required),
        ]

        for (sbomScope, expectedCDXScope) in scopes {
            let component = SBOMComponent(
                category: .library,
                id: SBOMIdentifier(value: "test-id"),
                purl: "pkg:swift/test@1.0.0",
                name: "TestComponent",
                version: SBOMComponent.Version(revision: "1.0.0"),
                originator: SBOMOriginator(commits: nil),
                scope: sbomScope,
                entity: .product
            )

            let result = try await CycloneDXConverter.convertToCycloneDXComponent(from: component)

            #expect(result.type == .library)
            #expect(result.scope == expectedCDXScope)
            #expect(result.bomRef == "test-id")
            #expect(result.name == "TestComponent")
            #expect(result.version == "1.0.0")
            #expect(result.purl == "pkg:swift/test@1.0.0")
        }
    }

    @Test("convertToCycloneDXComponent with pedigree")
    func convertToCycloneDXComponentWithPedigree() async throws {
        let originator = SBOMOriginator(commits: [
            SBOMCommit(
                sha: "abc123",
                repository: "https://github.com/swiftlang/swift-package-manager",
                url: "https://github.com/swiftlang/swift-package-manager/commit/abc123",
                authors: [
                    SBOMPerson(
                        id: SBOMIdentifier(value: "author1"),
                        name: "John Doe",
                        email: "john@example.com"
                    ),
                ],
                message: "Initial commit"
            ),
        ])

        let component = SBOMComponent(
            category: .library,
            id: SBOMIdentifier(value: "test-id"),
            purl: "pkg:swift/test@1.0.0",
            name: "TestComponent",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: originator,
            scope: .runtime,
            entity: .product
        )

        let result = try await CycloneDXConverter.convertToCycloneDXComponent(from: component)

        #expect(result.type == .library)
        #expect(result.bomRef == "test-id")
        #expect(result.name == "TestComponent")
        #expect(result.version == "1.0.0")
        #expect(result.scope == .required)
        #expect(result.purl == "pkg:swift/test@1.0.0")

        let pedigree = try #require(result.pedigree)
        let commits = try #require(pedigree.commits)
        #expect(commits.count == 1)

        let cdxCommit = commits[0]
        #expect(cdxCommit.uid == "abc123")
        #expect(cdxCommit.url == "https://github.com/swiftlang/swift-package-manager")
        #expect(cdxCommit.message == "Initial commit")

        let cdxAuthor = try #require(cdxCommit.author)
        #expect(cdxAuthor.name == "John Doe")
        #expect(cdxAuthor.email == "john@example.com")
    }

    @Test("convertToCycloneDXDependency basic conversion")
    func convertToCycloneDXDependencyBasicConversion() async throws {
        let result = try await CycloneDXConverter.convertToCycloneDXDependency(from:
            SBOMRelationship(
                id: SBOMIdentifier(value: "dep-1"),
                parentID: SBOMIdentifier(value: "parent-component"),
                childrenID: ["child1", "child2", "child3"].map { SBOMIdentifier(value: $0) }
            )
        )

        #expect(result.ref == "parent-component")
        #expect(result.dependsOn == ["child1", "child2", "child3"])
    }

    @Test("convertToCycloneDXDependency with empty children")
    func convertToCycloneDXDependencyWithEmptyChildren() async throws {
        let result = try await CycloneDXConverter.convertToCycloneDXDependency(from:
            SBOMRelationship(
                id: SBOMIdentifier(value: "dep-1"),
                parentID: SBOMIdentifier(value: "parent-component"),
                childrenID: []
            )
        )
        #expect(result.ref == "parent-component")
        #expect(result.dependsOn.isEmpty)
    }

    @Test("convertToCycloneDXMetadata basic conversion")
    func convertToCycloneDXMetadataBasicConversion() async throws {
        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: nil
        )
        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )

        let document = SBOMDocument(
            id: SBOMIdentifier(value: "doc-1"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [primaryComponent], relationships: nil)
        )

        let result = try await CycloneDXConverter.convertToCycloneDXMetadata(from: document)

        #expect(result.timestamp == "2025-01-01T00:00:00Z")
        #expect(result.component.bomRef == "primary-id")
        #expect(result.component.name == "PrimaryApp")
        #expect(result.component.type == .application)
        #expect(result.component.purl == "pkg:swift/primary@1.0.0")
        #expect(result.component.version == "1.0.0")
        #expect(result.tools == nil)
    }

    @Test("convertToCycloneDXMetadata with nil timestamp")
    func convertToCycloneDXMetadataWithNilTimestamp() async throws {
        let metadata = SBOMMetadata(
            timestamp: nil,
            creators: nil
        )
        let primaryComponent = SBOMComponent(
            category: .framework,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@2.0.0",
            name: "PrimaryFramework",
            version: SBOMComponent.Version(revision: "2.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )
        let document = SBOMDocument(
            id: SBOMIdentifier(value: "doc-1"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [primaryComponent], relationships: nil)
        )

        let result = try await CycloneDXConverter.convertToCycloneDXMetadata(from: document)

        #expect(result.timestamp == nil)
        #expect(result.component.bomRef == "primary-id")
        #expect(result.component.name == "PrimaryFramework")
        #expect(result.component.type == .framework)
        #expect(result.component.purl == "pkg:swift/primary@2.0.0")
        #expect(result.component.version == "2.0.0")
        #expect(result.tools == nil)
    }

    @Test("convertToCycloneDXDocument with no components or dependencies")
    func convertToCycloneDXDocumentWithMinimalData() async throws {
        let spec = SBOMSpec(spec: .cyclonedx)
        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: nil
        )

        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )

        let document = SBOMDocument(
            id: SBOMIdentifier(value: "urn:uuid:12345678-1234-1234-1234-123456789abc"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [], relationships: nil)
        )

        let result = try await CycloneDXConverter.convertToCycloneDXDocument(from: document, spec: spec)

        #expect(result.bomFormat == "CycloneDX")
        #expect(result.specVersion == "1.7")
        #expect(result.serialNumber == "urn:uuid:12345678-1234-1234-1234-123456789abc")
        #expect(result.version == 1)
        #expect(result.metadata.component.bomRef == "primary-id")
        #expect(result.components?.isEmpty ?? false)
        #expect(result.dependencies?.isEmpty ?? false)
    }

    @Test("convertToCycloneDXDocument with components and dependencies")
    func convertToCycloneDXDocumentWithComponentsAndDependencies() async throws {
        let spec = SBOMSpec(spec: .cyclonedx)
        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: nil
        )
        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )
        let component1 = SBOMComponent(
            category: .library,
            id: SBOMIdentifier(value: "lib1-id"),
            purl: "pkg:swift/lib1@1.0.0",
            name: "Library1",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )
        let component2 = SBOMComponent(
            category: .framework,
            id: SBOMIdentifier(value: "framework1-id"),
            purl: "pkg:swift/framework1@2.0.0",
            name: "Framework1",
            version: SBOMComponent.Version(revision: "2.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .optional,
            entity: .product
        )
        let dependency1 = SBOMRelationship(
            id: SBOMIdentifier(value: "dep-1"),
            parentID: SBOMIdentifier(value: "primary-id"),
            childrenID: ["lib1-id", "framework1-id"].map { SBOMIdentifier(value: $0) }
        )
        let dependency2 = SBOMRelationship(
            id: SBOMIdentifier(value: "dep-2"),
            parentID: SBOMIdentifier(value: "lib1-id"),
            childrenID: ["framework1-id"].map { SBOMIdentifier(value: $0) }
        )
        let document = SBOMDocument(
            id: SBOMIdentifier(value: "urn:uuid:12345678-1234-1234-1234-123456789abc"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(
                components: [component1, component2],
                relationships: [dependency1, dependency2]
            )
        )

        let result = try await CycloneDXConverter.convertToCycloneDXDocument(from: document, spec: spec)

        #expect(result.bomFormat == "CycloneDX")
        #expect(result.specVersion == "1.7")
        #expect(result.serialNumber == "urn:uuid:12345678-1234-1234-1234-123456789abc")
        #expect(result.version == 1)

        #expect(result.metadata.timestamp == "2025-01-01T00:00:00Z")
        #expect(result.metadata.component.bomRef == "primary-id")
        #expect(result.metadata.component.name == "PrimaryApp")

        let components = try #require(result.components)
        #expect(components.count == 2)

        let cdxComponent1 = components[0]
        #expect(cdxComponent1.bomRef == "lib1-id")
        #expect(cdxComponent1.name == "Library1")
        #expect(cdxComponent1.type == .library)
        #expect(cdxComponent1.scope == .required)

        let cdxComponent2 = components[1]
        #expect(cdxComponent2.bomRef == "framework1-id")
        #expect(cdxComponent2.name == "Framework1")
        #expect(cdxComponent2.type == .framework)
        #expect(cdxComponent2.scope == .optional)

        let dependencies = try #require(result.dependencies)
        #expect(dependencies.count == 2)

        let cdxDependency1 = dependencies[0]
        #expect(cdxDependency1.ref == "primary-id")
        #expect(cdxDependency1.dependsOn == ["lib1-id", "framework1-id"])

        let cdxDependency2 = dependencies[1]
        #expect(cdxDependency2.ref == "lib1-id")
        #expect(cdxDependency2.dependsOn == ["framework1-id"])
    }

    @Test("convertToCycloneDXDocument with empty components and dependencies")
    func convertToCycloneDXDocumentWithEmptyComponentsAndDependencies() async throws {
        let spec = SBOMSpec(spec: .cyclonedx)

        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: nil
        )
        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )
        let document = SBOMDocument(
            id: SBOMIdentifier(value: "urn:uuid:12345678-1234-1234-1234-123456789abc"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [], relationships: [])
        )
        let result = try await CycloneDXConverter.convertToCycloneDXDocument(from: document, spec: spec)

        #expect(result.bomFormat == "CycloneDX")
        #expect(result.specVersion == "1.7")
        #expect(result.serialNumber == "urn:uuid:12345678-1234-1234-1234-123456789abc")
        #expect(result.version == 1)

        let components = try #require(result.components)
        #expect(components.isEmpty)

        let dependencies = try #require(result.dependencies)
        #expect(dependencies.isEmpty)
    }

    @Test("convertToCycloneDXMetadata with creators/tools")
    func convertToCycloneDXMetadataWithCreators() async throws {
        let license1 = SBOMLicense(name: "Apache-2.0", url: "https://www.apache.org/licenses/LICENSE-2.0")
        let license2 = SBOMLicense(name: "MIT", url: nil)
        let tool1 = SBOMTool(
            id: SBOMIdentifier(value: "tool-1"),
            name: "SwiftPM",
            version: "6.0.0",
            licenses: [license1]
        )
        let tool2 = SBOMTool(
            id: SBOMIdentifier(value: "tool-2"),
            name: "Swift",
            version: "5.9.0",
            licenses: [license2]
        )
        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: [tool1, tool2]
        )
        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )
        let document = SBOMDocument(
            id: SBOMIdentifier(value: "doc-1"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [], relationships: [])
        )

        let result = try await CycloneDXConverter.convertToCycloneDXMetadata(from: document)

        #expect(result.timestamp == "2025-01-01T00:00:00Z")
        #expect(result.component.bomRef == "primary-id")
        #expect(result.component.name == "PrimaryApp")

        let tools = try #require(result.tools)
        #expect(tools.components.count == 2)

        let cdxTool1 = tools.components[0]
        #expect(cdxTool1.bomRef == "tool-1")
        #expect(cdxTool1.name == "SwiftPM")
        #expect(cdxTool1.version == "6.0.0")
        #expect(cdxTool1.type == .application)
        #expect(cdxTool1.scope == .excluded)
        #expect(cdxTool1.purl == "pkg:swift/github.com/swiftlang/SwiftPM@6.0.0")
        
        let cdxTool1Licenses = try #require(cdxTool1.licenses)
        #expect(cdxTool1Licenses.count == 1)
        #expect(cdxTool1Licenses[0].license.id == "Apache-2.0")
        #expect(cdxTool1Licenses[0].license.url == "https://www.apache.org/licenses/LICENSE-2.0")

        let cdxTool2 = tools.components[1]
        #expect(cdxTool2.bomRef == "tool-2")
        #expect(cdxTool2.name == "Swift")
        #expect(cdxTool2.version == "5.9.0")
        #expect(cdxTool2.type == .application)
        #expect(cdxTool2.scope == .excluded)
        #expect(cdxTool2.purl == "pkg:swift/github.com/swiftlang/Swift@5.9.0")
        
        let cdxTool2Licenses = try #require(cdxTool2.licenses)
        #expect(cdxTool2Licenses.count == 1)
        #expect(cdxTool2Licenses[0].license.id == "MIT")
        #expect(cdxTool2Licenses[0].license.url == nil)
    }

    @Test("convertToCycloneDXMetadata with empty creators")
    func convertToCycloneDXMetadataWithEmptyCreators() async throws {
        let metadata = SBOMMetadata(
            timestamp: "2025-01-01T00:00:00Z",
            creators: []
        )
        let primaryComponent = SBOMComponent(
            category: .application,
            id: SBOMIdentifier(value: "primary-id"),
            purl: "pkg:swift/primary@1.0.0",
            name: "PrimaryApp",
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(commits: nil),
            scope: .runtime,
            entity: .product
        )

        let document = SBOMDocument(
            id: SBOMIdentifier(value: "doc-1"),
            metadata: metadata,
            primaryComponent: primaryComponent,
            dependencies: SBOMDependencies(components: [], relationships: [])
        )

        let result = try await CycloneDXConverter.convertToCycloneDXMetadata(from: document)

        #expect(result.timestamp == "2025-01-01T00:00:00Z")
        #expect(result.component.bomRef == "primary-id")
        #expect(result.tools == nil)
    }
}
