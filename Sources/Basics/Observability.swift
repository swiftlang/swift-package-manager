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

// designed after https://github.com/apple/swift-log
// designed after https://github.com/apple/swift-metrics
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
    public let severity: Severity
    public let message: String
    public internal (set) var metadata: DiagnosticsMetadata?

    public init(severity: Severity, message: String, metadata: DiagnosticsMetadata?) {
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }

    public var description: String {
        return "[\(self.severity)]: \(self.message)"
    }

    public static func == (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        if lhs.severity != rhs.severity {
            return false
        }
        if lhs.message != rhs.message {
            return false
        }
        // FIXME
        /*
         if lhs.metadata != rhs.metadata {
         return false
         }*/
        return true
    }

    public static func error(_ message: String, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .error, message: message, metadata: metadata)
    }

    public static func error(_ message: CustomStringConvertible, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .error, message: message.description, metadata: metadata)
    }

    public static func warning(_ message: String, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .warning, message: message, metadata: metadata)
    }

    public static func warning(_ message: CustomStringConvertible, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .warning, message: message.description, metadata: metadata)
    }

    public static func info(_ message: String, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .info, message: message, metadata: metadata)
    }

    public static func info(_ message: CustomStringConvertible, metadata: DiagnosticsMetadata? = .none) -> Self {
        Self(severity: .info, message: message.description, metadata: metadata)
    }

    public enum Severity: Equatable {
        case error
        case warning
        case info
        case debug
    }
}

// TODO: consider using @autoclosure to delay potentially expensive evaluation of data when some diagnostics may be filtered out
public struct DiagnosticsEmitter {
    public let metadata: DiagnosticsMetadata?
    private let handler: DiagnosticsHandler

    public init(metadata: DiagnosticsMetadata? = .none) {
        self.metadata = metadata
        self.handler = ObservabilitySystem.global.diagnosticsHandler
    }

    public func emit(_ diagnostic: Diagnostic) {
        var diagnostic = diagnostic
        switch (self.metadata, diagnostic.metadata) {
        case (.none, .none):
            break // no change
        case (.some(let emitterMetadata), .some(let diagnosticMetadata)):
            diagnostic.metadata = emitterMetadata.merging(diagnosticMetadata)
        case (.some(let emitterMetadata), .none):
            diagnostic.metadata = emitterMetadata
        case (.none, .some(_)):
            break // no change
        }

        self.handler(diagnostic)
    }

    /*
     public func emit(_ message: DiagnosticMessage) {
     self.emit(severity: message.severity, message: message.text, metadata: message.metadata)
     }*/

    public func emit(severity: Diagnostic.Severity, message: String, metadata: DiagnosticsMetadata? = .none) {
        self.emit(.init(severity: severity, message: message, metadata: metadata))
    }

    public func emit(error message: String, metadata: DiagnosticsMetadata? = .none) {
        self.emit(.error(message, metadata: metadata))
    }

    public func emit(_ error: Error, metadata: DiagnosticsMetadata? = .none) {
        var metadata = metadata
        // FIXME: this brings in the TSC API still
        if let errorProvidingLocation = error as? DiagnosticLocationProviding, let diagnosticLocation = errorProvidingLocation.diagnosticLocation {
            metadata = metadata ?? DiagnosticsMetadata()
            metadata?.stringLocation = diagnosticLocation.description
        }

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

        self.emit(severity: .error, message: message, metadata: metadata)
    }

    public func emit(warning message: String, metadata: DiagnosticsMetadata? = .none) {
        self.emit(severity: .warning, message: message, metadata: metadata)
    }

    public func emit(info message: String, metadata: DiagnosticsMetadata? = .none) {
        self.emit(severity: .info, message: message, metadata: metadata)
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

// MARK: - DiagnosticsMetadata

// designed after https://github.com/apple/swift-distributed-tracing-baggage

/// Provides type-safe access to the DiagnosticsMetadata's values.
/// This API should ONLY be used inside of accessor implementations.
///
/// End users should use "accessors" the key's author MUST define rather than using this subscript, following this pattern:
///
///     extension DiagnosticsMetadata {
///       var testID: String? {
///         get {
///           self[TestIDKey.self]
///         }
///         set {
///           self[TestIDKey.self] = newValue
///         }
///       }
///     }
///
///     enum TestIDKey: DiagnosticsMetadataKey {
///         typealias Value = String
///     }
///
/// This is in order to enforce a consistent style across projects and also allow for fine grained control over
/// who may set and who may get such property. Just access control to the Key type itself lacks such fidelity.
///
/// Note that specific baggage and context types MAY (and usually do), offer also a way to set baggage values,
/// however in the most general case it is not required, as some frameworks may only be able to offer reading.

// FIXME: we currently requires that Value conforms to CustomStringConvertible which sucks
// ideally Value would conform to Equatable but that has generic requirement
// luckily, this is about to change so we can clean this up soon
public struct DiagnosticsMetadata: Equatable {
    private var _storage = [AnyKey: CustomStringConvertible]()

    public init() {}

    public subscript<Key: DiagnosticsMetadataKey>(_ key: Key.Type) -> Key.Value? {
        get {
            guard let value = self._storage[AnyKey(key)] else { return nil }
            // safe to force-cast as this subscript is the only way to set a value.
            return (value as! Key.Value)
        }
        set {
            self._storage[AnyKey(key)] = newValue
        }
    }

    /// The number of items in the baggage.
    public var count: Int {
        self._storage.count
    }

    /// A Boolean value that indicates whether the baggage is empty.
    public var isEmpty: Bool {
        self._storage.isEmpty
    }

    /// Iterate through all items in this `DiagnosticsMetadata` by invoking the given closure for each item.
    ///
    /// The order of those invocations is NOT guaranteed and should not be relied on.
    ///
    /// - Parameter body: The closure to be invoked for each item stored in this `DiagnosticsMetadata`,
    /// passing the type-erased key and the associated value.
    public func forEach(_ body: (AnyKey, CustomStringConvertible) throws -> Void) rethrows {
        try self._storage.forEach { key, value in
            try body(key, value)
        }
    }

    public func merging(_ other: DiagnosticsMetadata) -> DiagnosticsMetadata {
        var merged = DiagnosticsMetadata()
        self.forEach { (key, value) in
            merged._storage[key] = value
        }
        other.forEach { (key, value) in
            merged._storage[key] = value
        }
        return merged
    }

    // FIXME: this currently requires that Value conforms to CustomStringConvertible which sucks
    // ideally Value would conform to Equatable but that has generic requirement
    // luckily, this is about to change so we can clean this up soon
    public static func == (lhs: DiagnosticsMetadata, rhs: DiagnosticsMetadata) -> Bool {
        if lhs.count != rhs.count {
            return false
        }

        var equals = true
        lhs.forEach { (key, value) in
            if rhs._storage[key]?.description != value.description {
                equals = false
                return
            }
        }

        return equals
    }

    /// A type-erased `DiagnosticsMetadataKey` used when iterating through the `DiagnosticsMetadata` using its `forEach` method.
    public struct AnyKey {
        /// The key's type represented erased to an `Any.Type`.
        public let keyType: Any.Type

        init<Key: DiagnosticsMetadataKey>(_ keyType: Key.Type) {
            self.keyType = keyType
        }
    }
}

public protocol DiagnosticsMetadataKey {
    /// The type of value uniquely identified by this key.
    associatedtype Value: CustomStringConvertible
}

extension DiagnosticsMetadata.AnyKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs.keyType) == ObjectIdentifier(rhs.keyType)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self.keyType))
    }
}

// MARK: - Compatibility with TSC Diagnostics APIs


@available(*, deprecated, message: "temporary for transition DiagnosticsEngine -> DiagnosticsEmitter")
extension Diagnostic {
    init?(_ diagnostic: TSCDiagnostic) {
        var metadata: DiagnosticsMetadata?
        if diagnostic.location is UnknownLocation {
            metadata = .none
        } else {
            metadata = DiagnosticsMetadata()
            metadata?.stringLocation = diagnostic.location.description
        }

        switch diagnostic.behavior {
        case .error:
            self = .error(diagnostic.message.text, metadata: metadata)
        case .warning:
            self = .warning(diagnostic.message.text, metadata: metadata)
        case .note:
            self = .info(diagnostic.message.text, metadata: metadata)
        case .remark:
            self = .info(diagnostic.message.text, metadata: metadata)
        case .ignored:
            return nil
        }
    }
}

@available(*, deprecated, message: "temporary for transition DiagnosticsEngine -> DiagnosticsEmitter")
extension DiagnosticsMetadata {
    public var stringLocation: String? {
        get {
            self[StringLocation.self]
        }
        set {
            self[StringLocation.self] = newValue
        }
    }

    enum StringLocation: DiagnosticsMetadataKey {
        typealias Value = String
    }
}
