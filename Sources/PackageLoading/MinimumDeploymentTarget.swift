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

    static func computeMinimumDeploymentTarget(of binaryPath: AbsolutePath, platform: PackageModel.Platform) throws -> PlatformVersion? {
        guard let (_, platformName) = platform.sdkNameAndPlatform else {
            return nil
        }

        let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "vtool", "-show-build", binaryPath.pathString])
        var lines = try runResult.utf8Output().components(separatedBy: "\n")
        while !lines.isEmpty {
            let first = lines.removeFirst()
            if first.contains("platform \(platformName)"), let line = lines.first, line.contains("minos") {
                return line.components(separatedBy: " ").last.map(PlatformVersion.init(stringLiteral:))
            }
        }
        return nil
    }

    static func computeXCTestMinimumDeploymentTarget(with runResult: ProcessResult, platform: PackageModel.Platform) throws -> PlatformVersion? {
        guard let output = try runResult.utf8Output().spm_chuzzle() else { return nil }
        let sdkPath = try AbsolutePath(validating: output)
        let xcTestPath = sdkPath.appending(RelativePath("Developer/Library/Frameworks/XCTest.framework/XCTest"))
        return try computeMinimumDeploymentTarget(of: xcTestPath, platform: platform)
    }

    static func computeXCTestMinimumDeploymentTarget(for platform: PackageModel.Platform) -> PlatformVersion {
        guard let (sdkName, _) = platform.sdkNameAndPlatform else {
            return platform.oldestSupportedVersion
        }

        // On macOS, we are determining the deployment target by looking at the XCTest binary.
        #if os(macOS)
        do {
            let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "--sdk", sdkName, "--show-sdk-platform-path"])

            if let version = try computeXCTestMinimumDeploymentTarget(with: runResult, platform: platform) {
                return version
            }
        } catch { } // we do not treat this a fatal and instead use the fallback minimum deployment target
        #endif

        return platform.oldestSupportedVersion
    }
}

private extension PackageModel.Platform {
    var sdkNameAndPlatform: (String, String)? {
        switch self {
        case .macOS:
            return ("macosx", "MACOS")
        case .macCatalyst:
            return ("macosx", "MACCATALYST")
        case .iOS:
            return ("iphoneos", "IOS")
        case .tvOS:
            return ("appletvos", "TVOS")
        case .watchOS:
            return ("watchos", "WATCHOS")
        case .driverKit:
            return nil // DriverKit does not support XCTest.
        default:
            return nil
        }
    }
}
