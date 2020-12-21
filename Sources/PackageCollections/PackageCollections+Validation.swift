/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension Model.CollectionSource {
    func validate() -> [ValidationMessage]? {
        var messages: [ValidationMessage]?
        let appendMessage = { (message: ValidationMessage) in
            if messages == nil {
                messages = .init()
            }
            messages?.append(message)
        }

        let allowedSchemes = Set(["https", "file"])

        switch self.type {
        case .json:
            let scheme = url.scheme?.lowercased() ?? ""
            if !allowedSchemes.contains(scheme) {
                appendMessage(.error("Schema not allowed: \(url.absoluteString)"))
            } else if scheme == "file", !localFileSystem.exists(AbsolutePath(self.url.path)) {
                appendMessage(.error("Non-local files not allowed: \(url.absoluteString)"))
            }
        }

        return messages
    }
}

public struct ValidationMessage: Equatable, CustomStringConvertible {
    public let message: String
    public let level: Level
    public let property: String?

    private init(_ message: String, level: Level, property: String? = nil) {
        self.message = message
        self.level = level
        self.property = property
    }

    static func error(_ message: String, property: String? = nil) -> ValidationMessage {
        .init(message, level: .error, property: property)
    }

    static func warning(_ message: String, property: String? = nil) -> ValidationMessage {
        .init(message, level: .warning, property: property)
    }

    public enum Level: String, Equatable {
        case warning
        case error
    }

    public var description: String {
        "[\(self.level)] \(self.property.map { "\($0): " } ?? "")\(self.message)"
    }
}

extension Array where Element == ValidationMessage {
    func errors(include levels: Set<ValidationMessage.Level> = [.error]) -> [ValidationError]? {
        let errors = self.filter { levels.contains($0.level) }

        guard !errors.isEmpty else { return nil }

        return errors.map {
            if let property = $0.property {
                return ValidationError.property(name: property, message: $0.message)
            } else {
                return ValidationError.other(message: $0.message)
            }
        }
    }
}

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case property(name: String, message: String)
    case other(message: String)

    public var description: String {
        switch self {
        case .property(let name, let message):
            return "\(name): \(message)"
        case .other(let message):
            return message
        }
    }
}
