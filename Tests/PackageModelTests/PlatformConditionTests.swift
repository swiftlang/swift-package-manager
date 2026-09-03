//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import PackageModel
import Testing

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct PlatformConditionTests {

    @Test
    func noneOSPlatformConditionSatisfied() {
        // A build environment with Platform.custom(name: "none") should satisfy
        // a condition that requires .custom("none") — the Embedded Swift use case.
        let platform = Platform.custom(name: "none", oldestSupportedVersion: .unknown)
        let environment = BuildEnvironment(platform: platform)
        let condition = PlatformsCondition(platforms: [
            .custom(name: "none", oldestSupportedVersion: .unknown)
        ])
        #expect(condition.satisfies(environment))
    }

    @Test
    func noneOSPlatformDoesNotSatisfyLinux() {
        // Ensure .custom("none") does NOT match .linux
        let platform = Platform.custom(name: "none", oldestSupportedVersion: .unknown)
        let environment = BuildEnvironment(platform: platform)
        let condition = PlatformsCondition(platforms: [.linux])
        #expect(!condition.satisfies(environment))
    }

    @Test
    func linuxPlatformDoesNotSatisfyNoneOS() {
        // Ensure .linux does NOT match a condition requiring .custom("none")
        let environment = BuildEnvironment(platform: .linux)
        let condition = PlatformsCondition(platforms: [
            .custom(name: "none", oldestSupportedVersion: .unknown)
        ])
        #expect(!condition.satisfies(environment))
    }

    @Test
    func knownPlatformConditionsStillWork() {
        // Smoke test: known platforms still satisfy their own conditions.
        let knownPairs: [(Platform, Platform)] = [
            (.macOS, .macOS),
            (.linux, .linux),
            (.wasi, .wasi),
            (.windows, .windows),
            (.iOS, .iOS),
        ]
        for (envPlatform, condPlatform) in knownPairs {
            let environment = BuildEnvironment(platform: envPlatform)
            let condition = PlatformsCondition(platforms: [condPlatform])
            #expect(condition.satisfies(environment), "Expected \(envPlatform.name) to satisfy its own condition")
        }
    }

    @Test
    func targetAndHostPlatformConditionsUseIndependentEnvironments() {
        let targetCondition = PackageCondition(platforms: [.iOS])
        let hostCondition = PackageCondition(hostPlatforms: [.macOS])
        let targetEnvironment = BuildEnvironment(platform: .iOS)
        let hostEnvironment = BuildEnvironment(platform: .macOS)

        #expect(targetCondition.satisfies(
            targetEnvironment: targetEnvironment,
            hostEnvironment: hostEnvironment
        ))
        #expect(hostCondition.satisfies(
            targetEnvironment: targetEnvironment,
            hostEnvironment: hostEnvironment
        ))
        #expect(!targetCondition.satisfies(
            targetEnvironment: hostEnvironment,
            hostEnvironment: targetEnvironment
        ))
        #expect(!hostCondition.satisfies(
            targetEnvironment: hostEnvironment,
            hostEnvironment: targetEnvironment
        ))
    }

    @Test
    func allSpecifiedConditionAxesMustMatch() {
        let conditions: [PackageCondition] = [
            .init(platforms: [.iOS]),
            .init(hostPlatforms: [.macOS]),
            .init(configuration: .debug),
        ]

        #expect(conditions.allSatisfy {
            $0.satisfies(
                targetEnvironment: .init(platform: .iOS, configuration: .debug),
                hostEnvironment: .init(platform: .macOS, configuration: .debug)
            )
        })
        #expect(!conditions.allSatisfy {
            $0.satisfies(
                targetEnvironment: .init(platform: .iOS, configuration: .debug),
                hostEnvironment: .init(platform: .linux, configuration: .debug)
            )
        })
    }
}
