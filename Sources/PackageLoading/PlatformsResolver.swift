/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel


public class PlatformsResolver {
    // A cache to store declared and inferred supported platforms, based on the `isTest` parameter.
    private var _declaredPlatforms = [Bool: [SupportedPlatform]]()
    private var _inferredPlatforms = [Bool: [SupportedPlatform]]()

    private let manifest: Manifest
    private let platformRegistry: PlatformRegistry
    /// Minimum deployment target of XCTest per platform.
    private let xcTestMinimumDeploymentTargets: [PackageModel.Platform: PlatformVersion]

    public init(
        manifest: Manifest,
        xcTestMinimumDeploymentTargets: [PackageModel.Platform: PlatformVersion] = MinimumDeploymentTarget.default.xcTestMinimumDeploymentTargets
    ) {
        self.manifest = manifest
        self.platformRegistry = .default
        self.xcTestMinimumDeploymentTargets = xcTestMinimumDeploymentTargets
    }

    /// Returns the list of platforms that are declared by the manifest.
    public func declaredPlatforms(target: Target) -> [SupportedPlatform] {
        self.declaredPlatforms(isTest: target.type == .test)
    }

    #warning("FIXME: (:isTest) variant even needed?")
    public func declaredPlatforms(isTest: Bool) -> [SupportedPlatform] {
        if let platforms = self._declaredPlatforms[isTest] {
            return platforms
        }

        var supportedPlatforms: [SupportedPlatform] = []

        /// Add each declared platform to the supported platforms list.
        for platform in self.manifest.platforms {
            let declaredPlatform = self.platformRegistry.platformByName[platform.platformName]
                ?? .custom(name: platform.platformName, oldestSupportedVersion: platform.version)
            var version = PlatformVersion(platform.version)

            if let xcTestMinimumDeploymentTarget = xcTestMinimumDeploymentTargets[declaredPlatform], isTest, version < xcTestMinimumDeploymentTarget {
                version = xcTestMinimumDeploymentTarget
            }

            let supportedPlatform = SupportedPlatform(
                platform: declaredPlatform,
                version: version,
                options: platform.options
            )

            supportedPlatforms.append(supportedPlatform)
        }

        self._declaredPlatforms[isTest] = supportedPlatforms
        return supportedPlatforms
    }

    /// Returns the list of platforms that are inferred to be supported by the manifest.
    public func inferredPlatforms(target: Target) -> [SupportedPlatform] {
        self.inferredPlatforms(isTest: target.type == .test)
    }

    #warning("FIXME: (:isTest) variant even needed?")
    public func inferredPlatforms(isTest: Bool) -> [SupportedPlatform] {
        if let platforms = self._inferredPlatforms[isTest] {
            return platforms
        }

        var supportedPlatforms = self.declaredPlatforms(isTest: isTest)

        // Find the undeclared platforms.
        let remainingPlatforms = Set(platformRegistry.platformByName.keys).subtracting(supportedPlatforms.map({ $0.platform.name }))

        /// Start synthesizing for each undeclared platform.
        for platformName in remainingPlatforms.sorted() {
            let platform = self.platformRegistry.platformByName[platformName]!

            let oldestSupportedVersion: PlatformVersion
            if let xcTestMinimumDeploymentTarget = xcTestMinimumDeploymentTargets[platform], isTest {
                oldestSupportedVersion = xcTestMinimumDeploymentTarget
            } else if platform == .macCatalyst, let iOS = supportedPlatforms.first(where: { $0.platform == .iOS }) {
                // If there was no deployment target specified for Mac Catalyst, fall back to the iOS deployment target.
                oldestSupportedVersion = max(platform.oldestSupportedVersion, iOS.version)
            } else {
                oldestSupportedVersion = platform.oldestSupportedVersion
            }

            let supportedPlatform = SupportedPlatform(
                platform: platform,
                version: oldestSupportedVersion,
                options: []
            )

            supportedPlatforms.append(supportedPlatform)
        }

        self._inferredPlatforms[isTest] = supportedPlatforms
        return supportedPlatforms
    }
}
