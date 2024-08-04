//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

public struct WindowsSDKSettings {
    public struct DefaultProperties {
        public enum Runtime: String, Decodable {
        /// MultiThreadedDebugDLL
        /// Use the debug variant of the C runtime with shared linking.
        case multithreadedDebugDLL = "MDd"

        /// MultiThreadedDLL
        /// Use the release variant of the C runtime with shared linking.
        case multithreadedDLL = "MD"

        /// MultiThreadedDebug
        /// Use the debug variant of the C runtime with static linking.
        case multithreadedDebug = "MTd"

        /// MultiThreaded
        /// Use the release variant of the C runtime with static linking.
        case multithreaded = "MT"
        }

        /// DEFAULT_USE_RUNTIME - specifies the C runtime variant to use
        public let runtime: Runtime
    }

    public let defaults: DefaultProperties
}

extension WindowsSDKSettings.DefaultProperties: Decodable {
    enum CodingKeys: String, CodingKey {
    case runtime = "DEFAULT_USE_RUNTIME"
    }
}

extension WindowsSDKSettings: Decodable {
    enum CodingKeys: String, CodingKey {
    case defaults = "DefaultProperties"
    }
}

extension WindowsSDKSettings {
    public init?(reading path: AbsolutePath, observabilityScope: ObservabilityScope?, filesystem: FileSystem) {
        guard filesystem.exists(path) else {
            observabilityScope?.emit(error: "missing SDKSettings.plist at '\(path)'")
            return nil
        }

        do {
            let data: Data = try filesystem.readFileContents(path)
            self = try PropertyListDecoder().decode(WindowsSDKSettings.self, from: data)
        } catch {
            observabilityScope?.emit(
                error: "failed to load SDKSettings.plist at '\(path)'",
                underlyingError: error
            )
            return nil
        }
    }
}

public struct WindowsPlatformInfo {
    public struct DefaultProperties {
        /// XCTEST_VERSION
        /// specifies the version string of the bundled XCTest.
        public let xctestVersion: String

        /// SWIFT_TESTING_VERSION
        /// specifies the version string of the bundled swift-testing.
        public let swiftTestingVersion: String?

        /// SWIFTC_FLAGS
        /// Specifies extra flags to pass to swiftc from Swift Package Manager.
        public let extraSwiftCFlags: [String]?
    }

    public let defaults: DefaultProperties
}

extension WindowsPlatformInfo.DefaultProperties: Decodable {
    enum CodingKeys: String, CodingKey {
    case xctestVersion = "XCTEST_VERSION"
    case swiftTestingVersion = "SWIFT_TESTING_VERSION"
    case extraSwiftCFlags = "SWIFTC_FLAGS"
    }
}

extension WindowsPlatformInfo: Decodable {
    enum CodingKeys: String, CodingKey {
    case defaults = "DefaultProperties"
    }
}

extension WindowsPlatformInfo {
    public init?(reading path: AbsolutePath, observabilityScope: ObservabilityScope?, filesystem: FileSystem) {
        guard filesystem.exists(path) else {
            observabilityScope?.emit(error: "missing Info.plist at '\(path)'")
            return nil
        }

        do {
            let data: Data = try filesystem.readFileContents(path)
            self = try PropertyListDecoder().decode(WindowsPlatformInfo.self, from: data)
        } catch {
            observabilityScope?.emit(
                error: "failed to load Info.plist at '\(path)'",
                underlyingError: error
            )
            return nil
        }
    }
}
