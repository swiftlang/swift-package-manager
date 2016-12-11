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
///
/// - unknownOption:      An unknown option is encountered.
/// - unknownValue:       The value of an option is unknown.
/// - expectedValue:      Expected a value from the option.
/// - unexpectedArgument: An unexpected positional argument encountered.
/// - expectedArguments:  Expected these positional arguments but not found.
/// - typeMismatch:       The type of option's value doesn't match.
public enum ArgumentParserError: Swift.Error {
    case unknownOption(String)
    case unknownValue(option: String, value: String)
    case expectedValue(option: String)
    case unexpectedArgument(String)
    case expectedArguments(ArgumentParser, [String])
    case typeMismatch(String)
}

/// A protocol representing the possible types of arguments.
///
/// Conforming to this protocol will qualify the type to act as
/// positional and option arguments in the argument parser.
public protocol ArgumentKind {
    /// This will be called when the option is encountered while parsing.
    ///
    /// Call methods on the passed parser to manipulate parser as needed.
    init(parser: inout ArgumentParserProtocol) throws

    /// This will be called for positional arguments with the value discovered.
    init?(arg: String)
}

// MARK:- ArgumentKind conformance for common types

extension String: ArgumentKind {
    public init?(arg: String) {
        self = arg
    }

    public init(parser: inout ArgumentParserProtocol) throws {
        self = try parser.associatedArgumentValue ?? parser.next()
    }
}

extension Int: ArgumentKind {
    public init?(arg: String) {
        self.init(arg)
    }

    public init(parser: inout ArgumentParserProtocol) throws {
        let arg = try parser.associatedArgumentValue ?? parser.next()
        // Not every string can be converted into an integer.
        guard let intValue = Int(arg) else {
            throw ArgumentParserError.typeMismatch("\(arg) is not convertible to Int")
        }
        self = intValue
    }
}

extension Bool: ArgumentKind {
    public init?(arg: String) {
        self = true
    }

    public init(parser: inout ArgumentParserProtocol) throws {
        if let associatedValue = parser.associatedArgumentValue {
            switch associatedValue {
            case "true": self = true
            case "false": self = false
            default: throw ArgumentParserError.unknownValue(option: parser.currentArgument, value: associatedValue)
            }
        } else {
            // We don't need to pop here because presence of the option
            // is enough to indicate that the bool value is true.
            self = true
        }
    }
}

/// A protocol which implements ArgumentKind for string initializable enums.
///
/// Conforming to this protocol will automatically make an enum with is
/// String initializable conform to ArgumentKind.
public protocol StringEnumArgument: ArgumentKind {
    init?(rawValue: String)
}

extension StringEnumArgument {
    public init(parser: inout ArgumentParserProtocol) throws {
        let arg = try parser.associatedArgumentValue ?? parser.next()
        guard let obj = Self.init(arg: arg) else {
            throw ArgumentParserError.unknownValue(option: parser.currentArgument, value: arg)
        }
        self = obj
    }

    public init?(arg: String) {
        self.init(rawValue: arg)
    }
}


/// An argument representing a path (file / directory).
///
/// The path is resolved in the current working directory.
public struct PathArgument: ArgumentKind {
    public let path: AbsolutePath

    public init?(arg: String) {
        path = AbsolutePath(arg, relativeTo: currentWorkingDirectory)
    }

    public init(parser: inout ArgumentParserProtocol) throws {
        path = AbsolutePath(try parser.associatedArgumentValue ?? parser.next(), relativeTo: currentWorkingDirectory)
    }
}

/// A protocol representing positional or options argument.
protocol ArgumentProtocol: Hashable {
    /// The argument kind of this argument for eg String, Bool etc.
    // FIXME: This should be constrained to ArgumentKind but Array can't conform to it:
    // `extension of type 'Array' with constraints cannot have an inheritance clause`.
    associatedtype ArgumentKindTy 

    /// Name of the argument which will be parsed by the parser.
    var name: String { get }

    /// Short name of the argument, this is usually used in options arguments
    /// for a short names for e.g: `--help` -> `-h`.
    var shortName: String? { get }

    /// The usage text associated with this argument. Used to generate complete help string.
    var usage: String? { get }
}

extension ArgumentProtocol {
    // MARK:- Conformance for Hashable

    public var hashValue: Int {
        return name.hashValue
    }

    public static func ==(_ lhs: Self, _ rhs: Self) -> Bool {
        return lhs.name == rhs.name && lhs.usage == rhs.usage
    }
}

/// Returns true if the given argument does not starts with '-' i.e. it is a positional argument,
/// otherwise it is an options argument.
fileprivate func isPositional(argument: String) -> Bool {
    return !argument.hasPrefix("-")
}

/// A class representing option arguments. These are optional arguments
/// which may or may not be provided in the command line. They are always
/// prefixed by their name. For e.g. --verbosity true.
public final class OptionArgument<Kind>: ArgumentProtocol {
    typealias ArgumentKindTy = Kind

    let name: String
    let usage: String?
    let shortName: String?

    init(name: String, shortName: String?, usage: String?) {
        precondition(!isPositional(argument: name))
        self.name = name
        self.shortName = shortName
        self.usage = usage
    }
}

/// A class representing positional arguments. These arguments must be present
/// and in the same order as they are added in the parser.
public final class PositionalArgument<Kind>: ArgumentProtocol {
    typealias ArgumentKindTy = Kind

    let name: String
    let usage: String?
    // Postional arguments don't need short names.
    var shortName: String? { return nil }

    init(name: String, usage: String?) {
        precondition(isPositional(argument: name))
        self.name = name
        self.usage = usage
    }
}

/// A type-erased argument.
///
/// Note: Only used for argument parsing purpose.
fileprivate final class AnyArgument: ArgumentProtocol, CustomStringConvertible {
    typealias ArgumentKindTy = Any

    let name: String
    let usage: String?
    let shortName: String?

    /// The argument kind this holds, used while initializing that argument.
    let kind: ArgumentKind.Type

    /// True if the argument kind is of array type.
    let isArray: Bool

    init<T: ArgumentProtocol>(_ arg: T) {
        self.kind = T.ArgumentKindTy.self as! ArgumentKind.Type
        self.name = arg.name
        self.shortName = arg.shortName
        self.usage = arg.usage
        isArray = false
    }

    /// Initializer for array arguments.
    init<T>(_ arg: OptionArgument<[T]>) {
        self.kind = T.self as! ArgumentKind.Type
        self.name = arg.name
        self.shortName = arg.shortName
        self.usage = arg.usage
        isArray = true
    }

    var description: String {
        return "Argument(\(name))"
    }
}

/// Argument parser protocol passed in initializers of ArgumentKind to manipulate
/// parser as needed by the argument.
public protocol ArgumentParserProtocol {
    /// The current argument being parsed.
    var currentArgument: String { get }

    /// The associated value in a `--foo=bar` style argument.
    var associatedArgumentValue: String? { get }

    /// Provides (and consumes) next argument, if available.
    mutating func next() throws -> String
}

/// Argument parser struct responsible to parse the provided array of arguments and return
/// the parsed result.
public final class ArgumentParser {
    /// A class representing result of the parsed arguments.
    public class Result: CustomStringConvertible {
        /// Internal representation of arguments mapped to their values.
        private var results = [AnyArgument: Any]()

        /// Result of the parent parent parser, if any.
        private var parentResult: Result? = nil

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
        /// - parameter
        ///     - argument: The argument for which this result is being added.
        ///     - value: The associated value of the argument.
        ///
        /// - throws: ArgumentParserError
        fileprivate func addResult(for argument: AnyArgument, result: ArgumentKind) throws {
            if argument.isArray {
                var array = [ArgumentKind]()
                // Get the previously added results if present.
                if let previousResult = results[argument] as? [ArgumentKind] {
                    array = previousResult
                }
                array.append(result)
                results[argument] = array
            } else {
                results[argument] = result
            }
        }

        /// Get an option argument's value from the results.
        ///
        /// Since the options are optional, their result may or may not be present.
        public func get<T>(_ arg: OptionArgument<T>) -> T? {
            return (results[AnyArgument(arg)] as? T) ?? parentResult?.get(arg)
        }

        /// Array variant for option argument's get(_:).
        public func get<T>(_ arg: OptionArgument<[T]>) -> [T]? {
            return (results[AnyArgument(arg)] as? [T]) ?? parentResult?.get(arg)
        }

        /// Get a positional argument's value.
        public func get<T>(_ arg: PositionalArgument<T>) -> T? {
            return results[AnyArgument(arg)] as? T
        }

        /// Get the subparser which was chosen for the given parser.
        public func subparser(_ parser: ArgumentParser) -> String? {
            if parser === self.parser {
                return subparser
            }
            return parentResult?.subparser(parser)
        }

        public var description: String {
            var str = "ArgParseResult(\(results))"
            if let parent = parentResult {
                str += " -> " + parent.description
            }
            return str
        }
    }

    /// The mapping of subparsers to their subcommand.
    private var subparsers: [String: ArgumentParser] = [:]

    /// List of arguments added to this parser.
    private var options = [AnyArgument]()
    private var positionalArgs = [AnyArgument]()

    // If provided, will be substituted instead of arg0 in usage text.
    let commandName: String?

    /// Usage string of this parser.
    let usage: String

    /// Overview text of this parser.
    let overview: String

    /// The parser contains one and only optional positional argument.
    private var optionalPositionalArg = false

    /// If this parser is a subparser.
    private let isSubparser: Bool

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
    public func add<T: ArgumentKind>(option: String, shortName: String? = nil, kind: T.Type, usage: String? = nil) -> OptionArgument<T> {
        let arg = OptionArgument<T>(name: option, shortName: shortName, usage: usage)
        options.append(AnyArgument(arg))
        return arg
    }

    /// Adds an array argument type.
    public func add<T: ArgumentKind>(option: String, shortName: String? = nil, kind: [T].Type, usage: String? = nil) -> OptionArgument<[T]> {
        let arg = OptionArgument<[T]>(name: option, shortName: shortName, usage: usage)
        options.append(AnyArgument(arg))
        return arg
    }

    /// Adds an argument to the parser.
    /// Note: Only one positional argument is allowed if optional setting is enabled.
    public func add<T: ArgumentKind>(positional: String, kind: T.Type, optional: Bool = false, usage: String? = nil) -> PositionalArgument<T> {
        precondition(subparsers.isEmpty, "Positional arguments are not supported with subparsers")
        precondition(optional ? positionalArgs.count <= 1 : true, "Only one positional argument is allowed if optional setting is enabled.")
        optionalPositionalArg = optional
        let arg = PositionalArgument<T>(name: positional, usage: usage)
        positionalArgs.append(AnyArgument(arg))
        return arg
    }
    
    /// Add a parser with a subcommand name and its corresponding overview.
    @discardableResult
    public func add(subparser command: String, overview: String) -> ArgumentParser {
        let parser = ArgumentParser(subparser: overview)
        subparsers[command] = parser
        return parser
    }

    // MARK:- Parsing

    /// A wrapper struct to pass to the ArgumentKind initializers.
    struct Parser: ArgumentParserProtocol {
        /// The iterator used to iterate arguments.
        var argumentsIterator: IndexingIterator<[String]>

        /// The current argument being parsed.
        let currentArgument: String

        private(set) var associatedArgumentValue: String?

        mutating func next() throws -> String {
            guard let nextArg = argumentsIterator.next() else {
                throw ArgumentParserError.expectedValue(option: currentArgument)
            }
            return nextArg
        }

        init(associatedArgumentValue: String?, argumentsIterator: IndexingIterator<[String]>, currentArgument: String) {
            self.associatedArgumentValue = associatedArgumentValue
            self.argumentsIterator = argumentsIterator
            self.currentArgument = currentArgument
        }
    }

    /// Parses the provided array and return the result.
    public func parse(_ args: [String] = []) throws -> Result {
        return try parse(args, parent: nil)
    }

    private func parse(_ args: [String] = [], parent: Result?) throws -> Result {
        let result = Result(parser: self, parent: parent)
        // Create options map to quickly look up the arguments.
        let optionsTuple = options.flatMap { option -> [(String, AnyArgument)] in
            var result = [(option.name, option)]
            // Add the short names too, if we have them.
            if let shortName = option.shortName {
                result += [(shortName, option)]
            }
            return result
        }
        let optionsMap = Dictionary(items: optionsTuple)
        // Create iterators.
        var positionalArgsIterator = positionalArgs.makeIterator()
        var argumentsIterator = args.makeIterator()

        while let arg = argumentsIterator.next() {
            // If argument is help then just print usage and exit.
            if arg == "-h" || arg == "--help" {
                printUsage(on: stdoutStream)
                exit(0)
            } else if isPositional(argument: arg) {
                /// If this parser has subparsers, we allow only one positional argument which is the subparser command.
                if !subparsers.isEmpty {
                    // Make sure this argument has a subparser.
                    guard let subparser = subparsers[arg] else {
                        throw ArgumentParserError.expectedArguments(self, Array(subparsers.keys))
                    }
                    // Save which subparser was chosen.
                    result.subparser = arg
                    // Parse reset of the arguments with the subparser.
                    return try subparser.parse(Array(argumentsIterator), parent: result)
                }

                // Get the next positional argument we are expecting.
                guard let positionalArg = positionalArgsIterator.next() else {
                    throw ArgumentParserError.unexpectedArgument(arg)
                }
                // Initialize the argument and add to result.
                guard let resultValue = positionalArg.kind.init(arg: arg) else {
                    throw ArgumentParserError.typeMismatch("\(arg) is not convertible to \(positionalArg.kind)")
                }
                try result.addResult(for: positionalArg, result: resultValue)
            } else {
                let (arg, value) = arg.split(around: "=")
                // Get the corresponding option for the option argument.
                guard let option = optionsMap[arg] else {
                    throw ArgumentParserError.unknownOption(arg)
                }

                // Create a parser protocol object.
                var parser: ArgumentParserProtocol = Parser(
                    associatedArgumentValue: value,
                    argumentsIterator: argumentsIterator,
                    currentArgument: arg)

                // Initialize the argument and add to result.
                let resultValue = try option.kind.init(parser: &parser)
                // Restore the argument iterator state.
                // FIXME: Passing inout parser above is a compiler error without explicitly setting its type.
                argumentsIterator = (parser as! Parser).argumentsIterator
                try result.addResult(for: option, result: resultValue)
            }
        }
        // Report if there are any non-optional positional arguments left which were not present in the arguments.
        let leftOverArgs = Array(positionalArgsIterator)
        if !optionalPositionalArg && !leftOverArgs.isEmpty {
            throw ArgumentParserError.expectedArguments(self, leftOverArgs.map {$0.name})
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
        if let maxArgument = (positionalArgs + options).map({ $0.name.characters.count }).max(), maxArgument < maxWidthDefault {
            maxWidth = maxArgument + padding + 1
        } else {
            maxWidth = maxWidthDefault
        }

        /// Prints an argument on a stream if it has usage.
        func print(formatted argument: String, usage: String, on stream: OutputByteStream) {
            // Start with a new line and add some padding.
            stream <<< "\n" <<< Format.asRepeating(string: " ", count: padding)
            let count = argument.characters.count
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

        if options.count > 0 {
            stream <<< "\n\n"
            stream <<< "OPTIONS:"
            for argument in options.lazy.sorted(by: {$0.name < $1.name}) {
                guard let usage = argument.usage else { continue }
                // Create name with its shortname, if available.
                let name = [argument.name, argument.shortName].flatMap{$0}.joined(separator: ", ")
                print(formatted: name, usage: usage, on: stream)
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

        if positionalArgs.count > 0 {
            stream <<< "\n\n"
            stream <<< "COMMANDS:"
            for argument in positionalArgs.lazy.sorted(by: {$0.name < $1.name}) {
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
