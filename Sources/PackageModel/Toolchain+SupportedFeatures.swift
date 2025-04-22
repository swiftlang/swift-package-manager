//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import enum TSCBasic.JSON
import TSCUtility

public enum SwiftCompilerFeature {
    case upcoming(name: String, migratable: Bool, enabledIn: SwiftLanguageVersion)
    case experimental(name: String, migratable: Bool)

    public var upcoming: Bool {
        switch self {
        case .upcoming: true
        case .experimental: false
        }
    }

    public var experimental: Bool {
        switch self {
        case .upcoming: false
        case .experimental: true
        }
    }

    public var name: String {
        switch self {
        case .upcoming(name: let name, migratable: _, enabledIn: _):
            name
        case .experimental(name: let name, migratable: _):
            name
        }
    }

    public var migratable: Bool {
        switch self {
        case .upcoming(name: _, migratable: let migratable, enabledIn: _):
            migratable
        case .experimental(name: _, migratable: let migratable):
            migratable
        }
    }
}

extension Toolchain {
    public var swiftCompilerSupportedFeatures: [SwiftCompilerFeature] {
        get throws {
            let compilerOutput: String
            do {
                let result = try AsyncProcess.popen(args: swiftCompilerPath.pathString, "-print-supported-features")
                compilerOutput = try result.utf8Output().spm_chomp()
            } catch {
                throw InternalError("Failed to get supported features info (\(error.interpolationDescription))")
            }

            if compilerOutput.isEmpty {
                return []
            }

            let parsedSupportedFeatures: JSON
            do {
                parsedSupportedFeatures = try JSON(string: compilerOutput)
            } catch {
                throw InternalError(
                    "Failed to parse supported features info (\(error.interpolationDescription)).\nRaw compiler output: \(compilerOutput)"
                )
            }

            let features: JSON = try parsedSupportedFeatures.get("features")

            let upcoming: [SwiftCompilerFeature] = try features.getArray("upcoming").map {
                let name: String = try $0.get("name")
                let migratable: Bool? = $0.get("migratable")
                let enabledIn: String = try $0.get("enabled_in")

                guard let mode = SwiftLanguageVersion(string: enabledIn) else {
                    throw InternalError("Unknown swift language mode: \(enabledIn)")
                }

                return .upcoming(
                    name: name,
                    migratable: migratable ?? false,
                    enabledIn: mode
                )
            }

            let experimental: [SwiftCompilerFeature] = try features.getArray("experimental").map {
                let name: String = try $0.get("name")
                let migratable: Bool? = $0.get("migratable")

                return .experimental(
                    name: name,
                    migratable: migratable ?? false
                )
            }

            return upcoming + experimental
        }
    }
}
