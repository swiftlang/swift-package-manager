/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// Represents an object which can be converted into a diagnostic data.
// FIXME: Kill this
public protocol DiagnosticDataConvertible {

    /// Diagnostic data representation of this instance.
    var diagnosticData: DiagnosticData { get }
}

/// DiagnosticData wrapper for Swift errors.
public struct AnyDiagnostic: DiagnosticData {
    public let anyError: Swift.Error

    public init(_ error: Swift.Error) {
        self.anyError = error
    }

    public var description: String {
        return "\(anyError)"
    }
}

extension DiagnosticsEngine {

    public func emit(
        error: String,
        location: DiagnosticLocation? = nil
    ) {
        emit(.error(error), location: location)
    }

    public func emit(
        warning: String,
        location: DiagnosticLocation? = nil
    ) {
        emit(.warning(warning), location: location)
    }

    public func emit(
        note: String,
        location: DiagnosticLocation? = nil
    ) {
        emit(.note(note), location: location)
    }

  public func emit(
      remark: String,
      location: DiagnosticLocation? = nil
  ) {
      emit(.remark(remark), location: location)
  }

    /// Emit a Swift error.
    ///
    /// Errors will be converted into diagnostic data if possible.
    /// Otherwise, they will be emitted as AnyDiagnostic.
    public func emit(
        _ error: Swift.Error,
        location: DiagnosticLocation? = nil
    ) {
        if let diagnosticData = error as? DiagnosticData {
            emit(.error(diagnosticData), location: location)
        } else if case let convertible as DiagnosticDataConvertible = error {
            emit(convertible, location: location)
        } else {
            emit(.error(AnyDiagnostic(error)), location: location)
        }
    }

    /// Emit a diagnostic data convertible instance.
    public func emit(
        _ convertible: DiagnosticDataConvertible,
        location: DiagnosticLocation? = nil
     ) {
        emit(.error(convertible.diagnosticData), location: location)
    }

    @discardableResult
    public func with<T>(location: DiagnosticLocation, _ closure: (DiagnosticsEngine) -> T) -> T {
        let innerDiagnostics = DiagnosticsEngine(handlers: [self.emit], defaultLocation: location)
        return closure(innerDiagnostics)
    }

    /// Wrap a throwing closure, returning an optional value and
    /// emitting any thrown errors.
    ///
    /// - Parameters:
    ///     - closure: Closure to wrap.
    /// - Returns: Returns the return value of the closure wrapped
    ///   into an optional. If the closure throws, nil is returned.
    public func wrap<T>(_ closure: () throws -> T) -> T? {
        do {
            return try closure()
        } catch Diagnostics.fatalError {
            return nil
        } catch {
            emit(error)
            return nil
        }
    }

    /// Wrap a throwing closure, returning a success boolean and
    /// emitting any thrown errors.
    ///
    /// - Parameters:
    ///     - closure: Closure to wrap.
    /// - Returns: Returns true if the wrapped closure did not throw
    ///   and false otherwise.
    @discardableResult
    public func wrap(_ closure: () throws -> Void) -> Bool {
        do {
            try closure()
            return true
        } catch Diagnostics.fatalError {
            return false
        } catch {
            emit(error)
            return false
        }
    }
}

extension Optional where Wrapped == DiagnosticsEngine {
    public func emit(
        error: String,
        location: DiagnosticLocation? = nil
    ) throws {
        if case let diagnostics? = self {
            diagnostics.emit(.error(error), location: location)
        } else {
            throw StringError(error)
        }
    }

    public func emit(
        _ error: Swift.Error,
        location: DiagnosticLocation? = nil
    ) throws {
        if case let diagnostics? = self {
            diagnostics.emit(error, location: location)
        } else {
            throw error
        }
    }

    public func emit(
        _ convertible: DiagnosticDataConvertible,
        location: DiagnosticLocation? = nil
    ) throws {
        if case let diagnostics? = self {
            diagnostics.emit(.error(convertible.diagnosticData), location: location)
        } else {
            throw StringError(convertible.diagnosticData.description)
        }
    }

    public func emit(
        _ message: Diagnostic.Message,
        location: DiagnosticLocation? = nil
    ) throws {
        if case let diagnostics? = self {
            diagnostics.emit(message, location: location)
        } else if message.behavior == .error {
            throw StringError(message.text)
        }
    }
}

/// Namespace for representing diagnostic location of a package.
public enum PackageLocation {

    /// Represents location of a locally available package. This could be root
    /// package, edited dependency or checked out dependency.
    public struct Local: DiagnosticLocation {

        /// The name of the package, if known.
        public let name: String?

        /// The path to the package.
        public let packagePath: AbsolutePath

        public init(name: String? = nil, packagePath: AbsolutePath) {
            self.name = name
            self.packagePath = packagePath
        }

        public var description: String {
            let stream = BufferedOutputByteStream()
            if let name = name {
                stream <<< "'\(name)' "
            }
            stream <<< packagePath
            return stream.bytes.description
        }
    }

    /// Represents location a remote package with no checkout on disk.
    public struct Remote: DiagnosticLocation {

        /// The URL of the package.
        public let url: String

        /// The source control reference of the package. It could be version, branch, revision etc.
        public let reference: String

        public init(url: String, reference: String) {
            self.url = url
            self.reference = reference
        }

        public var description: String {
            return url + " @ " + reference
        }
    }
}

/// An Swift error enum that can be used as a stub to early exit from a method.
///
/// It is not expected for this enum to contain any payload or information about the
/// error. The actual errors and warnings are supposed to be added using the Diagnostics
/// engine.
public enum Diagnostics: Swift.Error {
    case fatalError
}
