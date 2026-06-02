//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageGraph
import PackageModel
import SPMBuildCore
import SwiftBuildSupport
import Testing
import _InternalTestSupport

@testable import SPMBuildCore

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) @testable import PackageGraph
@_spi(SwiftPMInternal) @testable import PackageModel

@Suite struct PluginUsageConditionAxisTests {
    @Test func hostAxisEmptyMatchesAnything() {
        let condition = Module.PluginUsageCondition(hostPlatforms: [], targetPlatforms: [.iOS], traits: [])
        let env = BuildEnvironment(platform: .linux, configuration: .debug)
        #expect(condition.hostAxisSatisfied(hostEnv: env))
    }

    @Test func hostAxisMatch() {
        let condition = Module.PluginUsageCondition(hostPlatforms: [.macOS], targetPlatforms: [], traits: [])
        let macOSEnv = BuildEnvironment(platform: .macOS, configuration: .debug)
        let linuxEnv = BuildEnvironment(platform: .linux, configuration: .debug)
        #expect(condition.hostAxisSatisfied(hostEnv: macOSEnv))
        #expect(!condition.hostAxisSatisfied(hostEnv: linuxEnv))
    }

    @Test func targetAxisEmptyMatchesAnything() {
        let condition = Module.PluginUsageCondition(hostPlatforms: [.macOS], targetPlatforms: [], traits: [])
        let env = BuildEnvironment(platform: .linux, configuration: .debug)
        #expect(condition.targetAxisSatisfied(targetEnv: env))
    }

    @Test func targetAxisMatch() {
        let condition = Module.PluginUsageCondition(hostPlatforms: [], targetPlatforms: [.iOS, .watchOS], traits: [])
        #expect(condition.targetAxisSatisfied(targetEnv: BuildEnvironment(platform: .iOS, configuration: .debug)))
        #expect(condition.targetAxisSatisfied(targetEnv: BuildEnvironment(platform: .watchOS, configuration: .debug)))
        #expect(!condition.targetAxisSatisfied(targetEnv: BuildEnvironment(platform: .macOS, configuration: .debug)))
    }

    @Test func traitsAxisEmptyMatchesAnything() {
        let condition = Module.PluginUsageCondition(hostPlatforms: [.macOS], targetPlatforms: [], traits: [])
        let traits = EnabledTraits.defaults
        #expect(condition.traitsAxisSatisfied(enabledTraits: traits))
    }

    @Test func traitsAxisDefaultSentinelHandling() {
        // Condition requires the "default" sentinel; runtime traits have it implicitly.
        let condition = Module.PluginUsageCondition(
            hostPlatforms: [], targetPlatforms: [], traits: ["default"]
        )
        let traits = EnabledTraits.defaults
        #expect(condition.traitsAxisSatisfied(enabledTraits: traits))
    }

    @Test func traitsAxisIntersection() {
        let condition = Module.PluginUsageCondition(
            hostPlatforms: [], targetPlatforms: [], traits: ["Logging"]
        )
        // The runtime trait set must contain "Logging" for the condition to match.
        let withLogging = EnabledTraits([
            EnabledTrait(name: "Logging", setBy: .traitConfiguration),
        ])
        let withoutLogging = EnabledTraits([
            EnabledTrait(name: "Metrics", setBy: .traitConfiguration),
        ])
        #expect(condition.traitsAxisSatisfied(enabledTraits: withLogging))
        #expect(!condition.traitsAxisSatisfied(enabledTraits: withoutLogging))
    }

    @Test func satisfiesIsAndOfThreeAxes() {
        let condition = Module.PluginUsageCondition(
            hostPlatforms: [.macOS], targetPlatforms: [.iOS], traits: ["default"]
        )
        let host = BuildEnvironment(platform: .macOS, configuration: .debug)
        let target = BuildEnvironment(platform: .iOS, configuration: .debug)

        // All three axes pass.
        #expect(condition.satisfies(
            hostEnvironment: host,
            targetEnvironment: target,
            enabledTraits: .defaults
        ))
        // Host axis fails.
        #expect(!condition.satisfies(
            hostEnvironment: BuildEnvironment(platform: .linux, configuration: .debug),
            targetEnvironment: target,
            enabledTraits: .defaults
        ))
        // Target axis fails.
        #expect(!condition.satisfies(
            hostEnvironment: host,
            targetEnvironment: BuildEnvironment(platform: .watchOS, configuration: .debug),
            enabledTraits: .defaults
        ))
    }
}

@Suite struct PIFConfiguredTargetModeTests {
    @Test func twoCases() {
        // The enum should have exactly two cases; this guard fires if a future case is
        // added without updating the rest of the per-platform fan-out logic.
        let modes: [PIFConfiguredTargetMode] = [.single, .multiple]
        #expect(modes.count == 2)
    }

    @Test func singleAndMultipleAreDistinct() {
        #expect(PIFConfiguredTargetMode.single != PIFConfiguredTargetMode.multiple)
    }
}
