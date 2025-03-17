//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum PluginContextError: Error {
    /// Could not find a tool with the given name. This could be either because
    /// it doesn't exist, or because the plugin doesn't have a dependency on it.
    case toolNotFound(name: String)

    /// Tool is not supported on the target platform
    case toolNotSupportedOnTargetPlatform(name: String)

    /// Could not find a target with the given name.
    case targetNotFound(name: String, package: Package)

    /// Could not find a product with the given name.
    case productNotFound(name: String, package: Package)
}

extension PluginContextError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .toolNotFound(let name):
            return "Plugin does not have access to a tool named ‘\(name)’"
        case .toolNotSupportedOnTargetPlatform(let name):
            return "Tool ‘\(name)’ is not supported on the target platform"
        case .targetNotFound(let name, let package):
            return "Package ‘\(package.displayName)’ has no target named ‘\(name)’"
        case .productNotFound(let name, let package):
            return "Package ‘\(package.displayName)’ has no product named ‘\(name)’"
        }
    }
}

public enum PluginDeserializationError: Error {
    /// The input JSON is malformed in some way; the message provides more details.
    case malformedInputJSON(_ message: String)
    /// The plugin doesn't support Xcode (it doesn't link against XcodeProjectPlugin).
    case missingXcodeProjectPluginSupport
    /// The plugin doesn't conform to an expected specialization of the BuildToolPlugin protocol.
    case missingBuildToolPluginProtocolConformance(protocolName: String)
    /// The plugin doesn't conform to an expected specialization of the CommandPlugin protocol.
    case missingCommandPluginProtocolConformance(protocolName: String)
    /// An internal error of some kind; the message provides more details.
    case internalError(_ message: String)
}

extension PluginDeserializationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .malformedInputJSON(let message):
            return "Malformed input JSON: \(message)"
        case .missingXcodeProjectPluginSupport:
            return "Plugin doesn't support Xcode projects (it doesn't use the XcodeProjectPlugin library)"
        case .missingBuildToolPluginProtocolConformance(let protocolName):
            return "Plugin is declared with the `buildTool` capability, but doesn't conform to the `\(protocolName)` protocol"
        case .missingCommandPluginProtocolConformance(let protocolName):
            return "Plugin is declared with the `command` capability, but doesn't conform to the `\(protocolName)` protocol"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
