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
import protocol TSCBasic.JSONMappable
import TSCUtility

public enum SwiftCompilerFeature {
    case optional(name: String, migratable: Bool, categories: [String], flagName: String)
    case upcoming(name: String, migratable: Bool, categories: [String], enabledIn: SwiftLanguageVersion)
    case experimental(name: String, migratable: Bool, categories: [String])

    public var optional: Bool {
        switch self {
        case .optional: true
        case .upcoming, .experimental: false
        }
    }
    public var upcoming: Bool {
        switch self {
        case .upcoming: true
        case .optional, .experimental: false
        }
    }

    public var experimental: Bool {
        switch self {
        case .optional, .upcoming: false
        case .experimental: true
        }
    }

    public var name: String {
        switch self {
        case .optional(name: let name, migratable: _, categories: _, flagName: _),
                .upcoming(name: let name, migratable: _, categories: _, enabledIn: _),
                .experimental(name: let name, migratable: _, categories: _):
            name
        }
    }

    public var migratable: Bool {
        switch self {
        case .optional(name: _, migratable: let migratable, categories: _, flagName: _),
             .upcoming(name: _, migratable: let migratable, categories: _, enabledIn: _),
             .experimental(name: _, migratable: let migratable, categories: _):
            migratable
        }
    }

    public var categories: [String] {
        switch self {
        case .optional(name: _, migratable: _, categories: let categories, flagName: _),
             .upcoming(name: _, migratable: _, categories: let categories, enabledIn: _),
             .experimental(name: _, migratable: _, categories: let categories):
            categories
        }
    }
}

extension Toolchain {
    public var supportesSupportedFeatures: Bool {
        guard let features = try? swiftCompilerSupportedFeatures else {
            return false
        }
        return !features.isEmpty
    }

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

            let optionalFeatures = (try? features.getArray("optional")) ?? []

            let optional: [SwiftCompilerFeature] = try optionalFeatures.map { json in
                let name: String = try json.get("name")
                let categories: [String]? = try json.getArrayIfAvailable("categories")
                let migratable: Bool? = json.get("migratable")
                let flagName: String = try json.get("flag_name")

                return .optional(
                    name: name,
                    migratable: migratable ?? false,
                    categories: categories ?? [name],
                    flagName: flagName
                )
            }

            let upcoming: [SwiftCompilerFeature] = try features.getArray("upcoming").map {
                let name: String = try $0.get("name")
                let categories: [String]? = try $0.getArrayIfAvailable("categories")
                let migratable: Bool? = $0.get("migratable")
                let enabledIn = if let version = try? $0.get(String.self, forKey: "enabled_in") {
                    version
                } else {
                    try String($0.get(Int.self, forKey: "enabled_in"))
                }

                guard let mode = SwiftLanguageVersion(string: enabledIn) else {
                    throw InternalError("Unknown swift language mode: \(enabledIn)")
                }

                return .upcoming(
                    name: name,
                    migratable: migratable ?? false,
                    categories: categories ?? [name],
                    enabledIn: mode
                )
            }

            let experimental: [SwiftCompilerFeature] = try features.getArray("experimental").map {
                let name: String = try $0.get("name")
                let categories: [String]? = try $0.getArrayIfAvailable("categories")
                let migratable: Bool? = $0.get("migratable")

                return .experimental(
                    name: name,
                    migratable: migratable ?? false,
                    categories: categories ?? [name]
                )
            }

            return optional + upcoming + experimental
        }
    }
}

fileprivate extension JSON {
    func getArrayIfAvailable<T: JSONMappable>(_ key: String) throws -> [T]? {
        do {
            return try get(key)
        } catch MapError.missingKey(key) {
            return nil
        }
    }
}
