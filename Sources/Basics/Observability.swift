/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCUtility

typealias TSCDiagnostic = TSCBasic.Diagnostic

// this could become a struct when we remove the "errorsReported" pattern
public class ObservabilitySystem {

    // global

    private static var _global = ObservabilitySystem(factory: NOOPFactory())
    private static var bootstrapped = false
    private static let lock = Lock()

    public static func bootstrapGlobal(factory: ObservabilityFactory) {
        Self.lock.withLock {
            // FIXME: disabled for testing
            //precondition(!Self.bootstrapped, "ObservabilitySystem can only bootstrapped once")
            Self._global = .init(factory: factory)
            Self.bootstrapped = true
        }
    }

    @available(*, deprecated, message: "this pattern is deprecated, transition to error handling instead")
    public static var errorsReported: Bool {
        Self.lock.withLock {
            Self._global.errorsReported
        }
    }

    // as we transition to async/await we can take advantage of Task Local values instead of a global
    fileprivate static var global: ObservabilitySystem {
        Self.lock.withLock {
            Self._global
        }
    }

    // compatibility with DiagnosticsEngine

    @available(*, deprecated, message: "temporary for transition DiagnosticsEngine -> DiagnosticsEmitter")
    public static func makeDiagnosticsEngine() -> DiagnosticsEngine {
        return DiagnosticsEngine(handlers: [{ Diagnostic($0).map{ self.global.diagnosticsHandler($0) } }])
    }

    // instance

    public var diagnosticsHandler: DiagnosticsHandler!
    private var _errorsReported = ThreadSafeBox<Bool>(false)

    public init(factory: ObservabilityFactory) {
        self.diagnosticsHandler = { diagnostic in
            if diagnostic.severity == .error {
                self._errorsReported.put(true)
            }
            factory.diagnosticsHandler(diagnostic)
        }
    }

    // FIXME: we want to remove this functionality and move to more conventional error handling
    @available(*, deprecated, message: "this pattern is deprecated, transition to error handling instead")
    public var errorsReported: Bool {
        self._errorsReported.get() ?? false
    }

    private struct NOOPFactory: ObservabilityFactory {
        var diagnosticsHandler: DiagnosticsHandler = { _ in }
    }
}

public protocol ObservabilityFactory {
    var diagnosticsHandler: DiagnosticsHandler { get }
}

public typealias DiagnosticsHandler = (Diagnostic) -> Void

public struct Diagnostic: CustomStringConvertible, Equatable {
    public let context: DiagnosticsContext?
    private let underlying: DiagnosticMessage

    public init(context: DiagnosticsContext?, message underlying: DiagnosticMessage) {
        self.context = context
        self.underlying = underlying
    }

    public var severity: DiagnosticMessage.Severity {
        self.underlying.severity
    }

    public var message: String {
        self.underlying.message
    }


    public var data: CustomStringConvertible? {
        self.underlying.data
    }

    public var description: String {
        return "[\(self.severity)]: \(self.message)"
    }

    public static func == (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        if lhs.context?.description != rhs.context?.description {
            return false
        }
        if lhs.underlying != rhs.underlying {
            return false
        }
        return true
    }
}

// TODO: consider using @autoclosure to delay potentially expensive evaluation of data when some diagnostics may be filtered out
public struct DiagnosticsEmitter {
    public let context: DiagnosticsContext?
    private let handler: DiagnosticsHandler

    public init(context: DiagnosticsContext? = .none) {
        self.context = context
        self.handler = ObservabilitySystem.global.diagnosticsHandler
    }

    public func emit(_ diagnostic: Diagnostic) {
        self.handler(diagnostic)
    }

    public func emit(_ message: DiagnosticMessage) {
        self.emit(.init(context: self.context, message: message))
    }

    public func emit(severity: DiagnosticMessage.Severity, message: String, data: CustomStringConvertible? = .none) {
        self.emit(.init(context: self.context, message: .init(severity: severity, message: message, data: data)))
    }

    public func emit(error message: String, data: CustomStringConvertible? = .none) {
        self.emit(.error(message, data: data))
    }

    public func emit(_ error: Error, data: CustomStringConvertible? = .none) {
        // FIXME: this brings in the TSC API still
        if self.context == nil, let errorProvidingLocation = error as? DiagnosticLocationProviding, let diagnosticLocation = errorProvidingLocation.diagnosticLocation {
            let context = DiagnosticLocationWrapper(diagnosticLocation)
            return DiagnosticsEmitter(context: context).emit(error)
        }
        self.emit(.error(error, data: data))
    }

    public func emit(warning message: String, data: CustomStringConvertible? = .none) {
        self.emit(.warning(message, data: data))
    }

    public func emit(info message: String, data: CustomStringConvertible? = .none) {
        self.emit(.info(message, data: data))
    }

    public func trap<T>(_ closure: () throws -> T) -> T? {
        do  {
            return try closure()
        } catch {
            self.emit(error)
            return nil
        }
    }
}

public struct DiagnosticMessage: Equatable {
    let severity: Severity
    let message: String
    // 👀 TODO: not sure if this is used very much, but it we need it this could/should be changed to more structured metadata model
    let data: CustomStringConvertible?

    public static func error(_ message: String, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .error, message: message, data: data)
    }

    public static func error(_ message: CustomStringConvertible, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .error, message: message.description, data: data)
    }

    public static func error(_ error: Error, data: CustomStringConvertible? = .none) -> Self {
        let message: String
        // FIXME: this brings in the TSC API still
        // FIXME: string interpolation seems brittle
        if let diagnosticData = error as? DiagnosticData {
            message = "\(diagnosticData)"
        } else if let convertible = error as? DiagnosticDataConvertible {
            message = "\(convertible.diagnosticData)"
        } else {
            message = "\(error)"
        }
        return Self(severity: .error, message: message, data: data)
    }

    public static func warning(_ message: String, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .warning, message: message, data: data)
    }

    public static func warning(_ message: CustomStringConvertible, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .warning, message: message.description, data: data)
    }

    public static func info(_ message: String, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .info, message: message, data: data)
    }

    public static func info(_ message: CustomStringConvertible, data: CustomStringConvertible? = .none) -> Self {
        Self(severity: .info, message: message.description, data: data)
    }

    public static func note(_ message: CustomStringConvertible, data: CustomStringConvertible? = .none) -> Self {
        // 👀 do we need info and note?
        Self(severity: .note, message: message.description, data: data)
    }

    public enum Severity: Equatable {
        case error
        case warning
        // 👀 do we need info and note?
        case info
        case note
    }

    public static func == (lhs: DiagnosticMessage, rhs: DiagnosticMessage) -> Bool {
        if lhs.severity != rhs.severity {
            return false
        }
        if lhs.message != rhs.message {
            return false
        }
        if lhs.data?.description != rhs.data?.description {
            return false
        }
        return true
    }
}

// 👀 TODO: this could/should be changed to more structured metadata model
public protocol DiagnosticsContext: CustomStringConvertible {}

public struct StringDiagnosticsContext: DiagnosticsContext{
    public private (set) var description: String

    public init(_ description: String) {
        self.description = description
    }
}

@available(*, deprecated, message: "temporary for transition DiagnosticsEngine -> DiagnosticsEmitter")
extension Diagnostic {
    init?(_ diagnostic: TSCDiagnostic) {
        switch diagnostic.behavior {
        case .error:
            self = .init(context: DiagnosticLocationWrapper(diagnostic.location), message: .error(diagnostic.message.text, data: diagnostic.message.data))
        case .warning:
            self = .init(context: DiagnosticLocationWrapper(diagnostic.location), message: .warning(diagnostic.message.text, data: diagnostic.message.data))
        case .note:
            self = .init(context: DiagnosticLocationWrapper(diagnostic.location), message: .note(diagnostic.message.text, data: diagnostic.message.data))
        case .remark:
            // 👀 remark mapped to info here, do we need all these levels?
            self = .init(context: DiagnosticLocationWrapper(diagnostic.location), message: .info(diagnostic.message.text, data: diagnostic.message.data))
        case .ignored:
            // 👀 is this okay?
            return nil
        }
    }
}

@available(*, deprecated, message: "temporary for transition DiagnosticsEngine -> DiagnosticsEmitter")
struct DiagnosticLocationWrapper: DiagnosticsContext {
    let location: DiagnosticLocation

    init?(_ location: DiagnosticLocation) {
        if location is UnknownLocation {
            return nil
        } else {
            self.location = location
        }
    }

    var description: String {
        self.location.description
    }
}
