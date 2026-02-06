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

internal struct CycloneDXConverter {
    private init() {}

    private static func convertToScope(from scope: SBOMComponent.Scope) async -> CycloneDXComponent.Scope {
        switch scope {
        case .runtime:
            .required
        case .optional:
            .optional
        case .test:
            .excluded
        }
    }

    private static func convertToCategory(from category: SBOMComponent.Category) async -> CycloneDXComponent
        .Category
    {
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

    internal static func convertToLicense(from license: SBOMLicense) -> CycloneDXLicense {
        return CycloneDXLicense(
            license: CycloneDXLicenseInfo(
                id: license.name,
                url: license.url
            ),
        )
    }

    internal static func convertToSchema(from spec: SBOMSpec) async throws -> String {
        switch spec.concreteSpec {
        case .cyclonedx1:
            return CycloneDXConstants.cyclonedx1Schema
        // case .cyclonedx2:
        //     return CycloneDXConstants.cyclonedx2Schema
        case .spdx3:
            throw SBOMError.unexpectedSpecType(expected: "cyclonedx", actual: spec)
        }
    }

    internal static func convertToPedigree(from originator: SBOMOriginator) async throws -> CycloneDXPedigree {
        guard let sbomCommits = originator.commits else {
            return CycloneDXPedigree(commits: nil)
        }

        let cyclonedxCommits = sbomCommits.map { sbomCommit in
            let cyclonedxAuthor: CycloneDXAction? = sbomCommit.authors?.first.map { sbomPerson in
                CycloneDXAction(
                    name: sbomPerson.name,
                    email: sbomPerson.email
                )
            }

            return CycloneDXCommit(
                uid: sbomCommit.sha,
                url: sbomCommit.repository,
                author: cyclonedxAuthor,
                message: sbomCommit.message
            )
        }

        return CycloneDXPedigree(commits: cyclonedxCommits)
    }

    internal static func convertToComponent(from comp: SBOMComponent) async throws -> CycloneDXComponent {
        try await CycloneDXComponent(
            type: self.convertToCategory(from: comp.category),
            bomRef: comp.id.value,
            name: comp.name,
            version: comp.version.revision,
            scope: self.convertToScope(from: comp.scope ?? .runtime),
            purl: comp.purl,
            pedigree: self.convertToPedigree(from: comp.originator),
            properties: [CycloneDXProperty(name: "swift-entity", value: comp.entity.rawValue)]
        )
    }

    private static func convertToComponent(from tool: SBOMTool) async throws -> CycloneDXComponent {
        let licenses = tool.licenses?.map { license in
            convertToLicense(from: license)
        }
        
        return CycloneDXComponent(
            type: .application,
            bomRef: tool.id.value,
            name: tool.name,
            version: tool.version,
            scope: .excluded,
            purl: PURL(
                scheme: "pkg",
                type: "swift",
                namespace: "github.com/swiftlang",
                name: tool.name,
                version: tool.version
            ).description,
            pedigree: nil,
            licenses: licenses
        )
    }

    internal static func convertToDependency(from dep: SBOMRelationship) async throws -> CycloneDXDependency {
        CycloneDXDependency(
            ref: dep.parentID.value,
            dependsOn: dep.childrenID.map(\.value)
        )
    }

    internal static func convertToMetadata(from document: SBOMDocument) async throws -> CycloneDXMetadata {
        var tools: CycloneDXTools? = nil
        if let creators = document.metadata.creators, !creators.isEmpty {
            var toolsComponents: [CycloneDXComponent] = []
            for creator in creators {
                let cyclonedxTool = try await convertToComponent(from: creator)
                toolsComponents.append(cyclonedxTool)
            }
            tools = CycloneDXTools(components: toolsComponents)
        }

        return try await CycloneDXMetadata(
            timestamp: document.metadata.timestamp,
            component: self.convertToComponent(from: document.primaryComponent),
            tools: tools
        )
    }

    internal static func convertToDocument(
        from document: SBOMDocument,
        spec: SBOMSpec
    ) async throws -> CycloneDXDocument {
        guard spec.supportsCycloneDX else {
            throw SBOMError.unexpectedSpecType(expected: "cyclonedx", actual: spec)
        }

        var components: [CycloneDXComponent] = []
        for sbomComp in document.dependencies.components {
            let cyclonedxComp = try await convertToComponent(from: sbomComp)
            components.append(cyclonedxComp)
        }

        var dependencies: [CycloneDXDependency] = []
        if let documentDependencies = document.dependencies.relationships {
            for sbomDep in documentDependencies {
                let cyclonedxDep = try await convertToDependency(from: sbomDep)
                dependencies.append(cyclonedxDep)
            }
        }

        return try await CycloneDXDocument(
            schema: self.convertToSchema(from: spec),
            bomFormat: "CycloneDX",
            specVersion: spec.versionString,
            serialNumber: document.id.value,
            version: 1,
            metadata: self.convertToMetadata(from: document),
            components: components,
            dependencies: dependencies
        )
    }
}
