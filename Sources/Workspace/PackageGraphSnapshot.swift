/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import Foundation
import PackageGraph

final public class PackageGraphSnapshotTool {

    let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public func createGraphSnapshot(
        root: PackageGraphRootInput,
        diagnostics: DiagnosticsEngine
    ) throws {
        let rootManifests = workspace.loadRootManifests(packages: root.packages, diagnostics: diagnostics) 
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests)

        try PackageGraphSnapshotBuilder(containerProvider: workspace.containerProvider)
            .build(inputConstraints: graphRoot.constraints)
    }
}

// MARK: - Models

extension String: PackageContainerIdentifier { }

final class PackageContainerSnapshot: Codable {
    let identifier: PackageReference
    let depsByVersion: [String: [RepositoryPackageConstraint]]

    init(identifier: PackageReference, depsByVersion: [String: [RepositoryPackageConstraint]]) {
        self.identifier = identifier
        self.depsByVersion = depsByVersion
    }
}

struct PackageGraphSnapshot: Codable {
    public let constraints: [RepositoryPackageConstraint]
    public let containers: [PackageContainerSnapshot]
}

// MARK: - Builders

final class PackageContainerSnapshotBuilder {
    let identifier: PackageReference
    var depsByVersion: [String: [RepositoryPackageConstraint]]

    init(identifier: PackageReference) {
        self.identifier = identifier
        self.depsByVersion = [:]
    }

    func add(constraints: [RepositoryPackageConstraint], forKey key: String) {
        depsByVersion[key] = constraints
    }

    func build() -> PackageContainerSnapshot {
        return PackageContainerSnapshot(identifier: identifier, depsByVersion: depsByVersion)
    }
}

private final class PackageGraphSnapshotBuilder {
    let containerProvider: RepositoryPackageContainerProvider

    private let operationQueue = OperationQueue()
    private let queue = DispatchQueue(label: "org.swift.swiftpm.something-2")
    private var packageContainerBuilders: [PackageReference: PackageContainerSnapshotBuilder] = [:]
    private let progressBar: LaneBasedProgressBarProtocol

    init(containerProvider: RepositoryPackageContainerProvider) {
        self.containerProvider = containerProvider
        operationQueue.name = "org.swift.swiftpm.something"

        let lanes = ProcessInfo.processInfo.activeProcessorCount
        progressBar = createLaneBasedProgressBar(forStream: stdoutStream, numLanes: lanes)
        operationQueue.maxConcurrentOperationCount = lanes
    }

    func build(constraint: RepositoryPackageConstraint) {
        let identifier = constraint.identifier

        // We only care about the first constraint that we encounter.
        let builder: PackageContainerSnapshotBuilder? = queue.sync(execute: {
            if !self.packageContainerBuilders.keys.contains(identifier) {
                let containerBuilder = PackageContainerSnapshotBuilder(identifier: identifier)
                packageContainerBuilders[identifier] = containerBuilder
                return containerBuilder
            }
            return nil
        })

        guard let containerBuilder = builder else { return }

        let theContainer = try? await { containerProvider.getContainer(for: identifier, skipUpdate: true, completion: $0) }
        guard let container = theContainer else {
            return
        }

        let progressBarLane = progressBar.createLane(name: "Processing \(identifier.path)")

        switch constraint.requirement {
        case .versionSet(let versionSet):
            let validVersions = container.versions(filter: versionSet.contains)

            for version in validVersions {
                progressBarLane.update(text: version.description)

                if let dependencies = try? container.getDependencies(at: version) {
                    containerBuilder.add(constraints: dependencies, forKey: version.description)
                    enqueue(constraints: dependencies)
                }
            }

        case .revision(let revision):
            progressBarLane.update(text: revision)

            if let dependencies = try? container.getDependencies(at: revision) {
                containerBuilder.add(constraints: dependencies, forKey: revision)
                enqueue(constraints: dependencies)
            }

        case .unversioned:
            progressBarLane.update(text: "Unversioned")

            if let dependencies = try? container.getUnversionedDependencies() {
                containerBuilder.add(constraints: dependencies, forKey: "___spm_unversioned")
                enqueue(constraints: dependencies)
            }
        }

        progressBarLane.complete()
    }

    func enqueue(constraints: [RepositoryPackageConstraint]) {
        for constraint in constraints {
            operationQueue.addOperation({
                self.build(constraint: constraint)
            })
        }
    }

    func build(inputConstraints: [RepositoryPackageConstraint]) throws {
        // Enqueue the input constraints.
        enqueue(constraints: inputConstraints)

        // Wait for all operations to finish.
        operationQueue.waitUntilAllOperationsAreFinished()
        progressBar.complete(text: "Done!")

        // Build all the containers.
        let snapshot = PackageGraphSnapshot(
            constraints: inputConstraints,
            containers: packageContainerBuilders.values.map({ $0.build() })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let d = try encoder.encode(snapshot)
        print(String(data: d, encoding: .utf8)!)
    }
}
