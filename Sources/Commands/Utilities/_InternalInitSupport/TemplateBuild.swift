//
//  TemplateBuild.swift
//  SwiftPM
//
//  Created by John Bute on 2025-06-11.
//


import CoreCommands
import Basics
import TSCBasic
import ArgumentParser
import TSCUtility
import SPMBuildCore

struct TemplateBuildSupport {
    static func build(swiftCommandState: SwiftCommandState, buildOptions: BuildCommandOptions, globalOptions: GlobalOptions, cwd: Basics.AbsolutePath) async throws {
        let buildSystem = try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { _, _ in
            try await swiftCommandState.createBuildSystem(
                explicitProduct: buildOptions.product,
                traitConfiguration: .init(traitOptions: buildOptions.traits),
                shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                productsBuildParameters: swiftCommandState.productsBuildParameters,
                toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                outputStream: TSCBasic.stdoutStream
            )
        }

        guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
            throw ExitCode.failure
        }

        try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { _, _ in
            do {
                try await buildSystem.build(subset: subset)
            } catch _ as Diagnostics {
                throw ExitCode.failure
            }
        }

    }
}
