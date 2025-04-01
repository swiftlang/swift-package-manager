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

/// Errors the system can encounter discovering a plugin's context.
public enum PluginContextError: Error {
    /// The system couldn't find a tool with the given name.
    ///
    /// This error can occur because the tool doesn't exist,
    /// or because the plugin doesn't have a dependency on it.
    case toolNotFound(name: String)

    /// The tool isn't supported on the target platform.
    case toolNotSupportedOnTargetPlatform(name: String)

    /// The system couldn't find a target with the specified name in the package.
    case targetNotFound(name: String, package: Package)

    /// The system couldn't find a product with the specified name in the package.
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

/// Errors the system can encounter deserializing a plugin.
public enum PluginDeserializationError: Error {
    /// The input JSON is malformed.
    ///
    /// The associated message provides more details about the problem.
    case malformedInputJSON(_ message: String)
    /// The plugin doesn't support Xcode.
    ///
    /// To support Xcode, a plugin needs to link against `XcodeProjectPlugin`.
    case missingXcodeProjectPluginSupport
    /// The package uses a build-tool plugin that doesn't conform to the correct protocol.
    ///
    /// To act as a build-tool plugin, the plugin needs to conform to ``BuildToolPlugin``.
    case missingBuildToolPluginProtocolConformance(protocolName: String)
    /// The package uses a command plugin that doesn't conform to the correct protocol.
    ///
    /// To act as a command plugin, the plugin needs to conform to ``CommandPlugin``.
    case missingCommandPluginProtocolConformance(protocolName: String)
    /// An internal error occurred.
    ///
    /// The associated message provides more details about the problem.
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
