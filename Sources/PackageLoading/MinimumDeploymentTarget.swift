/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic

public struct MinimumDeploymentTarget {
    public let xcTestMinimumDeploymentTargets: [PackageModel.Platform:PlatformVersion]

    public static let `default`: MinimumDeploymentTarget = .init()

    public init() {
        xcTestMinimumDeploymentTargets = PlatformRegistry.default.knownPlatforms.reduce([PackageModel.Platform:PlatformVersion]()) {
            var dict = $0
            dict[$1] = Self.computeXCTestMinimumDeploymentTarget(for: $1)
            return dict
        }
    }

    static func computeMinimumDeploymentTarget(of binaryPath: AbsolutePath) throws -> PlatformVersion? {
        let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "vtool", "-show-build", binaryPath.pathString])
        guard let versionString = try runResult.utf8Output().components(separatedBy: "\n").first(where: { $0.contains("minos") })?.components(separatedBy: " ").last else { return nil }
        return PlatformVersion(versionString)
    }

    static func computeXCTestMinimumDeploymentTarget(with runResult: ProcessResult) throws -> PlatformVersion? {
        guard let output = try runResult.utf8Output().spm_chuzzle() else { return nil }
        let sdkPath = try AbsolutePath(validating: output)
        let xcTestPath = sdkPath.appending(RelativePath("Developer/Library/Frameworks/XCTest.framework/XCTest"))
        return try computeMinimumDeploymentTarget(of: xcTestPath)
    }

    static func computeXCTestMinimumDeploymentTarget(for platform: PackageModel.Platform) -> PlatformVersion {
        guard let sdkName = platform.sdkName else {
            return platform.oldestSupportedVersion
        }

        // On macOS, we are determining the deployment target by looking at the XCTest binary.
        #if os(macOS)
        do {
            let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "--sdk", sdkName, "--show-sdk-platform-path"])

            if let version = try computeXCTestMinimumDeploymentTarget(with: runResult) {
                return version
            }
        } catch { } // we do not treat this a fatal and instead use the fallback minimum deployment target
        #endif

        return platform.oldestSupportedVersion
    }
}

private extension PackageModel.Platform {
    var sdkName: String? {
        switch self {
        case .macOS:
            return "macosx"
        case .iOS:
            return "iphoneos"
        case .tvOS:
            return "appletvos"
        case .watchOS:
            return "watchos"
        default:
            return nil
        }
    }
}
