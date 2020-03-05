/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch

/// The payload of a diagnostic.
public protocol DiagnosticData: CustomStringConvertible {
}

extension DiagnosticData {
    public var localizedDescription: String { self.description }
}

public protocol DiagnosticLocation: CustomStringConvertible {
}

public struct Diagnostic: CustomStringConvertible {
    /// The behavior associated with this diagnostic.
    public enum Behavior {
        /// An error which will halt the operation.
        case error

        /// A warning, but which will not halt the operation.
        case warning

        case note

        case remark

        // FIXME: Kill this
        case ignored
    }

    public struct Message {
        /// The diagnostic's behavior.
        public let behavior: Behavior

        /// The information on the actual diagnostic.
        public let data: DiagnosticData

        /// The textual representation of the diagnostic data.
        public var text: String { data.description }

        fileprivate init(data: DiagnosticData, behavior: Behavior) {
            self.data = data
            self.behavior = behavior
        }
    }

    /// The message in this diagnostic.
    public let message: Message

    /// The conceptual location of this diagnostic.
    ///
    /// This could refer to a concrete location in a file, for example, but it
    /// could also refer to an abstract location such as "the Git repository at
    /// this URL".
    public let location: DiagnosticLocation

    public var data: DiagnosticData { message.data }
    public var behavior: Behavior { message.behavior }

    public init(
        message: Message,
        location: DiagnosticLocation = UnknownLocation.location
    ) {
        self.message = message
        self.location = location
    }

    public var description: String { message.text }

    public var localizedDescription: String { message.text }
}

public final class DiagnosticsEngine: CustomStringConvertible {

    public typealias DiagnosticsHandler = (Diagnostic) -> Void

    /// Queue to protect concurrent mutations to the diagnositcs engine.
    private let queue = DispatchQueue(label: "\(DiagnosticsEngine.self)")

    /// Queue for dispatching handlers.
    private let handlerQueue = DispatchQueue(label: "\(DiagnosticsEngine.self)-callback")

    /// The diagnostics produced by the engine.
    public var diagnostics: [Diagnostic] {
        return queue.sync { _diagnostics }
    }
    private var _diagnostics: [Diagnostic] = []

    /// The list of handlers to run when a diagnostic is emitted.
    ///
    /// The handler will be called on an unknown queue.
    private let handlers: [DiagnosticsHandler]

    /// The default location to apply to location-less diagnostics.
    public let defaultLocation: DiagnosticLocation

    /// Returns true if there is an error diagnostics in the engine.
    public var hasErrors: Bool {
        return diagnostics.contains(where: { $0.message.behavior == .error })
    }

    public init(handlers: [DiagnosticsHandler] = [], defaultLocation: DiagnosticLocation = UnknownLocation.location) {
        self.handlers = handlers
        self.defaultLocation = defaultLocation
    }

    public func emit(
        _ message: Diagnostic.Message,
        location: DiagnosticLocation? = nil
    ) {
        emit(Diagnostic(message: message, location: location ?? defaultLocation))
    }

    public func emit(_ diagnostic: Diagnostic) {
        queue.sync {
            _diagnostics.append(diagnostic)
        }

        // Call the handlers on the background queue, if we have any.
        if !handlers.isEmpty {
            // FIXME: We should probably do this async but then we need
            // a way for clients to be able to wait until all handlers
            // are called.
            handlerQueue.sync {
                for handler in self.handlers {
                    handler(diagnostic)
                }
            }
        }
    }

    /// Merges contents of given engine.
    public func merge(_ engine: DiagnosticsEngine) {
        for diagnostic in engine.diagnostics {
            emit(diagnostic.message, location: diagnostic.location)
        }
    }

    public var description: String {
        let stream = BufferedOutputByteStream()
        stream <<< "["
        for diag in diagnostics {
            stream <<< diag.description <<< ", "
        }
        stream <<< "]"
        return stream.bytes.description
    }
}

extension Diagnostic.Message {
    public static func error(_ data: DiagnosticData) -> Diagnostic.Message {
        .init(data: data, behavior: .error)
    }

    public static func warning(_ data: DiagnosticData) -> Diagnostic.Message {
        .init(data: data, behavior: .warning)
    }

    public static func note(_ data: DiagnosticData) -> Diagnostic.Message {
        .init(data: data, behavior: .note)
    }

    public static func remark(_ data: DiagnosticData) -> Diagnostic.Message {
      .init(data: data, behavior: .remark)
  }

    public static func error(_ str: String) -> Diagnostic.Message {
        .error(StringDiagnostic(str))
    }

    public static func warning(_ str: String) -> Diagnostic.Message {
        .warning(StringDiagnostic(str))
    }

    public static func note(_ str: String) -> Diagnostic.Message {
        .note(StringDiagnostic(str))
    }

    public static func remark(_ str: String) -> Diagnostic.Message {
        .remark(StringDiagnostic(str))
    }
}

public struct StringDiagnostic: DiagnosticData {
    /// The diagnostic description.
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Represents a diagnostic location whic is unknown.
public final class UnknownLocation: DiagnosticLocation {
    /// The singleton instance.
    public static let location = UnknownLocation()

    private init() {}

    public var description: String {
        return "<unknown>"
    }
}
