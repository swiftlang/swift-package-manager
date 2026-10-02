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

import struct PackageModel.BuildCacheConfiguration

extension BuildCacheConfiguration {
    /// Returns the build setting overrides corresponding to this cache configuration.
    public func constructBuildCacheSettingsOverrides(usingXcodeDeveloperDirectory: Bool) -> [String: String] {
        var settings: [String: String] = [:]

        // Caching is off by default, so only emit overrides when it's enabled.
        if self.enabled != true {
            return settings
        }

        settings["SWIFT_ENABLE_COMPILE_CACHE"] = "YES"
        settings["CLANG_ENABLE_COMPILE_CACHE"] = "YES"
        settings["SWIFT_ENABLE_EXPLICIT_MODULES"] = "YES"
        settings["CLANG_ENABLE_EXPLICIT_MODULES"] = "YES"

        if let casPath = self.casPath {
            settings["COMPILATION_CACHE_CAS_PATH"] = casPath.pathStringWithPosixSlashes
        }

        switch self.sizeLimit {
        case .size(let value):
            settings["COMPILATION_CACHE_LIMIT_SIZE"] = value
        case .percent(let value):
            settings["COMPILATION_CACHE_LIMIT_PERCENT"] = "\(value)"
        case .none:
            break
        }

        if let enableDiagnosticRemarks = self.enableDiagnosticRemarks {
            settings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = enableDiagnosticRemarks ? "YES" : "NO"
        }

        if let pluginPath = self.pluginPath {
            settings["COMPILATION_CACHE_PLUGIN_PATH"] = pluginPath.pathStringWithPosixSlashes
        }

        // Enable the CAS plugin when a plugin path is provided, or when building
        // with an Xcode developer directory, which ships a compatible plugin.
        if self.pluginPath != nil || usingXcodeDeveloperDirectory {
            settings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
        }

        if let remoteServicePath = self.remoteServicePath {
            settings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = remoteServicePath.pathStringWithPosixSlashes
        }

        // Caching is enabled here, so default prefix mapping to on unless the user
        // expressed a preference.
        let enablePrefixMapping = self.enablePrefixMapping ?? true
        let prefixMappingValue = enablePrefixMapping ? "YES" : "NO"
        settings["CLANG_ENABLE_PREFIX_MAPPING"] = prefixMappingValue
        settings["SWIFT_ENABLE_PREFIX_MAPPING"] = prefixMappingValue
        settings["CLANG_ENABLE_PROJECT_PREFIX_MAPPING"] = prefixMappingValue
        settings["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] = prefixMappingValue

        return settings
    }
}
