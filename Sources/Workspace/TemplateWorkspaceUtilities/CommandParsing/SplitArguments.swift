//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A structure representing a parsed and consumable list of command-line arguments.
///
/// `SplitArguments` parses raw CLI arguments into discrete elements (`Element`) representing
/// options, values, and terminators (`--`). It provides methods to inspect, consume, and
/// track usage of arguments, supporting both positional and named options.
struct SplitArguments {
    /// Represents a single element in the parsed argument list.
    struct Element {
        /// The type of element: option, value, or terminator.
        enum Value: Equatable {
            case option(ParsedTemplateArgument)
            case value(String)
            case terminator // "--"
        }

        /// The underlying element value.
        var value: Value

        /// The original index of the argument in the input array.
        var index: Int

        /// Returns true if this element is a standalone value.
        var isValue: Bool {
            if case .value = self.value { return true }
            return false
        }

        /// Returns true if this element is the terminator `--`.
        var isTerminator: Bool {
            if case .terminator = self.value { return true }
            return false
        }
    }

    // MARK: - Properties

    /// The parsed elements in order.
    private var elements: [Element]
    /// The index of the first unconsumed element.
    private var firstUnused: Int = 0
    /// The original input array of argument strings.
    let originalInput: [String]
    /// Tracks indices of elements that have been consumed.
    private var consumedIndices: Set<Int> = []

    /// Records consumption events for debugging.
    var consumptionLog: [ConsumptionRecord] = []

    /// Returns a slice of elements that have not yet been consumed.
    var remainingElements: ArraySlice<Element> {
        self.elements[self.firstUnused...]
    }

    /// Returns true if there are no remaining unconsumed elements.
    var isEmpty: Bool {
        self.remainingElements.isEmpty
    }

    /// Returns the number of remaining unconsumed elements.
    var count: Int {
        self.remainingElements.count
    }

    /// Initializes a `SplitArguments` instance by parsing raw CLI argument strings.
    ///
    /// - Parameter arguments: The array of argument strings.
    /// - Throws: A `ParsingStringError` if an invalid argument format is encountered.
    init(arguments: [String]) throws {
        self.originalInput = arguments
        self.elements = []

        for (index, args) in arguments.enumerated() {
            let element = try Self.parseArgument(args, at: index)
            self.elements.append(contentsOf: element)

            // if it is a terminator, we parse the rest as values
            if element.first?.isTerminator == true {
                for (i, remainingArg) in arguments[(index + 1)...].enumerated() {
                    self.elements.append(Element(
                        value: .value(remainingArg),
                        index: i + 1 + index
                    ))
                }
                break
            }
        }
    }

    // MARK: Consumption helpers

    /// Returns the next unconsumed element without marking it as consumed.
    func peekNext() -> Element? {
        // Find the first unconsumed element from firstUnused onwards
        for element in self.remainingElements {
            if !self.consumedIndices.contains(element.index) {
                return element
            }
        }
        return nil
    }

    /// Consumes and returns the next unconsumed element.
    mutating func consumeNext() -> Element? {
        // Find and consume the first unconsumed element
        while !self.isEmpty {
            let element = self.remainingElements.first!
            self.firstUnused += 1

            if !self.consumedIndices.contains(element.index) {
                self.consumedIndices.insert(element.index)
                return element
            }
            // If already consumed, continue to next element
        }
        return nil
    }

    /// Consumes the next unconsumed value element.
    ///
    /// - Parameter argumentName: Optional name of the argument for tracking purposes.
    /// - Returns: The next value string, or nil if the next element is not a value.
    mutating func consumeNextValue(for argumentName: String? = nil) -> String? {
        guard let next = peekNext(), next.isValue else { return nil }
        if case .value(let str) = consumeNext()?.value {
            // Mark the consumption purpose if we have an argument name
            if let argName = argumentName {
                self.markAsConsumed(
                    next.index,
                    for: .optionValue(argName),
                    argumentName: argName
                )
            }
            return str
        }
        return nil
    }

    /// Scans forward for the next unconsumed value element, skipping options.
    mutating func scanForNextValue(for argumentName: String? = nil) -> String? {
        var scanIndex = self.firstUnused

        while scanIndex < self.elements.count {
            let element = self.elements[scanIndex]

            if self.consumedIndices.contains(element.index) {
                scanIndex += 1
                continue
            }

            switch element.value {
            case .value(let str):
                self.consumedIndices.insert(element.index)
                if let argName = argumentName {
                    self.markAsConsumed(
                        element.index,
                        for: .optionValue(argName),
                        argumentName: argName
                    )
                }
                return str

            case .option:
                scanIndex += 1
                continue

            case .terminator:
                // Stop scanning at terminator
                return nil
            }
        }

        return nil
    }

    /// Consumes an option with a specific name if it is next in the argument list.
    mutating func consumeOption(named name: String) -> ParsedTemplateArgument? {
        guard let next = peekNext(),
              case .option(let parsed) = next.value,
              parsed.matchesName(name) else { return nil }

        let element = self.consumeNext()!
        // Mark the option itself as consumed with proper tracking
        self.markAsConsumed(
            element.index,
            for: .optionValue(name),
            argumentName:
            name
        )
        return parsed
    }

    /// Returns all remaining values (for positional arguments)
    var remainingValues: [String] {
        self.remainingElements.compactMap { element in
            if case .value(let str) = element.value {
                return str
            }
            return nil
        }
    }

    /// Returns all remaining options with their values
    var remainingOptions: [(name: String, value: String?)] {
        self.remainingElements.compactMap { element in
            if case .option(let parsed) = element.value {
                return (parsed.name, parsed.value)
            }
            return nil
        }
    }

    // MARK: - Parsing

    /// Parses a single argument string into one or more elements.
    private static func parseArgument(_ arg: String, at index: Int) throws ->
        [Element]
    {
        if arg == "--" {
            return [Element(value: .terminator, index: index)]
        }

        if arg.hasPrefix("--") {
            // Long option: --name or --name=value
            let parsed = try
                ParsedTemplateArgument.parseLongOption(String(arg.dropFirst(2)))
            return [Element(value: .option(parsed), index: index)]
        }

        if arg.hasPrefix("-") && arg.count > 1 {
            // Short option(s): -f or -abc or -f=value
            let remainder = String(arg.dropFirst())
            if let equalIndex = remainder.firstIndex(of: "=") {
                // Single short option with value: -f=value
                let name = String(remainder[..<equalIndex])
                let value = String(remainder[remainder.index(after:
                    equalIndex
                )...])
                guard name.count == 1, let char = name.first else {
                    throw ParsingStringError("Invalid short option format")
                }
                let parsed = ParsedTemplateArgument(
                    type: .shortOption(char, value),
                    originalToken: arg
                )
                return [Element(value: .option(parsed), index: index)]
            } else if remainder.count == 1 {
                // Single short option: -f
                guard let char = remainder.first else {
                    throw ParsingStringError("Empty short option")
                }
                let parsed = ParsedTemplateArgument(
                    type: .shortFlag(char),
                    originalToken: arg
                )
                return [Element(value: .option(parsed), index: index)]
            } else {
                // Multiple short options: -abc (shortGroup)
                let chars = Array(remainder)
                let parsed = ParsedTemplateArgument(
                    type: .shortGroup(chars),
                    originalToken: arg
                )
                return [Element(value: .option(parsed), index: index)]
            }
        }

        // Regular value
        return [Element(value: .value(arg), index: index)]
    }
}

// MARK: - Consumption Tracking

extension SplitArguments {
    /// Marks an element as consumed
    mutating func markAsConsumed(
        _ index: Int,
        for purpose: ConsumptionPurpose,
        argumentName: String? = nil
    ) {
        self.consumedIndices.insert(index)
        self.consumptionLog.append(ConsumptionRecord(
            elementIndex: index,
            purpose: purpose,
            argumentName: argumentName
        ))
    }

    /// Returns all values that appear after the terminator `--`.
    mutating func removeElementsAfterTerminator() -> [String] {
        guard let terminatorIndex = elements.firstIndex(where: { $0.isTerminator
        }) else {
            return []
        }

        let postTerminatorValues = self.elements[(terminatorIndex + 1)...].compactMap { element -> String?
            in
            if case .value(let str) = element.value {
                self.markAsConsumed(element.index, for: .postTerminator)
                return str
            }
            return nil
        }

        return postTerminatorValues
    }

    /// Returns all elements that have not yet been consumed.
    var unconsumedElements: ArraySlice<Element> {
        self.elements.filter { !self.consumedIndices.contains($0.index) }[...]
    }
}
