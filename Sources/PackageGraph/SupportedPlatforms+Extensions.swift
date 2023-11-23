//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

extension SupportedPlatforms {
    /// Returns the supported platform instance for the given platform.
    public func getDerived(
        for platform: Platform,
        usingXCTest: Bool,
        derivedXCTestPlatformProvider: ((Platform) -> PlatformVersion?)?
    ) -> SupportedPlatform {
        // derived platform based on known minimum deployment target logic
        if let declaredPlatform = self.declared.first(where: { $0.platform == platform }) {
            var version = declaredPlatform.version

            if usingXCTest,
                let xcTestMinimumDeploymentTarget = derivedXCTestPlatformProvider?(platform),
                version < xcTestMinimumDeploymentTarget {
                version = xcTestMinimumDeploymentTarget
            }

            // If the declared version is smaller than the oldest supported one, we raise the derived version to that.
            if version < platform.oldestSupportedVersion {
                version = platform.oldestSupportedVersion
            }

            return SupportedPlatform(
                platform: declaredPlatform.platform,
                version: version,
                options: declaredPlatform.options
            )
        } else {
            let minimumSupportedVersion: PlatformVersion
            if usingXCTest,
                let xcTestMinimumDeploymentTarget = derivedXCTestPlatformProvider?(platform),
                xcTestMinimumDeploymentTarget > platform.oldestSupportedVersion {
                minimumSupportedVersion = xcTestMinimumDeploymentTarget
            } else {
                minimumSupportedVersion = platform.oldestSupportedVersion
            }

            let oldestSupportedVersion: PlatformVersion
            if platform == .macCatalyst {
                let iOS = self.getDerived(
                    for: .iOS,
                    usingXCTest: usingXCTest,
                    derivedXCTestPlatformProvider: derivedXCTestPlatformProvider
                )
                // If there was no deployment target specified for Mac Catalyst, fall back to the iOS deployment target.
                oldestSupportedVersion = max(minimumSupportedVersion, iOS.version)
            } else {
                oldestSupportedVersion = minimumSupportedVersion
            }

            return SupportedPlatform(
                platform: platform,
                version: oldestSupportedVersion,
                options: []
            )
        }
    }
}
