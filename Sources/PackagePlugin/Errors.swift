/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

public enum PluginContextError: Error {
    /// Could not find a tool with the given name. This could be either because
    /// it doesn't exist, or because the plugin doesn't have a dependency on it.
    case toolNotFound(name: String)
}

extension PluginContextError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .toolNotFound(let name):
            return "Plugin does not have access to a tool named ‘\(name)’"
        }
    }
}

public enum PluginDeserializationError: Error {
    /// The input JSON is malformed in some way; the message provides more details.
    case malformedInputJSON(_ message: String)
}

extension PluginDeserializationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .malformedInputJSON(let message):
            return "Malformed input JSON: \(message)"
        }
    }
}
