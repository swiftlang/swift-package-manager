/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

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
    public init?(reading path: AbsolutePath, diagnostics: DiagnosticsEngine?, filesystem: FileSystem) {
        guard filesystem.exists(path) else {
            diagnostics?.emit(error: "missing SDKSettings.plist at '\(path)'")
            return nil
        }

        do {
            let contents = try filesystem.readFileContents(path)
            self = try contents.withData {
                try PropertyListDecoder().decode(WindowsSDKSettings.self, from: $0)
            }
        } catch {
            diagnostics?.emit(error: "failed to load SDKSettings.plist at '\(path)': \(error)")
            return nil
        }
    }
}

public struct WindowsPlatformInfo {
    public struct DefaultProperties {
        /// XCTEST_VERSION
        /// specifies the version string of the bundled XCTest.
        public let xctestVersion: String
    }

    public let defaults: DefaultProperties
}

extension WindowsPlatformInfo.DefaultProperties: Decodable {
    enum CodingKeys: String, CodingKey {
    case xctestVersion = "XCTEST_VERSION"
    }
}

extension WindowsPlatformInfo: Decodable {
    enum CodingKeys: String, CodingKey {
    case defaults = "DefaultProperties"
    }
}

extension WindowsPlatformInfo {
    public init?(reading path: AbsolutePath, diagnostics: DiagnosticsEngine?, filesystem: FileSystem) {
        guard filesystem.exists(path) else {
            diagnostics?.emit(error: "missing Info.plist at '\(path)'")
            return nil
        }

        do {
            let contents = try filesystem.readFileContents(path)
            self = try contents.withData {
                try PropertyListDecoder().decode(WindowsPlatformInfo.self, from: $0)
            }
        } catch {
            diagnostics?.emit(error: "failed to load Info.plist at '\(path)': \(error)")
            return nil
        }
    }
}
