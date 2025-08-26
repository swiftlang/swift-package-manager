//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency

import struct Basics.AbsolutePath
import func Basics.depthFirstSearch
import struct Basics.Diagnostic
import struct Basics.InternalError
import class Basics.ObservabilityScope
import struct Basics.SwiftVersion
import class Basics.ThreadSafeKeyValueStore
import class Dispatch.DispatchGroup
import struct Dispatch.DispatchTime
import struct OrderedCollections.OrderedDictionary
import struct OrderedCollections.OrderedSet
import protocol PackageGraph.CustomPackageContainer
import struct PackageGraph.GraphLoadingNode
import struct PackageGraph.PackageContainerConstraint
import struct PackageGraph.PackageGraphRoot
import class PackageLoading.ManifestLoader
import struct PackageLoading.ManifestValidator
import struct PackageLoading.ToolsVersionParser
import class PackageModel.Manifest
import struct PackageModel.PackageIdentity
import struct PackageModel.PackageReference
import enum PackageModel.ProductFilter
import struct PackageModel.ToolsVersion
import enum PackageModel.TraitConfiguration
import protocol TSCBasic.FileSystem
import func TSCBasic.findCycle
import struct TSCBasic.KeyedPair
import struct TSCBasic.StringError
import func TSCBasic.topologicalSort
import func TSCBasic.transitiveClosure
import enum TSCUtility.Diagnostics
import struct TSCUtility.Version

// MARK: - Manifest Loading and caching

extension Workspace {
    /// A struct representing all the current manifests (root + external) in a package graph.
    public struct DependencyManifests {
        /// The package graph root.
        var root: PackageGraphRoot

        /// The dependency manifests in the transitive closure of root manifest.
        let dependencies: [(
            manifest: Manifest,
            dependency: ManagedDependency,
            productFilter: ProductFilter,
            fileSystem: FileSystem
        )]

        private let workspace: Workspace

        private let observabilityScope: ObservabilityScope

        private let _dependencies: LoadableResult<(
            required: OrderedCollections.OrderedSet<PackageReference>,
            missing: OrderedCollections.OrderedSet<PackageReference>,
            unused: OrderedCollections.OrderedSet<PackageReference>
        )>

        private let _constraints: LoadableResult<[PackageContainerConstraint]>

        fileprivate init(
            root: PackageGraphRoot,
            dependencies: [(
                manifest: Manifest,
                dependency: ManagedDependency,
                productFilter: ProductFilter,
                fileSystem: FileSystem
            )],
            workspace: Workspace,
            observabilityScope: ObservabilityScope
        ) {
            self.root = root
            self.dependencies = dependencies
            self.workspace = workspace
            self.observabilityScope = observabilityScope
            self._dependencies = LoadableResult {
                try Self.computeDependencies(
                    root: root,
                    dependencies: dependencies,
                    workspace: workspace,
                    observabilityScope: observabilityScope
                )
            }
            self._constraints = LoadableResult {
                try Self.computeConstraints(
                    root: root,
                    dependencies: dependencies,
                    workspace: workspace
                )
            }
        }

        /// Returns all manifests contained in DependencyManifests.
        public var allDependencyManifests: OrderedCollections.OrderedDictionary<
            PackageIdentity,
            (manifest: Manifest, fs: FileSystem)
        > {
            self.dependencies.reduce(into: OrderedCollections.OrderedDictionary<
                PackageIdentity,
                (manifest: Manifest, fs: FileSystem)
            >()) { partial, item in
                partial[item.dependency.packageRef.identity] = (item.manifest, item.fileSystem)
            }
        }

        /// Computes the identities which are declared in the manifests but aren't present in dependencies.
        public var missingPackages: [PackageReference] {
            get throws {
                try self._dependencies.load().missing.elements
            }
        }

        /// Computes the identities which are declared in the manifests but aren't present in dependencies.
        public var requiredPackages: [PackageReference] {
            get throws {
                try self._dependencies.load().required.elements
            }
        }

        /// Computes the identities which are declared in the manifests are aren't used by any targets.
        public var unusedPackages: [PackageReference] {
            get throws {
                try self._dependencies.load().unused.elements
            }
        }

        /// Returns the list of packages which are allowed to vend products with unsafe flags.
        var unsafeAllowedPackages: Set<PackageReference> {
            var result = Set<PackageReference>()

            for dependency in self.dependencies {
                let dependency = dependency.dependency
                switch dependency.state {
                case .sourceControlCheckout(let checkout):
                    let packageRef = dependency.packageRef

                    if checkout.isBranchOrRevisionBased
                        // FIXME: Remove this once we have a general mechanism
                        //        for passing "safe" flags.
                        || packageRef.identity == .plain("swift-corelibs-foundation")
                    {
                        result.insert(packageRef)
                    }

                case .registryDownload, .custom:
                    continue

                case .fileSystem, .edited:
                    result.insert(dependency.packageRef)
                }
            }

            // Root packages are always allowed to use unsafe flags.
            result.formUnion(root.packageReferences)

            return result
        }

        private static func computeDependencies(
            root: PackageGraphRoot,
            dependencies: [(
                manifest: Manifest,
                dependency: ManagedDependency,
                productFilter: ProductFilter,
                fileSystem: FileSystem
            )],
            workspace: Workspace,
            observabilityScope: ObservabilityScope
        ) throws
            -> (
                required: OrderedCollections.OrderedSet<PackageReference>,
                missing: OrderedCollections.OrderedSet<PackageReference>,
                unused: OrderedCollections.OrderedSet<PackageReference>
            )
        {
            // Temporary countermeasures against rdar://83316222; be robust against having colliding identities in both
            // `root.packages` and `dependencies`.
            var manifestsMap: [PackageIdentity: Manifest] = [:]
            root.packages.map { ($0.key, $0.value.manifest) }.forEach {
                if manifestsMap[$0.0] == nil {
                    manifestsMap[$0.0] = $0.1
                }
            }
            dependencies.map { ($0.dependency.packageRef.identity, $0.manifest) }.forEach {
                if manifestsMap[$0.0] == nil {
                    manifestsMap[$0.0] = $0.1
                }
            }

            var unusedIdentities: OrderedCollections.OrderedSet<PackageReference> = []
            var inputIdentities: OrderedCollections.OrderedSet<PackageReference> = []

            let inputNodes: [GraphLoadingNode] = try root.packages.map { identity, package in
                inputIdentities.append(package.reference)

                let node = try GraphLoadingNode(
                    identity: identity,
                    manifest: package.manifest,
                    productFilter: .everything,
                    enabledTraits: workspace.enabledTraitsMap[package.reference.identity]
                )
                return node
            } + root.dependencies.compactMap { dependency in
                let package = dependency.packageRef
                inputIdentities.append(package)
                return try manifestsMap[dependency.identity].map { manifest in

                    return try GraphLoadingNode(
                        identity: dependency.identity,
                        manifest: manifest,
                        productFilter: dependency.productFilter,
                        enabledTraits: workspace.enabledTraitsMap[dependency.identity]
                    )
                }
            }

            // Begin with all packages having everything as an unused dependency.
            var unusedDepsPerPackage: [PackageIdentity: [PackageReference]] = manifestsMap
                .reduce(into: [PackageIdentity: [PackageReference]]()) { depsMap, manifestMap in
                    depsMap[manifestMap.key] = manifestsMap.compactMap { identity, manifest in
                        guard !root.manifests.contains(where: { identity == $0.key }) else { return nil }
                        let kind = manifest.packageKind
                        let ref = PackageReference(identity: identity, kind: kind)
                        return ref
                    }
                }

            let topLevelDependencies = root.packages.flatMap { $1.manifest.dependencies.map(\.packageRef) }

            var requiredIdentities: OrderedCollections.OrderedSet<PackageReference> = []
            _ = try transitiveClosure(inputNodes) { node in
                return try node.manifest.dependenciesRequired(for: node.productFilter, node.enabledTraits)
                    .compactMap { dependency in
                        let package = dependency.packageRef

                        // Check if traits are guarding the dependency from being enabled.
                        // Also check whether we've enabled pruning unused dependencies.
                        let isDepUsed = try node.manifest.isPackageDependencyUsed(
                            dependency,
                            enabledTraits: node.enabledTraits
                        )
                        if !isDepUsed && workspace.configuration.pruneDependencies {
                            if !node.enabledTraits.isEmpty {
                                observabilityScope.emit(debug: """
                            '\(package.identity)' from '\(package.locationString)' was omitted \
                            from required dependencies because it is being guarded by the following traits:' \
                            \(node.enabledTraits.joined(separator: ", "))
                            """)
                            } else {
                                observabilityScope.emit(debug: """
                            '\(package.identity)' from '\(package.locationString)' was omitted \
                            from required dependencies because it is unused
                            """)
                            }
                        } else {
                            unusedDepsPerPackage[node.identity, default: []] = unusedDepsPerPackage[
                                node.identity,
                                default: []
                            ].filter { $0.identity != dependency.identity }
                            let (inserted, index) = requiredIdentities.append(package)
                            if !inserted {
                                let existing = requiredIdentities.elements[index]
                                // if identity already tracked, compare the locations and used the preferred variant
                                if existing.canonicalLocation == package.canonicalLocation {
                                    // same literal location is fine
                                    if existing.locationString != package.locationString {
                                        // we prefer the top level dependencies
                                        if topLevelDependencies.contains(where: {
                                            $0.locationString == existing.locationString
                                        }) {
                                            observabilityScope.emit(debug: """
                                            similar variants of package '\(package.identity)' \
                                            found at '\(package.locationString)' and '\(existing.locationString)'. \
                                            using preferred root variant '\(existing.locationString)'
                                            """)
                                        } else {
                                            let preferred = [existing, package].sorted(by: {
                                                $0.locationString > $1.locationString
                                            }).first! // safe
                                            observabilityScope.emit(debug: """
                                            similar variants of package '\(package.identity)' \
                                            found at '\(package.locationString)' and '\(existing.locationString)'. \
                                            using preferred variant '\(preferred.locationString)'
                                            """)
                                            if preferred.locationString != existing.locationString {
                                                requiredIdentities.remove(existing)
                                                requiredIdentities.insert(preferred, at: index)
                                            }
                                        }
                                    }
                                } else {
                                    observabilityScope.emit(debug: """
                                    '\(package.identity)' from '\(package.locationString)' was omitted \
                                    from required dependencies because it has the same identity as the \
                                    one from '\(existing.locationString)'
                                    """)
                                }
                            }
                        }

                        // should calculate enabled traits here.
                        let explicitlyEnabledTraits = dependency.traits?.filter {
                            guard let condition = $0.condition else { return true }
                            return condition.isSatisfied(by: node.enabledTraits)
                        }.map(\.name)

                        return try manifestsMap[dependency.identity].map { manifest in
                            // Calculate all transitively enabled traits for this manifest.

                            var allEnabledTraits: Set<String> = ["default"]
                            if let explicitlyEnabledTraits
                            {
                                allEnabledTraits = Set(explicitlyEnabledTraits)
                            }

                            return try GraphLoadingNode(
                                identity: dependency.identity,
                                manifest: manifest,
                                productFilter: dependency.productFilter,
                                enabledTraits: allEnabledTraits
                            )
                        }
                    }
            }
            requiredIdentities = inputIdentities.union(requiredIdentities)

            // Calculate all unused identities:
            let unusedAcrossAllPackages = unusedDepsPerPackage.values.map { Set($0) }
                .reduce(Set(unusedDepsPerPackage.values.first ?? [])) { unused, deps in
                    unused.intersection(deps)
                }

            unusedIdentities = unusedIdentities.union(unusedAcrossAllPackages)

            if workspace.configuration.pruneDependencies {
                requiredIdentities = requiredIdentities.subtracting(unusedIdentities)
            }

            var availableIdentities: Set<PackageReference> = try Set(manifestsMap.map {
                // FIXME: adding this guard to ensure refactoring is correct 9/21
                // we only care about remoteSourceControl for this validation. it would otherwise trigger for
                // a dependency is put into edit mode, which we want to deprecate anyways
                if case .remoteSourceControl = $0.1.packageKind {
                    let effectiveURL = workspace.mirrors.effective(for: $0.1.packageLocation)
                    guard effectiveURL == $0.1.packageKind.locationString else {
                        throw InternalError(
                            "effective url for \($0.1.packageLocation) is \(effectiveURL), different from expected \($0.1.packageKind.locationString)"
                        )
                    }
                }
                return PackageReference(identity: $0.key, kind: $0.1.packageKind)
            })

            if workspace.configuration.pruneDependencies {
                availableIdentities = availableIdentities.subtracting(unusedIdentities)
            }

            // We should never have loaded a manifest we don't need.
            assert(
                availableIdentities.isSubset(of: requiredIdentities),
                "\(availableIdentities.map(\.identity)) | \(requiredIdentities.map(\.identity))"
            )
            // These are the missing package identities.
            let missingIdentities = requiredIdentities.subtracting(availableIdentities)

            return (requiredIdentities, missingIdentities, unusedIdentities)
        }

        /// Returns constraints of the dependencies, including edited package constraints.
        var dependencyConstraints: [PackageContainerConstraint] {
            get throws {
                try self._constraints.load()
            }
        }

        private static func computeConstraints(
            root: PackageGraphRoot,
            dependencies: [(
                manifest: Manifest,
                dependency: ManagedDependency,
                productFilter: ProductFilter,
                fileSystem: FileSystem
            )],
            workspace: Workspace
        ) throws -> [PackageContainerConstraint] {
            var allConstraints = [PackageContainerConstraint]()

            for (externalManifest, managedDependency, productFilter, _) in dependencies {
                // For edited packages, add a constraint with unversioned requirement so the
                // resolver doesn't try to resolve it.
                switch managedDependency.state {
                case .edited:
                    // FIXME: We shouldn't need to construct a new package reference object here.
                    // We should get the correct one from managed dependency object.
                    let ref = PackageReference.fileSystem(
                        identity: managedDependency.packageRef.identity,
                        path: workspace.path(to: managedDependency)
                    )
                    let constraint = PackageContainerConstraint(
                        package: ref,
                        requirement: .unversioned,
                        products: productFilter
                    )
                    allConstraints.append(constraint)
                case .sourceControlCheckout, .registryDownload, .fileSystem, .custom:
                    break
                }
                allConstraints += try externalManifest.dependencyConstraints(
                    productFilter: productFilter,
                    workspace.enabledTraitsMap[managedDependency.packageRef.identity]
                )
            }
            return allConstraints
        }

        // FIXME: @testable(internal)
        /// Returns a list of constraints for all 'edited' package.
        public var editedPackagesConstraints: [PackageContainerConstraint] {
            var constraints = [PackageContainerConstraint]()

            for (_, managedDependency, productFilter, _) in dependencies {
                switch managedDependency.state {
                case .sourceControlCheckout, .registryDownload, .fileSystem, .custom: continue
                case .edited: break
                }
                // FIXME: We shouldn't need to construct a new package reference object here.
                // We should get the correct one from managed dependency object.
                let ref = PackageReference.fileSystem(
                    identity: managedDependency.packageRef.identity,
                    path: workspace.path(to: managedDependency)
                )
                let constraint = PackageContainerConstraint(
                    package: ref,
                    requirement: .unversioned,
                    products: productFilter
                )
                constraints.append(constraint)
            }
            return constraints
        }
    }

    /// Returns the location of the dependency.
    ///
    /// Source control dependencies will return the subpath inside `checkoutsPath` and
    /// Registry dependencies will return the subpath inside `registryDownloadsPath` and
    /// edited dependencies will either return a subpath inside `editablesPath` or
    /// a custom path.
    public func path(to dependency: Workspace.ManagedDependency) -> AbsolutePath {
        switch dependency.state {
        case .sourceControlCheckout:
            self.location.repositoriesCheckoutSubdirectory(for: dependency)
        case .registryDownload:
            self.location.registryDownloadSubdirectory(for: dependency)
        case .edited(_, let path):
            path ?? self.location.editSubdirectory(for: dependency)
        case .fileSystem(let path):
            path
        case .custom(_, let path):
            path
        }
    }

    /// Returns manifest interpreter flags for a package.
    public func interpreterFlags(for manifestPath: AbsolutePath) throws -> [String] {
        guard let manifestLoader = self.manifestLoader as? ManifestLoader else {
            throw StringError("unexpected manifest loader kind")
        }

        let manifestToolsVersion = (try? ToolsVersionParser.parse(
            manifestPath: manifestPath,
            fileSystem: self.fileSystem
        )) ?? self.currentToolsVersion

        guard self.currentToolsVersion >= manifestToolsVersion || SwiftVersion.current.isDevelopment,
              manifestToolsVersion >= ToolsVersion.minimumRequired
        else {
            throw StringError("invalid tools version")
        }
        return manifestLoader.interpreterFlags(for: manifestToolsVersion)
    }

    /// Load the manifests for the current dependency tree.
    ///
    /// This will load the manifests for the root package as well as all the
    /// current dependencies from the working checkouts.
    public func loadDependencyManifests(
        root: PackageGraphRoot,
        automaticallyAddManagedDependencies: Bool = false,
        observabilityScope: ObservabilityScope
    ) async throws -> DependencyManifests {
        let prepopulateManagedDependencies: ([PackageReference]) async throws -> Void = { refs in
            // pre-populate managed dependencies if we are asked to do so (this happens when resolving to a resolved
            // file)
            if automaticallyAddManagedDependencies {
                for ref in refs {
                    // Since we are creating managed dependencies based on the resolved file in this mode, but local
                    // packages aren't part of that file, they will be missing from it. So we're eagerly adding them
                    // here, but explicitly don't add any that are overridden by a root with the same identity since
                    // that would lead to loading the given package twice, once as a root and once as a dependency
                    // which violates various assumptions.
                    if case .fileSystem = ref.kind, !root.manifests.keys.contains(ref.identity) {
                        try await self.state.add(dependency: .fileSystem(packageRef: ref))
                    }
                }
                await observabilityScope.trap { try await self.state.save() }
            }
        }

        // Make a copy of dependencies as we might mutate them in the for loop.
        let dependenciesToCheck = await Array(self.state.dependencies)
        // Remove any managed dependency which has become a root.
        for dependency in dependenciesToCheck {
            if root.packages.keys.contains(dependency.packageRef.identity) {
                await observabilityScope.makeChildScope(
                    description: "removing managed dependencies",
                    metadata: dependency.packageRef.diagnosticsMetadata
                ).trap {
                    try await self.remove(package: dependency.packageRef)
                }
            }
        }

        // Validates that all the managed dependencies are still present in the file system.
        await self.fixManagedDependencies(
            observabilityScope: observabilityScope
        )
        guard !observabilityScope.errorsReported else {
            // return partial results
            return DependencyManifests(
                root: root,
                dependencies: [],
                workspace: self,
                observabilityScope: observabilityScope
            )
        }

        // Load root dependencies manifests (in parallel)
        let rootDependencies = root.dependencies.map(\.packageRef)
        try await prepopulateManagedDependencies(rootDependencies)
        let rootDependenciesManifests = await self.loadManagedManifests(
            for: rootDependencies,
            observabilityScope: observabilityScope
        )

        let rootManifests = try root.manifests.mapValues { manifest in
            let parentEnabledTraits = self.enabledTraitsMap[manifest.packageIdentity]
            let deps = try manifest.dependencies.filter { dep in
                let explicitlyEnabledTraits = dep.traits?.filter({
                    guard let condition = $0.condition else { return true }
                    return condition.isSatisfied(by: parentEnabledTraits)
                }).map(\.name)

                let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) })
                let enabledTraits = enabledTraitsSet?.union(self.enabledTraitsMap[dep.identity]) ?? self.enabledTraitsMap[dep.identity]

                self.enabledTraitsMap[dep.identity] = enabledTraits

                let isDepUsed = try manifest.isPackageDependencyUsed(dep, enabledTraits: parentEnabledTraits)
                return isDepUsed
            }

            return Manifest(
                displayName: manifest.displayName,
                packageIdentity: manifest.packageIdentity,
                path: manifest.path,
                packageKind: manifest.packageKind,
                packageLocation: manifest.packageLocation,
                defaultLocalization: manifest.defaultLocalization,
                platforms: manifest.platforms,
                version: manifest.version,
                revision: manifest.revision,
                toolsVersion: manifest.toolsVersion,
                pkgConfig: manifest.pkgConfig,
                providers: manifest.providers,
                cLanguageStandard: manifest.cLanguageStandard,
                cxxLanguageStandard: manifest.cxxLanguageStandard,
                swiftLanguageVersions: manifest.swiftLanguageVersions,
                dependencies: deps,
                products: manifest.products,
                targets: manifest.targets,
                traits: manifest.traits,
                pruneDependencies: manifest.pruneDependencies
            )
        }

        let topLevelManifests = rootManifests.merging(rootDependenciesManifests, uniquingKeysWith: { lhs, _ in
            lhs // prefer roots!
        })

        // optimization: preload first level dependencies manifest (in parallel)
        let firstLevelDependencies = try topLevelManifests.values.map { manifest in
            let parentEnabledTraits = self.enabledTraitsMap[manifest.packageIdentity]
            return try manifest.dependencies.filter { dep in
                let explicitlyEnabledTraits = dep.traits?.filter({
                    guard let condition = $0.condition else { return true }
                    return condition.isSatisfied(by: parentEnabledTraits)
                }).map(\.name)

                let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) })
                let enabledTraits = enabledTraitsSet?.union(self.enabledTraitsMap[dep.identity]) ?? self.enabledTraitsMap[dep.identity]

                self.enabledTraitsMap[dep.identity] = enabledTraits

                let isDepUsed = try manifest.isPackageDependencyUsed(dep, enabledTraits: parentEnabledTraits)
                return isDepUsed

            }.map(\.packageRef)
        }.flatMap(\.self)

        let firstLevelManifests = await self.loadManagedManifests(
            for: firstLevelDependencies,
            observabilityScope: observabilityScope
        )

        // Continue to load the rest of the manifest for this graph
        // Creates a map of loaded manifests. We do this to avoid reloading the shared nodes.
        var loadedManifests = firstLevelManifests
        let successorNodes: (KeyedPair<GraphLoadingNode, PackageIdentity>) async throws -> [KeyedPair<
            GraphLoadingNode,
            PackageIdentity
        >] = { node in
            // optimization: preload manifest we know about in parallel
            // avoid loading dependencies that are trait-guarded here since this is redundant.
            let dependenciesRequired = try node.item.manifest.dependenciesRequired(
                for: node.item.productFilter,
                node.item.enabledTraits
            )
            let dependenciesToLoad = dependenciesRequired.map(\.packageRef)
                .filter { !loadedManifests.keys.contains($0.identity) }
            try await prepopulateManagedDependencies(dependenciesToLoad)
            let dependenciesManifests = await self.loadManagedManifests(
                for: dependenciesToLoad,
                observabilityScope: observabilityScope
            )
            dependenciesManifests.forEach { loadedManifests[$0.key] = $0.value }
            return try dependenciesRequired.compactMap { dependency in
                return try loadedManifests[dependency.identity].flatMap { manifest in

                    let explicitlyEnabledTraits = dependency.traits?.filter {
                        guard let condition = $0.condition else { return true }
                        return condition.isSatisfied(by: node.item.enabledTraits)
                    }.map(\.name)

                    var enabledTraitsSet = explicitlyEnabledTraits.flatMap { Set($0) }
                    let precomputedTraits = self.enabledTraitsMap[dependency.identity]
                    // Shouldn't union here if enabledTraitsMap returns "default" and we DO have explicitly enabled traits, since we're meant to flatten the default traits.
                    if precomputedTraits == ["default"],
                       let enabledTraitsSet {
                        self.enabledTraitsMap[dependency.identity] = enabledTraitsSet
                    } else {
                        // Unify traits
                        enabledTraitsSet?.formUnion(precomputedTraits)
                        if let enabledTraitsSet {
                            self.enabledTraitsMap[dependency.identity] = enabledTraitsSet
                        }
                    }

                    let calculatedTraits = try manifest.enabledTraits(
                        using: self.enabledTraitsMap[dependency.identity],
                        .init(node.item.manifest)
                    )

                    self.enabledTraitsMap[dependency.identity] = calculatedTraits

                    // we also compare the location as this function may attempt to load
                    // dependencies that have the same identity but from a different location
                    // which is an error case we diagnose an report about in the GraphLoading part which
                    // is prepared to handle the case where not all manifest are available
                    return manifest.canonicalPackageLocation == dependency.packageRef.canonicalLocation ?
                        try KeyedPair(
                            GraphLoadingNode(
                                identity: dependency.identity,
                                manifest: manifest,
                                productFilter: dependency.productFilter,
                                enabledTraits: calculatedTraits
                            ),
                            key: dependency.identity
                        ) :
                        nil
                }
            }
        }

        var allNodes = OrderedDictionary<PackageIdentity, GraphLoadingNode>()

        do {
            let manifestGraphRoots = try topLevelManifests.map { identity, manifest in
                return try KeyedPair(
                    GraphLoadingNode(
                        identity: identity,
                        manifest: manifest,
                        productFilter: .everything,
                        enabledTraits: self.enabledTraitsMap[identity]
                    ),
                    key: identity
                )
            }

            try await depthFirstSearch(
                manifestGraphRoots,
                successors: successorNodes
            ) {
                allNodes[$0.key] = $0.item
            } onDuplicate: { _, _ in
                // Nothing we need to compute here.
            }
        }

        // Update enabled traits map
        self.enabledTraitsMap = .init(try precomputeTraits( topLevelManifests.values.map({ $0 }), loadedManifests))

        let dependencyManifests = allNodes.filter { !$0.value.manifest.packageKind.isRoot }

        // TODO: this check should go away when introducing explicit overrides
        // check for overrides attempts with same name but different path
        let rootManifestsByName = Array(root.manifests.values).spm_createDictionary { ($0.displayName, $0) }
        for (_, node) in dependencyManifests {
            if let override = rootManifestsByName[node.manifest.displayName],
               override.packageLocation != node.manifest.packageLocation
            {
                observabilityScope
                    .emit(
                        error: "unable to override package '\(node.manifest.displayName)' because its identity '\(PackageIdentity(urlString: node.manifest.packageLocation))' doesn't match override's identity (directory name) '\(PackageIdentity(urlString: override.packageLocation))'"
                    )
            }
        }

        var dependencies: [(Manifest, ManagedDependency, ProductFilter, FileSystem)] = []
        for (identity, node) in dependencyManifests {
            guard let dependency = await self.state.dependencies[identity] else {
                throw InternalError("dependency not found for \(identity) at \(node.manifest.packageLocation)")
            }

            let packageRef = PackageReference(identity: identity, kind: node.manifest.packageKind)
            let fileSystem = try await self.getFileSystem(
                package: packageRef,
                state: dependency.state,
                observabilityScope: observabilityScope
            )
            dependencies.append((node.manifest, dependency, node.productFilter, fileSystem ?? self.fileSystem))
        }

        return DependencyManifests(
            root: root,
            dependencies: dependencies,
            workspace: self,
            observabilityScope: observabilityScope
        )
    }

    public func precomputeTraits(
        _ topLevelManifests: [Manifest],
        _ manifestMap: [PackageIdentity: Manifest]
    ) throws -> [PackageIdentity: Set<String>] {
        var visited: Set<PackageIdentity> = []

        func dependencies(of parent: Manifest, _ productFilter: ProductFilter = .everything) throws {
            let parentTraits = self.enabledTraitsMap[parent.packageIdentity]
            let requiredDependencies = try parent.dependenciesRequired(for: productFilter, parentTraits)
            let guardedDependencies = parent.dependenciesTraitGuarded(withEnabledTraits: parentTraits)

            _ = try (requiredDependencies + guardedDependencies).compactMap({ dependency in
                return try manifestMap[dependency.identity].flatMap({ manifest in

                    let explicitlyEnabledTraits = dependency.traits?.filter {
                        guard let condition = $0.condition else { return true }
                        return condition.isSatisfied(by: parentTraits)
                    }.map(\.name)

                    var enabledTraitsSet = explicitlyEnabledTraits.flatMap { Set($0) }
                    let precomputedTraits = self.enabledTraitsMap[dependency.identity]
                    // Shouldn't union here if enabledTraitsMap returns "default" and we DO have explicitly enabled traits, since we're meant to flatten the default traits.
                    if precomputedTraits == ["default"],
                       let enabledTraitsSet {
                        self.enabledTraitsMap[dependency.identity] = enabledTraitsSet
                    } else {
                        // Unify traits
                        enabledTraitsSet?.formUnion(precomputedTraits)
                        if let enabledTraitsSet {
                            self.enabledTraitsMap[dependency.identity] = enabledTraitsSet
                        }
                    }

                    let calculatedTraits = try manifest.enabledTraits(
                        using: self.enabledTraitsMap[dependency.identity],
                        .init(parent)
                    )

                    self.enabledTraitsMap[dependency.identity] = calculatedTraits
                    let result = visited.insert(dependency.identity)
                    if result.inserted {
                        try dependencies(of: manifest, dependency.productFilter)
                    }

                    return manifest
                })
            })
        }

        for manifest in topLevelManifests {
            // Track already-visited manifests to avoid cycles
            let result = visited.insert(manifest.packageIdentity)
            if result.inserted {
                try dependencies(of: manifest)
            }
        }

        return self.enabledTraitsMap.dictionaryLiteral
    }

    /// Loads the given manifests, if it is present in the managed dependencies.
    ///

    private func loadManagedManifests(
        for packages: [PackageReference],
        observabilityScope: ObservabilityScope
    ) async -> [PackageIdentity: Manifest] {
        await withTaskGroup(of: (PackageIdentity, Manifest?).self) { group in
            for package in Set(packages) {
                group.addTask {
                    await (
                        package.identity,
                        self.loadManagedManifest(for: package, observabilityScope: observabilityScope)
                    )
                }
            }
            return await group.compactMap {
                $0 as? (PackageIdentity, Manifest)
            }.reduce(into: [PackageIdentity: Manifest]()) { partialResult, loadedManifest in
                partialResult[loadedManifest.0] = loadedManifest.1
            }
        }
    }

    /// Loads the given manifest, if it is present in the managed dependencies.
    private func loadManagedManifest(
        for package: PackageReference,
        observabilityScope: ObservabilityScope
    ) async -> Manifest? {
        // Check if this dependency is available.
        // we also compare the location as this function may attempt to load
        // dependencies that have the same identity but from a different location
        // which is an error case we diagnose an report about in the GraphLoading part which
        // is prepared to handle the case where not all manifest are available
        guard let managedDependency = await self.state.dependencies[comparingLocation: package] else {
            return nil
        }

        // Get the path of the package.
        let packagePath = self.path(to: managedDependency)

        // The kind and version, if known.
        let packageKind: PackageReference.Kind
        let packageVersion: Version?
        switch managedDependency.state {
        case .sourceControlCheckout(let checkoutState):
            packageKind = managedDependency.packageRef.kind
            switch checkoutState {
            case .version(let checkoutVersion, _):
                packageVersion = checkoutVersion
            default:
                packageVersion = .none
            }
        case .registryDownload(let downloadedVersion):
            packageKind = managedDependency.packageRef.kind
            packageVersion = downloadedVersion
        case .custom(let availableVersion, _):
            packageKind = managedDependency.packageRef.kind
            packageVersion = availableVersion
        case .edited, .fileSystem:
            packageKind = .fileSystem(packagePath)
            packageVersion = .none
        }

        let fileSystem: FileSystem?
        do {
            fileSystem = try await self.getFileSystem(
                package: package,
                state: managedDependency.state,
                observabilityScope: observabilityScope
            )
        } catch {
            // only warn here in case of issues since we should not even get here without a valid package container
            observabilityScope.emit(
                warning: "unexpected failure while accessing custom package container",
                underlyingError: error
            )
            fileSystem = nil
        }

        // Load and return the manifest.
        return try? await self.loadManifest(
            packageIdentity: managedDependency.packageRef.identity,
            packageKind: packageKind,
            packagePath: packagePath,
            packageLocation: managedDependency.packageRef.locationString,
            packageVersion: packageVersion,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }

    /// Load the manifest at a given path.
    ///
    /// This is just a helper wrapper to the manifest loader.
    func loadManifest(
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packagePath: AbsolutePath,
        packageLocation: String,
        packageVersion: Version? = nil,
        fileSystem: FileSystem? = nil,
        observabilityScope: ObservabilityScope
    ) async throws -> Manifest {
        let fileSystem = fileSystem ?? self.fileSystem

        // Load the manifest, bracketed by the calls to the delegate callbacks.
        delegate?.willLoadManifest(
            packageIdentity: packageIdentity,
            packagePath: packagePath,
            url: packageLocation,
            version: packageVersion,
            packageKind: packageKind
        )

        let manifestLoadingScope = observabilityScope.makeChildScope(description: "Loading manifest") {
            .packageMetadata(identity: packageIdentity, kind: packageKind)
        }

        var manifestLoadingDiagnostics = [Diagnostic]()
        defer { manifestLoadingScope.emit(manifestLoadingDiagnostics) }

        let start = DispatchTime.now()
        let manifest: Manifest
        do {
            manifest = try await self.manifestLoader.load(
                packagePath: packagePath,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                packageVersion: packageVersion.map { (version: $0, revision: nil) },
                currentToolsVersion: self.currentToolsVersion,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                fileSystem: fileSystem,
                observabilityScope: manifestLoadingScope,
                delegateQueue: .sharedConcurrent
            )
        } catch {
            let duration = start.distance(to: .now())
            manifestLoadingDiagnostics.append(.error(error))
            self.delegate?.didLoadManifest(
                packageIdentity: packageIdentity,
                packagePath: packagePath,
                url: packageLocation,
                version: packageVersion,
                packageKind: packageKind,
                manifest: nil,
                diagnostics: manifestLoadingDiagnostics,
                duration: duration
            )
            throw error
        }

        let duration = start.distance(to: .now())
        let validator = ManifestValidator(
            manifest: manifest,
            sourceControlValidator: self.repositoryManager,
            fileSystem: self.fileSystem
        )
        let validationIssues = validator.validate()
        if !validationIssues.isEmpty {
            // Diagnostics.fatalError indicates that a more specific diagnostic has already been added.
            manifestLoadingDiagnostics.append(contentsOf: validationIssues)
            throw Diagnostics.fatalError
        }
        self.delegate?.didLoadManifest(
            packageIdentity: packageIdentity,
            packagePath: packagePath,
            url: packageLocation,
            version: packageVersion,
            packageKind: packageKind,
            manifest: manifest,
            diagnostics: manifestLoadingDiagnostics,
            duration: duration
        )
        return manifest
    }

    /// Validates that all the edited dependencies are still present in the file system.
    /// If some checkout dependency is removed form the file system, clone it again.
    /// If some edited dependency is removed from the file system, mark it as unedited and
    /// fallback on the original checkout.
    private func fixManagedDependencies(
        observabilityScope: ObservabilityScope
    ) async {
        // Reset managed dependencies if the state file was removed during the lifetime of the Workspace object.
        if await !self.state.dependencies.isEmpty, await !self.state.stateFileExists() {
            try? await self.state.reset()
        }

        // Make a copy of dependencies as we might mutate them in the for loop.
        let allDependencies = await Array(self.state.dependencies)
        for dependency in allDependencies {
            await observabilityScope.makeChildScope(
                description: "copying managed dependencies",
                metadata: dependency.packageRef.diagnosticsMetadata
            ).trap {
                // If the dependency is present, we're done.
                let dependencyPath = self.path(to: dependency)
                if fileSystem.isDirectory(dependencyPath) {
                    return
                }

                switch dependency.state {
                case .sourceControlCheckout(let checkoutState):
                    // If some checkout dependency has been removed, retrieve it again.
                    _ = try await self.checkoutRepository(
                        package: dependency.packageRef,
                        at: checkoutState,
                        observabilityScope: observabilityScope
                    )
                    observabilityScope
                        .emit(.checkedOutDependencyMissing(packageName: dependency.packageRef.identity.description))

                case .registryDownload(let version):
                    // If some downloaded dependency has been removed, retrieve it again.
                    _ = try await self.downloadRegistryArchive(
                        package: dependency.packageRef,
                        at: version,
                        observabilityScope: observabilityScope
                    )
                    observabilityScope
                        .emit(.registryDependencyMissing(packageName: dependency.packageRef.identity.description))

                case .custom(let version, let path):
                    let container = try await self.packageContainerProvider.getContainer(
                        for: dependency.packageRef,
                        updateStrategy: .never,
                        observabilityScope: observabilityScope
                    )
                    if let customContainer = container as? CustomPackageContainer {
                        let newPath = try customContainer.retrieve(at: version, observabilityScope: observabilityScope)
                        observabilityScope
                            .emit(.customDependencyMissing(packageName: dependency.packageRef.identity.description))

                        // FIXME: We should be able to handle this case and also allow changed paths for registry and SCM downloads.
                        if newPath != path {
                            observabilityScope
                                .emit(error: "custom dependency was retrieved at a different path: \(newPath)")
                        }
                    } else {
                        observabilityScope.emit(error: "invalid custom dependency container: \(container)")
                    }

                case .edited:
                    // If some edited dependency has been removed, mark it as unedited.
                    //
                    // Note: We don't resolve the dependencies when unediting
                    // here because we expect this method to be called as part
                    // of some other resolve operation (i.e. resolve, update, etc).
                    try await self.unedit(
                        dependency: dependency,
                        forceRemove: true,
                        observabilityScope: observabilityScope
                    )

                    observabilityScope
                        .emit(.editedDependencyMissing(packageName: dependency.packageRef.identity.description))

                case .fileSystem:
                    await self.state.remove(identity: dependency.packageRef.identity)
                    try await self.state.save()
                }
            }
        }
    }

    private func getFileSystem(
        package: PackageReference,
        state: Workspace.ManagedDependency.State,
        observabilityScope: ObservabilityScope
    ) async throws -> FileSystem? {
        // Only custom containers may provide a file system.
        guard self.customPackageContainerProvider != nil else {
            return nil
        }

        switch state {
        // File-system based dependencies do not provide a custom file system object.
        case .fileSystem:
            return nil
        case .custom:
            let container = try await withCheckedThrowingContinuation { continuation in
                self.packageContainerProvider.getContainer(
                    for: package,
                    updateStrategy: .never,
                    observabilityScope: observabilityScope,
                    on: .sharedConcurrent,
                    completion: {
                        continuation.resume(with: $0)
                    }
                )
            }
            guard let customContainer = container as? CustomPackageContainer else {
                observabilityScope.emit(error: "invalid custom dependency container: \(container)")
                return nil
            }
            return try customContainer.getFileSystem()
        default:
            observabilityScope.emit(error: "invalid managed dependency state for custom dependency: \(state)")
            return nil
        }
    }
}
