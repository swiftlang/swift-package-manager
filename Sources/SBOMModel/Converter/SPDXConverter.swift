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

internal struct SPDXConverter {
    private init() {}

    private static func generateSPDXID(_ id: String) -> String {
        if id.starts(with: "urn:") { return id }
        return "urn:spdx:\(id)"
    }

    private static func convertToSPDXPurpose(from category: SBOMComponent.Category) async -> SPDXPackage.Purpose {
        switch category {
        case .application:
            .application
        case .framework:
            .framework
        case .library:
            .library
        case .file:
            .file
        }
    }

    private static func convertToSPDXLicenseExpression(from license: SBOMLicense, creationInfoID: String) async -> SPDXLicenseExpression {
        let id = generateSPDXID(license.name)
        return SPDXLicenseExpression(
            id: id,
            type: SPDXType.LicenseExpression,
            expression: license.name,
            creationInfoID: creationInfoID,
        )
    }
    

    internal static func convertToSPDXAgent(from metadata: SBOMMetadata?) async -> [any SPDXObject] {
        guard let metadata,
              let creators = metadata.creators,
              !creators.isEmpty
        else {
            return []
        }
                
        var agents: [any SPDXObject] = []
        for creator in creators {
            let creatorID = self.generateSPDXID(creator.id.value)
            let toolCreationInfoID = "\(creatorID):creationInfo"
            let toolCreationInfo = SPDXCreationInfo(
                id: toolCreationInfoID,
                type: .CreationInfo,
                specVersion: creator.version,
                createdBy: [creatorID],
                created: "1970-01-01T00:00:00Z"
            )
            let tool = SPDXAgent(
                id: creatorID,
                type: .Agent,
                name: creator.name,
                creationInfoID: toolCreationInfoID
            )
            if let licenses = creator.licenses {
                for license in licenses {
                    let spdxLicense = await convertToSPDXLicenseExpression(from: license, creationInfoID: toolCreationInfoID)
                    let relationship = SPDXRelationship(
                        id: generateSPDXID("\(creatorID)-hasDeclaredLicense-\(spdxLicense.id)"),
                        type: .Relationship,
                        category: .hasDeclaredLicense,
                        creationInfoID: toolCreationInfoID,
                        parentID: creatorID,
                        childrenID: [spdxLicense.id]
                    )
                    agents.append(relationship)
                    agents.append(spdxLicense)
                }
            }
            
            agents.append(toolCreationInfo)
            agents.append(tool)
        }
        return agents
    }

    internal static func convertToSPDXDocument(
        from document: SBOMDocument,
        spec: SBOMSpec
    ) async throws -> [any SPDXObject] {
        guard let timestamp = document.metadata.timestamp,
              let creators = document.metadata.creators,
              !creators.isEmpty
        else {
            throw SBOMConverterError.missingRequiredMetadata(
                message: "timestamp or creators are missing from SBOM document metadata, required for SPDX format"
            )
        }

        var elements: [any SPDXObject] = []

        let creationInfoID = SPDXConstants.spdxRootCreationInfoID

        let creationInfo = SPDXCreationInfo(
            id: creationInfoID,
            type: .CreationInfo,
            specVersion: spec.version,
            createdBy: creators.map { self.generateSPDXID($0.id.value) },
            created: timestamp
        )
        elements.append(creationInfo)

        let spdxSBOMID = SBOMIdentifier.generate().value
        let profileConformance = ["core", "software"]

        let primaryComponentID = self.generateSPDXID(document.primaryComponent.id.value)

        let spdxSBOM = SPDXSBOM(
            id: spdxSBOMID,
            type: .SoftwareSBOM,
            creationInfoID: creationInfoID,
            profileConformance: profileConformance,
            rootElementIDs: [primaryComponentID]
        )
        elements.append(spdxSBOM)

        let describes = SPDXRelationship(
            id: generateSPDXID("\(spdxSBOMID)-describes-\(primaryComponentID)"),
            type: .Relationship,
            category: .describes,
            creationInfoID: creationInfoID,
            parentID: spdxSBOMID,
            childrenID: [primaryComponentID]
        )
        elements.append(describes)

        let spdxDocument = SPDXDocument(
            id: generateSPDXID(document.id.value),
            type: .SpdxDocument,
            creationInfoID: creationInfoID,
            profileConformance: profileConformance,
            rootElementIDs: [spdxSBOMID]
        )
        elements.append(spdxDocument)

        return elements
    }

    internal static func convertToSPDXPackage(from component: SBOMComponent) async throws -> SPDXPackage {
        await SPDXPackage(
            id: self.generateSPDXID(component.id.value),
            type: .SoftwarePackage,
            purpose: self.convertToSPDXPurpose(from: component.category),
            purl: component.purl,
            name: component.name,
            version: component.version.revision,
            creationInfoID: SPDXConstants.spdxRootCreationInfoID,
            description: component.description,
            summary: component.entity.rawValue
        )
    }

    internal static func convertToSPDXExternalIdentifiers(from components: [SBOMComponent]?) async -> [any SPDXObject] {
        guard let comps = components, !comps.isEmpty else {
            return []
        }

        var externalIdentifiers: [any SPDXObject] = []
        var commitToComponents: [String: (repository: String, componentIDs: [String])] = [:]
        for component in comps {
            if let commits = component.originator.commits {
                let componentID = self.generateSPDXID(component.id.value)
                for commit in commits {
                    if commitToComponents[commit.sha] != nil {
                        commitToComponents[commit.sha]?.componentIDs.append(componentID)
                    } else {
                        commitToComponents[commit.sha] = (repository: commit.repository, componentIDs: [componentID])
                    }
                }
            }
        }
        for (commitSHA, commitInfo) in commitToComponents {
            let externalIdentifier = SPDXExternalIdentifier(
                identifier: generateSPDXID(commitSHA),
                identifierLocator: [commitInfo.repository],
                type: .ExternalIdentifier,
                category: .gitoid
            )
            externalIdentifiers.append(externalIdentifier)
            let relationship = SPDXRelationship(
                id: generateSPDXID("\(commitSHA)-generates"),
                type: .Relationship,
                category: .generates,
                creationInfoID: SPDXConstants.spdxRootCreationInfoID,
                parentID: self.generateSPDXID(commitSHA),
                childrenID: commitInfo.componentIDs
            )
            externalIdentifiers.append(relationship)
        }

        return externalIdentifiers
    }

    internal static func convertToSPDXRelationships(from dependencies: SBOMDependencies?) async -> [any SPDXObject] {
        guard let dependencies else {
            return []
        }

        var relationships: [any SPDXObject] = []
        if let sbomRelationships = dependencies.relationships {
            for dependency in sbomRelationships {
                let parentID = self.generateSPDXID(dependency.parentID.value)
                let childrenIDs = dependency.childrenID.map { self.generateSPDXID($0.value) }

                let relationship = SPDXRelationship(
                    id: generateSPDXID("\(dependency.parentID.value)-dependsOn"),
                    type: .Relationship,
                    category: .dependsOn,
                    creationInfoID: SPDXConstants.spdxRootCreationInfoID,
                    parentID: parentID,
                    childrenID: childrenIDs
                )
                relationships.append(relationship)

                var optionalDependencies: [String] = []
                var testDependencies: [String] = []
                for childID in dependency.childrenID {
                    guard let comp = dependencies.components.first(where: { $0.id == childID }) else {
                        continue
                    }
                    let spdxChildID = self.generateSPDXID(childID.value)
                    switch comp.scope {
                    case .optional:
                        optionalDependencies.append(spdxChildID)
                    case .test:
                        testDependencies.append(spdxChildID)
                    default:
                        break
                    }
                }
                if !optionalDependencies.isEmpty {
                    let relationship = SPDXRelationship(
                        id: generateSPDXID("\(dependency.parentID.value)-hasOptionalDependency"),
                        type: .Relationship,
                        category: .hasOptionalDependency,
                        creationInfoID: SPDXConstants.spdxRootCreationInfoID,
                        parentID: parentID,
                        childrenID: optionalDependencies
                    )
                    relationships.append(relationship)
                }
                if !testDependencies.isEmpty {
                    let relationship = SPDXRelationship(
                        id: generateSPDXID("\(dependency.parentID.value)-hasTest"),
                        type: .Relationship,
                        category: .hasTest,
                        creationInfoID: SPDXConstants.spdxRootCreationInfoID,
                        parentID: parentID,
                        childrenID: testDependencies
                    )
                    relationships.append(relationship)
                }
            }
        }

        return relationships
    }

    internal static func convertToSPDXGraph(from document: SBOMDocument, spec: SBOMSpec) async throws -> SPDXGraph {
        guard spec.type.supportsSPDX else {
            throw SBOMError.unexpectedSpecType(expected: "spdx", actual: spec.type)
        }

        let agents = await convertToSPDXAgent(from: document.metadata)
        let elements = try await convertToSPDXDocument(from: document, spec: spec)

        var packages: [any SPDXObject] = []
        for comp in document.dependencies.components {
            let p = try await convertToSPDXPackage(from: comp)
            packages.append(p)
        }

        let relationships = await convertToSPDXRelationships(from: document.dependencies)
        let commits = await convertToSPDXExternalIdentifiers(from: document.dependencies.components)

        return SPDXGraph(
            context: SPDXConstants.spdx3Context,
            graph: agents + elements + packages + relationships + commits
        )
    }
}
