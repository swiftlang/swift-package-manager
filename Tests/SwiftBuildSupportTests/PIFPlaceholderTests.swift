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
import SwiftBuild
@testable import SwiftBuildSupport
import Testing

@Suite(
    .tags(
        .TestSize.small,
        .FunctionalArea.PIF
    )
)
struct PIFPlaceholderTests {

    @Test("Placeholder PIF describes the project it was asked for")
    func placeholderProjectMirrorsItsArguments() {
        let (project, _) = PackagePIFBuilder.buildPlaceholderPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example",
            targetBuildSettings: ProjectModel.BuildSettings(),
            developmentRegion: "en"
        )

        #expect(project.id.value == "PACKAGE:example")
        #expect(project.path == "/tmp/Example/Package.swift")
        #expect(project.projectDir == "/tmp/Example")
        #expect(project.name == "Example")
        #expect(project.developmentRegion == "en")
        #expect(project.buildConfigs.map(\.name) == ["Debug", "Release"])
    }

    @Test("Placeholder PIF has a single aggregate target, unlike an empty PIF")
    func placeholderHasExactlyOneAggregateTarget() throws {
        let (project, placeholderModule) = PackagePIFBuilder.buildPlaceholderPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example",
            targetBuildSettings: ProjectModel.BuildSettings()
        )

        // The single aggregate target is what distinguishes a *placeholder* PIF from an *empty* one.
        let aggregateTarget = try #require(project.targets.only)
        guard case .aggregate = aggregateTarget else {
            Issue.record("expected the placeholder target to be an aggregate target")
            return
        }
        #expect(aggregateTarget.id.value == "PACKAGE-PLACEHOLDER:PACKAGE:example")
        #expect(aggregateTarget.common.buildConfigs.map(\.name) == ["Debug", "Release"])

        // An empty PIF, in contrast, has no targets at all.
        let emptyProject = PackagePIFBuilder.buildEmptyPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example"
        )
        #expect(emptyProject.targets.count == 0)

        // The returned module describes that same placeholder target.
        #expect(placeholderModule.type == .placeholder)
        #expect(placeholderModule.name == "Example")
        #expect(placeholderModule.moduleName == "Example")
        #expect(placeholderModule.pifTarget?.id == aggregateTarget.id)
    }

    @Test("Placeholder PIF applies the given build settings to the target, not to the project")
    func placeholderAppliesTargetBuildSettings() throws {
        var targetBuildSettings = ProjectModel.BuildSettings()
        targetBuildSettings[.SDKROOT] = "auto"

        let (project, _) = PackagePIFBuilder.buildPlaceholderPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example",
            targetBuildSettings: targetBuildSettings
        )

        let aggregateTarget = try #require(project.targets.only)
        for targetBuildConfig in aggregateTarget.common.buildConfigs {
            #expect(targetBuildConfig.settings == targetBuildSettings)
        }

        // The project-level configurations stay empty.
        for projectBuildConfig in project.buildConfigs {
            #expect(projectBuildConfig.settings == ProjectModel.BuildSettings())
        }
    }

    @Test("Placeholder PIF omits the development region unless one is given")
    func placeholderDevelopmentRegionIsOptional() {
        let (project, _) = PackagePIFBuilder.buildPlaceholderPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example",
            targetBuildSettings: ProjectModel.BuildSettings()
        )
        #expect(project.developmentRegion == nil)
    }

    /// Checks that a placeholder PIF is well-formed enough that *Swift Build can consume it*:
    /// signing and serialization are the steps SwiftPM performs before handing a PIF off, so
    /// they are what would reject a placeholder project that cannot be represented in the PIF.
    ///
    /// Note that this stops short of running an actual build over the placeholder PIF.
    @Test("Placeholder PIF can be signed and serialized without errors")
    func placeholderPIFCanBeSignedAndSerialized() throws {
        let (project, _) = PackagePIFBuilder.buildPlaceholderPIF(
            id: "PACKAGE:example",
            path: "/tmp/Example/Package.swift",
            projectDir: "/tmp/Example",
            name: "Example",
            targetBuildSettings: ProjectModel.BuildSettings()
        )

        let workspacePath = try AbsolutePath(validating: "/tmp/Example")
        let workspace = PIF.Workspace(
            id: "WORKSPACE:example",
            name: "Example",
            path: workspacePath,
            projects: [project]
        )

        // Signing encodes the project and each of its targets in turn, so it is the step that
        // would surface a placeholder project that cannot be represented in the PIF.
        try PIF.sign(workspace: workspace)

        // A project serializes its targets *by signature*, so the placeholder target is only
        // representable once signing has given it one.
        let signedProject = try #require(workspace.projects.only)
        let placeholderTarget = try #require(signedProject.underlying.targets.only)
        #expect(placeholderTarget.common.signature != nil)

        // The whole workspace then encodes without throwing.
        let encodedWorkspace = try JSONEncoder.makeWithDefaults().encode(workspace)
        #expect(!encodedWorkspace.isEmpty)
    }
}
