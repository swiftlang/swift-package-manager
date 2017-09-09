/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A type which can be used as a diagnostic parameter.
public protocol DiagnosticParameter {

    /// Human readable diagnostic description of the parameter.
    var diagnosticDescription: String { get }
}

// Default implementation for types which conform to CustomStringConvertible.
extension DiagnosticParameter where Self: CustomStringConvertible {
    public var diagnosticDescription: String {
        return description
    }
}

// Conform basic types.
extension String: DiagnosticParameter {}
extension Int: DiagnosticParameter {}

/// A builder for constructing diagnostic descriptions.
public class DiagnosticDescriptionBuilder<Data: DiagnosticData> {
    public var fragments: [DiagnosticID.DescriptionFragment] = []

    func build(
        _ body: (DiagnosticDescriptionBuilder) -> Void
    ) -> [DiagnosticID.DescriptionFragment] {
        body(self)
        return fragments
    }
}

@discardableResult
public func <<< <T>(
    builder: DiagnosticDescriptionBuilder<T>,
    string: String
) -> DiagnosticDescriptionBuilder<T> {
    builder.fragments.append(.literal(string, preference: .default))
    return builder
}

@discardableResult
public func <<<<T, P: DiagnosticParameter>(
    builder: DiagnosticDescriptionBuilder<T>,
    accessor: @escaping (T) -> P
) -> DiagnosticDescriptionBuilder<T> {
    builder.fragments.append(.substitution({ accessor($0 as! T) }, preference: .default))
    return builder
}

@discardableResult
public func <<< <T>(
    builder: DiagnosticDescriptionBuilder<T>,
    fragment: DiagnosticID.DescriptionFragment
) -> DiagnosticDescriptionBuilder<T> {
    builder.fragments.append(fragment)
    return builder
}

/// A unique identifier for a diagnostic.
///
/// Diagnostic identifiers are intended to be a stable representation of a
/// particular kind of diagnostic that can be emitted by the client.
///
/// The stabilty of identifiers is important for use cases where the client
/// (e.g., a command line tool, an IDE, or a web UI) is expecting to receive
/// diagnostics and be able to present additional UI affordances or workflows
/// associated for specific kinds of diagnostics.
///
//
// FIXME: One thing we should consider is whether we should make the diagnostic
// a protocol and put these properties on the type, which is conceptually the
// right modeling, but might be cumbersome of our desired features don't
// perfectly align with what the language can express.
public class DiagnosticID: ObjectIdentifierProtocol {

    /// A piece of a diagnostic description.
    public enum DescriptionFragment {
        /// Represents how important a fragment is.
        public enum Preference {
            case low, `default`, high
        }

        /// A literal string.
        case literalItem(String, preference: Preference)

        /// A substitution of a computed value.
        case substitutionItem((DiagnosticData) -> DiagnosticParameter, preference: Preference)

        public static func literal(
            _ string: String,
            preference: Preference = .default
        ) -> DescriptionFragment {
            return .literalItem(string, preference: preference)
        }

        public static func substitution(
            _ accessor: @escaping ((DiagnosticData) -> DiagnosticParameter),
            preference: Preference = .default
        ) -> DescriptionFragment {
            return .substitutionItem(accessor, preference: preference)
        }
    }

    /// The name of the diagnostic, which is expected to be in reverse dotted notation.
    public let name: String

    /// The English format string for the diagnostic description.
    public let description: [DescriptionFragment]

    /// The default behavior associated with this diagnostic.
    public let defaultBehavior: Diagnostic.Behavior

    /// Create a new diagnostic identifier.
    ///
    /// - Parameters:
    ///   - type: The type of the payload data, used to help type inference.
    ///
    ///   - name: The name of the identifier.
    ///
    ///   - description: A closure which will compute the description from a
    ///                  builder. We compute descriptions in this fashion in
    ///                  order to take advantage of type inference to make it
    ///                  easy to have type safe accessors for the payload
    ///                  properties.
    ///
    /// The intended use is to support a convenient inline syntax for defining
    /// new diagnostics, for example:
    ///     
    ///     struct TooFewLives: DiagnosticData {
    ///         static var id = DiagnosticID(
    ///             type: TooFewLives.self,
    ///             name: "org.swift.diags.too-few-lives",
    ///             description: { $0 <<< "cannot create a cat with" <<< { $0.count } <<< "lives" }
    ///         )
    ///     
    ///         let count: Int
    ///     }
    public init<T>(
        type: T.Type,
        name: String,
        defaultBehavior: Diagnostic.Behavior = .error,
        description buildDescription: (DiagnosticDescriptionBuilder<T>) -> Void
    ) {
        self.name = name
        self.description = DiagnosticDescriptionBuilder<T>().build(buildDescription)
        self.defaultBehavior = defaultBehavior
    }
}

/// The payload of a diagnostic.
public protocol DiagnosticData: CustomStringConvertible {
    /// The identifier of the diagnostic this payload corresponds to.
    static var id: DiagnosticID { get }
}

extension DiagnosticData {
    public var description: String {
        return localizedDescription(for: self)
    }
}

/// The location of the diagnostic.
public protocol DiagnosticLocation {
    /// The human readable summary description for the location.
    var localizedDescription: String { get }
}

public struct Diagnostic {
    public typealias Location = DiagnosticLocation

    /// The behavior associated with this diagnostic.
    public enum Behavior {
        /// An error which will halt the operation.
        case error

        /// A warning, but which will not halt the operation.
        case warning

        /// An informational message.
        case note

        /// A diagnostic which was ignored.
        case ignored
    }

    /// The diagnostic identifier.
    public var id: DiagnosticID {
        return type(of: data).id
    }

    /// The diagnostic's behavior.
    public let behavior: Behavior

    /// The conceptual location of this diagnostic.
    ///
    /// This could refer to a concrete location in a file, for example, but it
    /// could also refer to an abstract location such as "the Git repository at
    /// this URL".
    public let location: Location

    /// The information on the actual diagnostic.
    public let data: DiagnosticData

    // FIXME: Need additional attachment mechanism (backtrace, etc.), or
    // extensible handlers (e.g., interactive diagnostics).

    /// Create a new diagnostic.
    ///
    /// - Parameters:
    ///   - location: The abstract location of the issue which triggered the diagnostic.
    ///   - parameters: The parameters to the diagnostic conveying additional information.
    /// - Precondition: The bindings must match those declared by the identifier.
    public init(location: Location, data: DiagnosticData) {
        // FIXME: Implement behavior overrides.
        self.behavior = type(of: data).id.defaultBehavior
        self.location = location
        self.data = data
    }

    /// The human readable summary description for the diagnostic.
    public var localizedDescription: String {
        return Basic.localizedDescription(for: data)
    }
}

/// A scope of diagnostics.
///
/// The scope provides aggregate information on all of the diagnostics which can
/// be produced by a component.
public protocol DiagnosticsScope {
    /// Get a URL for more information on a particular diagnostic ID.
    ///
    /// This is intended to be used to provide verbose descriptions for diagnostics.
    ///
    /// - Parameters:
    ///   - id: The diagnostic ID to describe.
    ///   - diagnostic: If provided, a specific diagnostic to describe.
    /// - Returns: If available, a URL which will give more information about
    /// the diagnostic.
    func url(describing id: DiagnosticID, for diagnostic: Diagnostic?) -> String?
}

public class DiagnosticsEngine: CustomStringConvertible {
    /// The diagnostics produced by the engine.
    public var diagnostics: [Diagnostic] = []

    public var hasErrors: Bool {
        return diagnostics.contains(where: { $0.behavior == .error })
    }
    
    public init() {
    }

    public func emit(data: DiagnosticData, location: DiagnosticLocation) {
        diagnostics.append(Diagnostic(location: location, data: data))
    }

    /// Merges contents of given engine.
    public func merge(_ engine: DiagnosticsEngine) {
        for diagnostic in engine.diagnostics {
            emit(data: diagnostic.data, location: diagnostic.location)
        }
    }

    public var description: String {
        let stream = BufferedOutputByteStream()
        stream <<< "["
        for diag in diagnostics {
            stream <<< diag.localizedDescription <<< ", "
        }
        stream <<< "]"
        return stream.bytes.asString!
    }
}

/// Returns localized description of a diagnostic data.
fileprivate func localizedDescription(for data: DiagnosticData) -> String {
    var result = ""
    for (i, fragment) in type(of: data).id.description.enumerated() {
        if i != 0 {
            result += " "
        }

        switch fragment {
        case let .literalItem(string, _):
            result += string
        case let .substitutionItem(accessor, _):
            result += accessor(data).diagnosticDescription
        }
    }
    return result
}
