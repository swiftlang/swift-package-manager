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
import PackageCollections
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility

/// Extractor for generating SBOM documents
internal struct SBOMExtractor {
    let modulesGraph: ModulesGraph
    let dependencyGraph: [String: [String]]?
    let store: ResolvedPackagesStore
    let caches: SBOMCaches

    internal init(
        modulesGraph: ModulesGraph,
        dependencyGraph: [String: [String]]? = nil,
        store: ResolvedPackagesStore
    ) {
        self.modulesGraph = modulesGraph
        self.dependencyGraph = dependencyGraph
        self.store = store
        self.caches = SBOMCaches()
    }

    internal init(
        modulesGraph: ModulesGraph,
        dependencyGraph: [String: [String]]? = nil,
        store: ResolvedPackagesStore,
        caches: SBOMCaches
    ) {
        self.modulesGraph = modulesGraph
        self.dependencyGraph = dependencyGraph
        self.store = store
        self.caches = caches
    }

    internal func extractMetadata() async throws -> SBOMMetadata {
        SBOMMetadata(
            timestamp: Date().ISO8601Format(),
            creators: [
                SBOMTool(
                    id: SBOMIdentifier.generate(),
                    name: "swift-package-manager",
                    version: SwiftVersion.current.displayString,
                    purl: PURL(
                        scheme: "pkg",
                        type: "swift",
                        namespace: "github.com/swiftlang",
                        name: "swift-package-manager",
                        version: SwiftVersion.current.displayString
                    ),
                    licenses: [
                        SBOMLicense( // TODO: echeng3805: better way to get license without hard-coding and without network call?
                        // can't read the license in the root directory bc SBOM generation isn't always running in swift-package-manager
                            name: PackageCollectionsModel.LicenseType.Apache2_0.description,
                            url: "http://swift.org/LICENSE.txt"
                        ),
                    ]
                ),
            ]
        )
    }

    internal static func extractCategory(from package: ResolvedPackage) throws -> SBOMComponent.Category {
        let productCategories = package.products.map(\.type)
        if productCategories.contains(.executable) {
            return .application
        }
        return .library
    }

    internal static func extractCategory(from product: ResolvedProduct) throws -> SBOMComponent.Category {
        switch product.type {
        case .executable:
            .application
        case .library, .snippet, .plugin, .test, .macro:
            .library
        }
    }

    internal static func extractScope(from product: ResolvedProduct) throws -> SBOMComponent.Scope {
        if product.type == .test {
            return .test
        }
        guard !product.modules.isEmpty else {
            return .runtime
        }
        let allModulesAreTests = product.modules.allSatisfy { $0.type == .test }
        return allModulesAreTests ? .test : .runtime
    }

    internal static func extractScope(from package: ResolvedPackage) throws -> SBOMComponent.Scope {
        guard !package.products.isEmpty else {
            return .runtime
        }
        let allProductsAreTests = package.products.allSatisfy { product in
            product.isLinkingXCTest || product.type == .test
        }
        return allProductsAreTests ? .test : .runtime
    }

    private func extractComponentInfoFromGit(packagePath: AbsolutePath) async throws -> SBOMGitInfo {
        let gitRepo = GitRepository(path: packagePath, isWorkingRepo: true)

        let currentRevision = try? gitRepo.getCurrentRevision()
        guard let currentRevision else {
            return SBOMGitInfo(
                version: SBOMComponent.Version(revision: "unknown"),
                originator: SBOMOriginator(commits: nil)
            )
        }

        let hasUncommittedChanges = gitRepo.hasUncommittedChanges()
        let currentTag = gitRepo.getCurrentTag()
        let revisionString: String = if let currentTag {
            hasUncommittedChanges ? "\(currentTag)-modified" : currentTag
        } else {
            hasUncommittedChanges ? "\(currentRevision.identifier)-modified" : currentRevision.identifier
        }

        let commit = try gitRepo.getCurrentBranch()
            .flatMap { try? gitRepo.getRemote(for: $0) }
            .map { SBOMCommit(sha: currentRevision.identifier, repository: $0.1) }
        let versionCommit = commit
        let commits = commit.map { [$0] }

        return SBOMGitInfo(
            version: SBOMComponent.Version(
                revision: revisionString,
                commit: versionCommit
            ),
            originator: SBOMOriginator(commits: commits)
        )
    }

    private func extractComponentVersionAndCommits(from packageIdentity: PackageIdentity) async throws -> SBOMGitInfo {
        if let cachedGitInfo = await caches.git.get(packageIdentity) {
            return cachedGitInfo
        }
        // root package (try to get version and commits from git)
        if let rootPackage = modulesGraph.rootPackages.first(where: { $0.identity == packageIdentity }) {
            let gitInfo = try await extractComponentInfoFromGit(packagePath: rootPackage.path)
            await self.caches.git.set(packageIdentity, gitInfo: gitInfo)
            return gitInfo
        }
        guard let resolvedPackage = store.resolvedPackages[packageIdentity] else {
            return SBOMGitInfo(
                version: SBOMComponent.Version(revision: "unknown"),
                originator: SBOMOriginator(commits: nil)
            )
        }
        // non-root package (version is from store)
        let version: String
        let sha: String
        switch resolvedPackage.state {
        case .version(let versionValue, let revision):
            version = versionValue.description
            if let revision {
                sha = revision
            } else {
                sha = "unknown"
            }
        case .branch(_, let revision), .revision(let revision):
            version = revision
            sha = revision
        }
        let commit = SBOMCommit(
            sha: sha,
            repository: resolvedPackage.packageRef.kind.locationString // absolute path, URL string, or package identity
        )
        return SBOMGitInfo(
            version: SBOMComponent.Version(revision: version, commit: commit),
            originator: SBOMOriginator(commits: [commit])
        )
    }

    internal static func extractComponentID(from package: ResolvedPackage) -> SBOMIdentifier {
        SBOMIdentifier(value: package.identity.description)
    }

    internal static func extractComponentID(from product: ResolvedProduct) -> SBOMIdentifier {
        SBOMIdentifier(value: "\(product.packageIdentity):\(product.name)")
    }

    private func extractProductsFromPackage(package: ResolvedPackage) async throws -> [SBOMComponent] {
        var productComponents: [SBOMComponent] = []
        for product in package.products {
            let productComponent = try await extractComponent(product: product)
            productComponents.append(productComponent)
        }
        return productComponents
    }

    internal func extractComponent(package: ResolvedPackage) async throws -> SBOMComponent {
        if let cached = await caches.component.getPackage(package.identity) {
            return cached
        }

        let gitInfo = try await extractComponentVersionAndCommits(from: package.identity)
        let products = try await extractProductsFromPackage(package: package)
        let component = try await SBOMComponent(
            category: Self.extractCategory(from: package),
            id: Self.extractComponentID(from: package),
            purl: PURL.from(package: package, version: gitInfo.version),
            name: package.identity.description,
            version: gitInfo.version,
            originator: gitInfo.originator,
            description: package.description,
            scope: Self.extractScope(from: package),
            components: products,
            entity: .package
        )

        await self.caches.component.setPackage(package.identity, component: component)

        return component
    }

    internal func extractComponent(product: ResolvedProduct) async throws -> SBOMComponent {
        if let cached = await caches.component.getProduct(product.packageIdentity, productName: product.name) {
            return cached
        }

        let gitInfo = try await extractComponentVersionAndCommits(from: product.packageIdentity)
        let component = try await SBOMComponent(
            category: Self.extractCategory(from: product),
            id: Self.extractComponentID(from: product),
            purl: PURL.from(product: product, version: gitInfo.version),
            name: product.name,
            version: gitInfo.version,
            originator: gitInfo.originator,
            description: nil,
            scope: Self.extractScope(from: product),
            entity: .product
        )

        await self.caches.component.setProduct(product.packageIdentity, productName: product.name, component: component)

        return component
    }

    internal func extractPrimaryComponent(product: String? = nil) async throws -> SBOMComponent {
        guard let rootPackage = modulesGraph.rootPackages.first else {
            throw SBOMExtractorError.noRootPackage(context: "determine primary component for SBOM")
        }
        // product of root package
        if let productName = product {
            guard let resolvedProduct = rootPackage.products.first(where: { $0.name == productName }) else {
                throw SBOMExtractorError.productNotFound(
                    productName: productName,
                    packageIdentity: rootPackage.identity.description
                )
            }
            return try await self.extractComponent(product: resolvedProduct)
        }
        // root package
        return try await self.extractComponent(package: rootPackage)
    }

    internal func extractSBOM(product: String? = nil, filter: Filter = .all) async throws -> SBOMDocument {
        try await SBOMDocument(
            id: SBOMIdentifier.generate(),
            metadata: self.extractMetadata(),
            primaryComponent: self.extractPrimaryComponent(product: product), // either a root package or a product of the root package
            dependencies: extractDependencies(product: product, filter: filter)
        )
    }
}
