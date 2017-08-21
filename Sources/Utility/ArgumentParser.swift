/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Foundation
import func POSIX.exit

/// Errors which may be encountered when running argument parser.
public enum ArgumentParserError: Swift.Error {

    /// An unknown option is encountered.
    case unknownOption(String)

    /// The value of an argument is invalid.
    case invalidValue(argument: String, error: ArgumentConversionError)

    /// Expected a value from the option.
    case expectedValue(option: String)

    /// An unexpected positional argument encountered.
    case unexpectedArgument(String)

    /// Expected these positional arguments but not found.
    case expectedArguments(ArgumentParser, [String])
}

extension ArgumentParserError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknownOption(let option):
            return "unknown option \(option); use --help to list available options"
        case .invalidValue(let argument, let error):
            return "\(error) for argument \(argument); use --help to print usage"
        case .expectedValue(let option):
            return "option \(option) requires a value; provide a value using '\(option) <value>' or '\(option)=<value>'"
        case .unexpectedArgument(let argument):
            return "unexpected argument \(argument); use --help to list available arguments"
        case .expectedArguments(_, let arguments):
            return "expected arguments: \(arguments.joined(separator: ", "))"
        }
    }
}

/// Conversion errors that can be returned from `ArgumentKind`'s failable
/// initializer.
public enum ArgumentConversionError: Swift.Error {

    /// The value is unkown.
    case unknown(value: String)

    /// The value could not be converted to the target type.
    case typeMismatch(value: String, expectedType: Any.Type)

    /// Custom reason for conversion failure.
    case custom(String)
}

extension ArgumentConversionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown(let value):
            return "unknown value '\(value)'"
        case .typeMismatch(let value, let expectedType):
            return "'\(value)' is not convertible to \(expectedType)"
        case .custom(let reason):
            return reason
        }
    }
}

extension ArgumentConversionError: Equatable {
    public static func ==(lhs: ArgumentConversionError, rhs: ArgumentConversionError) -> Bool {
        switch (lhs, rhs) {
        case (.unknown(let lhsValue), .unknown(let rhsValue)):
            return lhsValue == rhsValue
        case (.unknown, _):
            return false
        case (.typeMismatch(let lhsValue, let lhsType), .typeMismatch(let rhsValue, let rhsType)):
            return lhsValue == rhsValue && lhsType == rhsType
        case (.typeMismatch, _):
            return false
        case (.custom(let lhsReason), .custom(let rhsReason)):
            return lhsReason == rhsReason
        case (.custom, _):
            return false
        }
    }
}

/// Different shells for which we can generate shell scripts.
public enum Shell: String, StringEnumArgument {
    case bash
    case zsh

    public static var completion: ShellCompletion = .values([
        (bash.rawValue, "generate completion script for Bourne-again shell"),
        (zsh.rawValue, "generate completion script for Z shell"),
    ])
}

/// Various shell completions modes supplied by ArgumentKind.
///
/// - none:        Offers no completions at all; e.g. for string identifier
/// - unspecified: No specific completions, will offer tool's completions
/// - filename:    Offers filename completions
/// - values:      Offers completions from predefined list. A description
///                can be provided which is shown in some shells, like zsh.
public enum ShellCompletion {
    case none
    case unspecified
    case filename
    case values([(value: String, description: String)])
}

/// A protocol representing the possible types of arguments.
///
/// Conforming to this protocol will qualify the type to act as
/// positional and option arguments in the argument parser.
public protocol ArgumentKind {
    /// Throwable convertion initializer.
    init(argument: String) throws

    /// Type of shell completion to provide for this argument.
    static var completion: ShellCompletion { get }
}

// MARK: - ArgumentKind conformance for common types

extension String: ArgumentKind {
    public init(argument: String) throws {
        self = argument
    }

    public static let completion: ShellCompletion = .none
}

extension Int: ArgumentKind {
    public init(argument: String) throws {
        guard let int = Int(argument) else {
            throw ArgumentConversionError.typeMismatch(value: argument, expectedType: Int.self)
        }

        self = int
    }

    public static let completion: ShellCompletion = .none
}

extension Bool: ArgumentKind {
    public init(argument: String) throws {
        switch argument {
        case "true":
            self = true
        case "false":
            self = false
        default:
            throw ArgumentConversionError.unknown(value: argument)
        }
    }

    public static var completion: ShellCompletion = .unspecified
}

/// A protocol which implements ArgumentKind for string initializable enums.
///
/// Conforming to this protocol will automatically make an enum with is
/// String initializable conform to ArgumentKind.
public protocol StringEnumArgument: ArgumentKind {
    init?(rawValue: String)
}

extension StringEnumArgument {
    public init(argument: String) throws {
        guard let value = Self.init(rawValue: argument) else {
            throw ArgumentConversionError.unknown(value: argument)
        }

        self = value
    }
}

/// An argument representing a path (file / directory).
///
/// The path is resolved in the current working directory.
public struct PathArgument: ArgumentKind {
    public let path: AbsolutePath

    public init(argument: String) throws {
        // FIXME: This should check for invalid paths.
        path = AbsolutePath(argument, relativeTo: currentWorkingDirectory)
    }

    public static var completion: ShellCompletion = .filename
}

/// An enum representing the strategy to parse argument values.
public enum ArrayParsingStrategy {
    /// Will parse only the next argument and append all values together: `-Xcc -Lfoo -Xcc -Lbar`.
    case oneByOne

    /// Will parse all values up to the next option argument: `--files file1 file2 --verbosity 1`.
    case upToNextOption

    /// Will parse all remaining arguments, usually for executable commands: `swift run exe --option 1`.
    case remaining

    /// Function that parses the current arguments iterator based on the strategy
    /// and returns the parsed values.
    func parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        var values: [ArgumentKind] = []

        switch self {
        case .oneByOne:
            guard let nextArgument = parser.next() else  {
                throw ArgumentParserError.expectedValue(option: parser.currentArgument)
            }

            try values.append(kind.init(argument: nextArgument))

        case .upToNextOption:
            /// Iterate over arguments until the end or an optional argument
            while let nextArgument = parser.peek(), isPositional(argument: nextArgument) {
                /// We need to call next to consume the argument. The peek above did not.
                _ = parser.next()
                try values.append(kind.init(argument: nextArgument))
            }

        case .remaining:
            while let nextArgument = parser.next() {
                try values.append(kind.init(argument: nextArgument))
            }
        }
        
        return values
    }
}

/// A protocol representing positional or options argument.
protocol ArgumentProtocol: Hashable {
    /// The argument kind of this argument for eg String, Bool etc.
    ///
    // FIXME: This should be constrained to ArgumentKind but Array can't conform
    // to it: `extension of type 'Array' with constraints cannot have an
    // inheritance clause`.
    associatedtype ArgumentKindTy

    /// Name of the argument which will be parsed by the parser.
    var name: String { get }

    /// Short name of the argument, this is usually used in options arguments
    /// for a short names for e.g: `--help` -> `-h`.
    var shortName: String? { get }

    /// The parsing strategy to adopt when parsing values.
    var strategy: ArrayParsingStrategy { get }

    /// Defines is the argument is optional
    var isOptional: Bool { get }

    /// The usage text associated with this argument. Used to generate complete help string.
    var usage: String? { get }

    /// Parses and returns the argument values from the parser.
    ///
    // FIXME: Because `ArgumentKindTy`` can't conform to `ArgumentKind`, this
    // function has to be provided a kind (which will be different from
    // ArgumentKindTy for arrays). Once the generics feature exists we can
    // improve this API.
    func parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind]
}

extension ArgumentProtocol {
    // MARK: - Conformance for Hashable

    public var hashValue: Int {
        return name.hashValue
    }

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        return lhs.name == rhs.name && lhs.usage == rhs.usage
    }
}

/// Returns true if the given argument does not starts with '-' i.e. it is
/// a positional argument, otherwise it is an options argument.
fileprivate func isPositional(argument: String) -> Bool {
    return !argument.hasPrefix("-")
}

/// A class representing option arguments. These are optional arguments which may
/// or may not be provided in the command line. They are always prefixed by their
/// name. For e.g. --verbosity true.
public final class OptionArgument<Kind>: ArgumentProtocol {
    typealias ArgumentKindTy = Kind

    let name: String

    let shortName: String?

    // Option arguments are always optional.
    var isOptional: Bool { return true }

    let strategy: ArrayParsingStrategy

    let usage: String?

    init(name: String, shortName: String?, strategy: ArrayParsingStrategy, usage: String?) {
        precondition(!isPositional(argument: name))
        self.name = name
        self.shortName = shortName
        self.strategy = strategy
        self.usage = usage
    }

    func parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        do {
            return try _parse(kind, with: &parser)
        } catch let conversionError as ArgumentConversionError {
            throw ArgumentParserError.invalidValue(argument: name, error: conversionError)
        }
    }

    func _parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        // When we have an associated value, we ignore the strategy and only
        // parse that value.
        if let associatedArgument = parser.associatedArgumentValue {
            return try [kind.init(argument: associatedArgument)]
        }

        // As a special case, Bool options don't consume arguments.
        if kind == Bool.self && strategy == .oneByOne {
            return [true]
        }

        let values = try strategy.parse(kind, with: &parser)
        guard !values.isEmpty else {
            throw ArgumentParserError.expectedValue(option: name)
        }

        return values
    }
}

/// A class representing positional arguments. These arguments must be present
/// and in the same order as they are added in the parser.
public final class PositionalArgument<Kind>: ArgumentProtocol {

    typealias ArgumentKindTy = Kind

    let name: String

    // Postional arguments don't need short names.
    var shortName: String? { return nil }

    let strategy: ArrayParsingStrategy

    let isOptional: Bool

    let usage: String?

    init(name: String, strategy: ArrayParsingStrategy, optional: Bool, usage: String?) {
        precondition(isPositional(argument: name))
        self.name = name
        self.strategy = strategy
        self.isOptional = optional
        self.usage = usage
    }

    func parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        do {
            return try _parse(kind, with: &parser)
        } catch let conversionError as ArgumentConversionError {
            throw ArgumentParserError.invalidValue(argument: name, error: conversionError)
        }
    }

    func _parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        let value = try kind.init(argument: parser.currentArgument)

        var values = [value]

        switch strategy {
        case .oneByOne:
            // We shouldn't apply the strategy with `.oneByOne` because we
            // already have one, the parsed `parser.currentArgument`.
            break

        case .upToNextOption, .remaining:
            try values.append(contentsOf: strategy.parse(kind, with: &parser))
        }

        return values
    }
}

/// A type-erased argument.
///
/// Note: Only used for argument parsing purpose.
final class AnyArgument: ArgumentProtocol, CustomStringConvertible {
    typealias ArgumentKindTy = Any

    let name: String

    let shortName: String?

    let strategy: ArrayParsingStrategy

    let isOptional: Bool

    let usage: String?

    /// The argument kind this holds, used while initializing that argument.
    let kind: ArgumentKind.Type

    /// True if the argument kind is of array type.
    let isArray: Bool

    /// A type-erased wrapper around the argument's `parse` function.
    private let parseClosure: (ArgumentKind.Type, inout ArgumentParserProtocol) throws -> [ArgumentKind]

    init<T: ArgumentProtocol>(_ argument: T) {
        self.kind = T.ArgumentKindTy.self as! ArgumentKind.Type
        self.name = argument.name
        self.shortName = argument.shortName
        self.strategy = argument.strategy
        self.isOptional = argument.isOptional
        self.usage = argument.usage
        self.parseClosure = argument.parse(_:with:)
        isArray = false
    }

    /// Initializer for array arguments.
    init<T: ArgumentProtocol>(_ argument: T) where T.ArgumentKindTy: Sequence {
        self.kind = T.ArgumentKindTy.Element.self as! ArgumentKind.Type
        self.name = argument.name
        self.shortName = argument.shortName
        self.strategy = argument.strategy
        self.isOptional = argument.isOptional
        self.usage = argument.usage
        self.parseClosure = argument.parse(_:with:)
        isArray = true
    }

    var description: String {
        return "Argument(\(name))"
    }

    func parse(_ kind: ArgumentKind.Type, with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        return try self.parseClosure(kind, &parser)
    }

    func parse(with parser: inout ArgumentParserProtocol) throws -> [ArgumentKind] {
        return try self.parseClosure(self.kind, &parser)
    }
}

/// Argument parser protocol passed in initializers of ArgumentKind to manipulate
/// parser as needed by the argument.
///
// FIXME: We probably don't need this protocol anymore and should convert this to a class.
public protocol ArgumentParserProtocol {
    /// The current argument being parsed.
    var currentArgument: String { get }

    /// The associated value in a `--foo=bar` style argument.
    var associatedArgumentValue: String? { get }

    /// Provides (consumes) and returns the next argument. Returns `nil` if there are not arguments left.
    mutating func next() -> String?

    /// Peek at the next argument without consuming it.
    func peek() -> String?
}

/// Argument parser struct responsible to parse the provided array of arguments
/// and return the parsed result.
public final class ArgumentParser {

    /// A class representing result of the parsed arguments.
    public class Result: CustomStringConvertible {
        /// Internal representation of arguments mapped to their values.
        private var results = [AnyArgument: Any]()

        /// Result of the parent parent parser, if any.
        private var parentResult: Result?

        /// Reference to the parser this result belongs to.
        private let parser: ArgumentParser

        /// The subparser command chosen.
        fileprivate var subparser: String?

        /// Create a result with a parser and parent result.
        init(parser: ArgumentParser, parent: Result?) {
            self.parser = parser
            self.parentResult = parent
        }

        /// Adds a result.
        ///
        /// - Parameters:
        ///     - values: The associated values of the argument.
        ///     - argument: The argument for which this result is being added.
        /// - Note:
        ///     While it may seem more fragile to use an array as input in the
        ///     case of single-value arguments, this design choice allows major
        ///     simplifications in the parsing code.
        fileprivate func add(_ values: [ArgumentKind], for argument: AnyArgument) throws {
            if argument.isArray {
                var array = results[argument] as? [ArgumentKind] ?? []
                array.append(contentsOf: values)
                results[argument] = array
            } else {
                // We expect only one value for non-array arguments.
                guard let value = values.only else {
                    assertionFailure()
                    return
                }
                results[argument] = value
            }
        }

        /// Get an option argument's value from the results.
        ///
        /// Since the options are optional, their result may or may not be present.
        public func get<T>(_ argument: OptionArgument<T>) -> T? {
            return (results[AnyArgument(argument)] as? T) ?? parentResult?.get(argument)
        }

        /// Array variant for option argument's get(_:).
        public func get<T>(_ argument: OptionArgument<[T]>) -> [T]? {
            return (results[AnyArgument(argument)] as? [T]) ?? parentResult?.get(argument)
        }

        /// Get a positional argument's value.
        public func get<T>(_ argument: PositionalArgument<T>) -> T? {
            return results[AnyArgument(argument)] as? T
        }

        /// Array variant for positional argument's get(_:).
        public func get<T>(_ argument: PositionalArgument<[T]>) -> [T]? {
            return results[AnyArgument(argument)] as? [T]
        }

        /// Get the subparser which was chosen for the given parser.
        public func subparser(_ parser: ArgumentParser) -> String? {
            if parser === self.parser {
                return subparser
            }
            return parentResult?.subparser(parser)
        }

        public var description: String {
            var description = "ArgParseResult(\(results))"
            if let parent = parentResult {
                description += " -> " + parent.description
            }
            return description
        }
    }

    /// The mapping of subparsers to their subcommand.
    private(set) var subparsers: [String: ArgumentParser] = [:]

    /// List of arguments added to this parser.
    private(set) var optionArguments: [AnyArgument] = []
    private(set) var positionalArguments: [AnyArgument] = []

    // If provided, will be substituted instead of arg0 in usage text.
    let commandName: String?

    /// Usage string of this parser.
    let usage: String

    /// Overview text of this parser.
    let overview: String

    /// If this parser is a subparser.
    private let isSubparser: Bool

    /// Boolean specifying if the parser can accept further positional
    /// arguments (false if it already has a positional argument with
    /// `isOptional` set to `true` or strategy set to `.remaining`).
    private var canAcceptPositionalArguments: Bool = true

    /// Create an argument parser.
    ///
    /// - Parameters:
    ///   - commandName: If provided, this will be substitued in "usage" line of the generated usage text.
    ///   Otherwise, first command line argument will be used.
    ///   - usage: The "usage" line of the generated usage text.
    ///   - overview: The "overview" line of the generated usage text.
    public init(commandName: String? = nil, usage: String, overview: String) {
        self.isSubparser = false
        self.commandName = commandName
        self.usage = usage
        self.overview = overview
    }

    /// Create a subparser with its help text.
    private init(subparser overview: String) {
        self.isSubparser = true
        self.commandName = nil
        self.usage = ""
        self.overview = overview
    }

    /// Adds an option to the parser.
    public func add<T: ArgumentKind>(
        option: String,
        shortName: String? = nil,
        kind: T.Type,
        usage: String? = nil
    ) -> OptionArgument<T> {
        assert(!optionArguments.contains(where: { $0.name == option }), "Can not define an option twice")

        let argument = OptionArgument<T>(name: option, shortName: shortName, strategy: .oneByOne, usage: usage)
        optionArguments.append(AnyArgument(argument))
        return argument
    }

    /// Adds an array argument type.
    public func add<T: ArgumentKind>(
        option: String,
        shortName: String? = nil,
        kind: [T].Type,
        strategy: ArrayParsingStrategy = .upToNextOption,
        usage: String? = nil
    ) -> OptionArgument<[T]> {
        assert(!optionArguments.contains(where: { $0.name == option }), "Can not define an option twice")

        let argument = OptionArgument<[T]>(name: option, shortName: shortName, strategy: strategy, usage: usage)
        optionArguments.append(AnyArgument(argument))
        return argument
    }

    /// Adds an argument to the parser.
    ///
    /// Note: Only one positional argument is allowed if optional setting is enabled.
    public func add<T: ArgumentKind>(
        positional: String,
        kind: T.Type,
        optional: Bool = false,
        usage: String? = nil
    ) -> PositionalArgument<T> {
        precondition(subparsers.isEmpty, "Positional arguments are not supported with subparsers")
        precondition(canAcceptPositionalArguments, "Can not accept more positional arguments")

        if optional {
            canAcceptPositionalArguments = false
        }

        let argument = PositionalArgument<T>(name: positional, strategy: .oneByOne, optional: optional, usage: usage)
        positionalArguments.append(AnyArgument(argument))
        return argument
    }

    /// Adds an argument to the parser.
    ///
    /// Note: Only one multiple-value positional argument is allowed.
    public func add<T: ArgumentKind>(
        positional: String,
        kind: [T].Type,
        optional: Bool = false,
        strategy: ArrayParsingStrategy = .upToNextOption,
        usage: String? = nil
    ) -> PositionalArgument<[T]> {
        precondition(subparsers.isEmpty, "Positional arguments are not supported with subparsers")
        precondition(canAcceptPositionalArguments, "Can not accept more positional arguments")

        if optional || strategy == .remaining {
            canAcceptPositionalArguments = false
        }

        let argument = PositionalArgument<[T]>(name: positional, strategy: strategy, optional: optional, usage: usage)
        positionalArguments.append(AnyArgument(argument))
        return argument
    }

    /// Add a parser with a subcommand name and its corresponding overview.
    @discardableResult
    public func add(subparser command: String, overview: String) -> ArgumentParser {
        precondition(positionalArguments.isEmpty, "Subparsers are not supported with positional arguments")
        let parser = ArgumentParser(subparser: overview)
        subparsers[command] = parser
        return parser
    }

    // MARK: - Parsing

    /// A wrapper struct to pass to the ArgumentKind initializers.
    struct Parser: ArgumentParserProtocol {
        let currentArgument: String
        private(set) var associatedArgumentValue: String?

        /// The iterator used to iterate arguments.
        fileprivate var argumentsIterator: IndexingIterator<[String]>

        init(associatedArgumentValue: String?, argumentsIterator: IndexingIterator<[String]>, currentArgument: String) {
            self.associatedArgumentValue = associatedArgumentValue
            self.argumentsIterator = argumentsIterator
            self.currentArgument = currentArgument
        }

        mutating func next() -> String? {
            return argumentsIterator.next()
        }

        func peek() -> String? {
            var iteratorCopy = argumentsIterator
            let nextArgument = iteratorCopy.next()
            return nextArgument
        }
    }

    /// Parses the provided array and return the result.
    public func parse(_ arguments: [String] = []) throws -> Result {
        return try parse(arguments, parent: nil)
    }

    private func parse(_ arguments: [String] = [], parent: Result?) throws -> Result {
        let result = Result(parser: self, parent: parent)
        // Create options map to quickly look up the arguments.
        let optionsTuple = optionArguments.flatMap({ option -> [(String, AnyArgument)] in
            var result = [(option.name, option)]
            // Add the short names too, if we have them.
            if let shortName = option.shortName {
                result += [(shortName, option)]
            }
            return result
        })
        let optionsMap = Dictionary(items: optionsTuple)

        // Create iterators.
        var positionalArgumentIterator = positionalArguments.makeIterator()
        var argumentsIterator = arguments.makeIterator()

        while let argumentString = argumentsIterator.next() {
            let argument: AnyArgument
            let parser: Parser

            // If argument is help then just print usage and exit.
            if argumentString == "-h" || argumentString == "-help" || argumentString == "--help" {
                printUsage(on: stdoutStream)
                exit(0)
            } else if isPositional(argument: argumentString) {
                /// If this parser has subparsers, we allow only one positional argument which is the subparser command.
                if !subparsers.isEmpty {
                    // Make sure this argument has a subparser.
                    guard let subparser = subparsers[argumentString] else {
                        throw ArgumentParserError.expectedArguments(self, Array(subparsers.keys))
                    }
                    // Save which subparser was chosen.
                    result.subparser = argumentString
                    // Parse reset of the arguments with the subparser.
                    return try subparser.parse(Array(argumentsIterator), parent: result)
                }

                // Get the next positional argument we are expecting.
                guard let positionalArgument = positionalArgumentIterator.next() else {
                    throw ArgumentParserError.unexpectedArgument(argumentString)
                }

                argument = positionalArgument
                parser = Parser(
                    associatedArgumentValue: nil,
                    argumentsIterator: argumentsIterator,
                    currentArgument: argumentString)
            } else {
                let (argumentString, value) = argumentString.split(around: "=")
                // Get the corresponding option for the option argument.
                guard let optionArgument = optionsMap[argumentString] else {
                    throw ArgumentParserError.unknownOption(argumentString)
                }

                argument = optionArgument
                parser = Parser(
                    associatedArgumentValue: value,
                    argumentsIterator: argumentsIterator,
                    currentArgument: argumentString)
            }

            // Update results.
            var parserProtocol = parser as ArgumentParserProtocol
            let values = try argument.parse(with: &parserProtocol)
            try result.add(values, for: argument)
            // Restore the argument iterator state.
            argumentsIterator = (parserProtocol as! Parser).argumentsIterator
        }
        // Report if there are any non-optional positional arguments left which were not present in the arguments.
        let leftOverArguments = Array(positionalArgumentIterator)
        if leftOverArguments.contains(where: { !$0.isOptional }) {
            throw ArgumentParserError.expectedArguments(self, leftOverArguments.map({ $0.name }))
        }
        return result
    }

    /// Prints usage text for this parser on the provided stream.
    public func printUsage(on stream: OutputByteStream) {
        /// Space settings.
        let maxWidthDefault = 24
        let padding = 2

        let maxWidth: Int
        // Figure out the max width based on argument length or choose the default width if max width is longer
        // than the default width.
        if let maxArgument = (positionalArguments + optionArguments).map({ $0.name.count }).max(),
            maxArgument < maxWidthDefault {
            maxWidth = maxArgument + padding + 1
        } else {
            maxWidth = maxWidthDefault
        }

        /// Prints an argument on a stream if it has usage.
        func print(formatted argument: String, usage: String, on stream: OutputByteStream) {
            // Start with a new line and add some padding.
            stream <<< "\n" <<< Format.asRepeating(string: " ", count: padding)
            let count = argument.count
            // If the argument name is more than the set width take the whole
            // line for it, otherwise we can fit everything in one line.
            if count >= maxWidth - padding {
                stream <<< argument <<< "\n"
                // Align full width because we on a new line.
                stream <<< Format.asRepeating(string: " ", count: maxWidth + padding)
            } else {
                stream <<< argument
                // Align to the remaining empty space we have.
                stream <<< Format.asRepeating(string: " ", count: maxWidth - count)
            }
            stream <<< usage
        }

        stream <<< "OVERVIEW: " <<< overview

        // We only print command usage for top level parsers.
        if !isSubparser {
            stream <<< "\n\n"
            // Get the binary name from command line arguments.
            let defaultCommandName = CommandLine.arguments[0].components(separatedBy: "/").last!
            stream <<< "USAGE: " <<< (commandName ?? defaultCommandName) <<< " " <<< usage
        }

        if optionArguments.count > 0 {
            stream <<< "\n\n"
            stream <<< "OPTIONS:"
            for argument in optionArguments.lazy.sorted(by: {$0.name < $1.name}) {
                guard let usage = argument.usage else { continue }
                // Create name with its shortname, if available.
                let name = [argument.name, argument.shortName].flatMap({ $0 }).joined(separator: ", ")
                print(formatted: name, usage: usage, on: stream)
            }

            // Print help option, if this is a top level command.
            if !isSubparser {
                print(formatted: "--help", usage: "Display available options", on: stream)
            }
        }

        if subparsers.keys.count > 0 {
            stream <<< "\n\n"
            stream <<< "SUBCOMMANDS:"
            for (command, parser) in subparsers.sorted(by: { $0.key < $1.key }) {
                // Special case for hidden subcommands.
                guard !parser.overview.isEmpty else { continue }
                print(formatted: command, usage: parser.overview, on: stream)
            }
        }

        if positionalArguments.count > 0 {
            stream <<< "\n\n"
            stream <<< "COMMANDS:"
            for argument in positionalArguments.lazy.sorted(by: {$0.name < $1.name}) {
                guard let usage = argument.usage else { continue }
                print(formatted: argument.name, usage: usage, on: stream)
            }
        }
        stream <<< "\n"
        stream.flush()
    }
}

/// A class to bind ArgumentParser's arguments to an option structure.
public final class ArgumentBinder<Options> {
    /// The signature of body closure.
    private typealias BodyClosure = (inout Options, ArgumentParser.Result) -> Void

    /// This array holds the closures which should be executed to fill the options structure.
    private var bodies = [BodyClosure]()

    /// Create a binder.
    public init() {
    }

    /// Bind an option argument.
    public func bind<T>(
        option: OptionArgument<T>,
        to body: @escaping (inout Options, T) -> Void
    ) {
        addBody {
            guard let result = $1.get(option) else { return }
            body(&$0, result)
        }
    }

    /// Bind an array option argument.
    public func bindArray<T>(
        option: OptionArgument<[T]>,
        to body: @escaping (inout Options, [T]) -> Void
    ) {
        addBody {
            guard let result = $1.get(option) else { return }
            body(&$0, result)
        }
    }

    /// Bind a positional argument.
    public func bind<T>(
        positional: PositionalArgument<T>,
        to body: @escaping (inout Options, T) -> Void
    ) {
        addBody {
            // All the positional argument will always be present.
            guard let result = $1.get(positional) else { return }
            body(&$0, result)
        }
    }

    /// Bind an array positional argument.
    public func bindArray<T>(
        positional: PositionalArgument<[T]>,
        to body: @escaping (inout Options, [T]) -> Void
    ) {
        addBody {
            // All the positional argument will always be present.
            guard let result = $1.get(positional) else { return }
            body(&$0, result)
        }
    }

    /// Bind two positional arguments.
    public func bindPositional<T, U>(
        _ first: PositionalArgument<T>,
        _ second: PositionalArgument<U>,
        to body: @escaping (inout Options, T, U) -> Void
    ) {
        addBody {
            // All the positional arguments will always be present.
            guard let first = $1.get(first) else { return }
            guard let second = $1.get(second) else { return }
            body(&$0, first, second)
        }
    }

    /// Bind three positional arguments.
    public func bindPositional<T, U, V>(
        _ first: PositionalArgument<T>,
        _ second: PositionalArgument<U>,
        _ third: PositionalArgument<V>,
        to body: @escaping (inout Options, T, U, V) -> Void
    ) {
        addBody {
            // All the positional arguments will always be present.
            guard let first = $1.get(first) else { return }
            guard let second = $1.get(second) else { return }
            guard let third = $1.get(third) else { return }
            body(&$0, first, second, third)
        }
    }

    /// Bind two options.
    public func bind<T, U>(
        _ first: OptionArgument<T>,
        _ second: OptionArgument<U>,
        to body: @escaping (inout Options, T?, U?) -> Void
    ) {
        addBody {
            body(&$0, $1.get(first), $1.get(second))
        }
    }

    /// Bind three options.
    public func bind<T, U, V>(
        _ first: OptionArgument<T>,
        _ second: OptionArgument<U>,
        _ third: OptionArgument<V>,
        to body: @escaping (inout Options, T?, U?, V?) -> Void
    ) {
        addBody {
            body(&$0, $1.get(first), $1.get(second), $1.get(third))
        }
    }

    /// Bind two array options.
    public func bindArray<T, U>(
        _ first: OptionArgument<[T]>,
        _ second: OptionArgument<[U]>,
        to body: @escaping (inout Options, [T], [U]) -> Void
    ) {
        addBody {
            body(&$0, $1.get(first) ?? [], $1.get(second) ?? [])
        }
    }

    /// Add three array option and call the final closure with their values.
    public func bindArray<T, U, V>(
        _ first: OptionArgument<[T]>,
        _ second: OptionArgument<[U]>,
        _ third: OptionArgument<[V]>,
        to body: @escaping (inout Options, [T], [U], [V]) -> Void
     ) {
        addBody {
            body(&$0, $1.get(first) ?? [], $1.get(second) ?? [], $1.get(third) ?? [])
        }
    }

    /// Bind a subparser.
    public func bind(
        parser: ArgumentParser,
        to body: @escaping (inout Options, String) -> Void
    ) {
        addBody {
            guard let result = $1.subparser(parser) else { return }
            body(&$0, result)
        }
    }

    /// Appends a closure to bodies array.
    private func addBody(_ body: @escaping BodyClosure) {
        bodies.append(body)
    }

    /// Fill the result into the options structure.
    public func fill(_ result: ArgumentParser.Result, into options: inout Options) {
        bodies.forEach { $0(&options, result) }
    }
}
