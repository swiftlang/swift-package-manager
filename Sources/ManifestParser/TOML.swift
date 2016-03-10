/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines a minimal TOML parser. It is currently designed only to
 support the needs of the package manager, not to be a general purpose TOML
 library. There is currently no support for the date type.
*/

// MARK: TOML Item Definition

/// Represents a TOML encoded value.
public enum TOMLItem {
    case Bool(value: Swift.Bool)
    case Int(value: Swift.Int)
    case Float(value: Swift.Float)
    case String(value: Swift.String)
    case Array(contents: TOMLItemArray)
    case Table(contents: TOMLItemTable)
}

public class TOMLItemArray: CustomStringConvertible {
    public var items: [TOMLItem] = []

    init(items: [TOMLItem] = []) {
        self.items = items
    }

    public var description: String {
        return items.description
    }
}

public class TOMLItemTable: CustomStringConvertible {
    public var items: [String: TOMLItem]

    init(items: [String: TOMLItem] = [:]) {
        self.items = items
    }
    
    public var description: String {
        return items.description
    }
}

extension TOMLItem: CustomStringConvertible {
    public var description: Swift.String {
        switch self {
        case .Bool(let value): return value.description
        case .Int(let value): return value.description
        case .Float(let value): return value.description
        case .String(let value): return "\"\(value)\""
        case .Array(let values): return values.description
        case .Table(let values): return values.description
        }
    }
}

extension TOMLItem: Equatable { }
public func ==(lhs: TOMLItem, rhs: TOMLItem) -> Bool {
    switch (lhs, rhs) {
    case (.Bool(let a), .Bool(let b)): return a == b
    case (.Bool, _): return false
    case (.Int(let a), .Int(let b)): return a == b
    case (.Int, _): return false
    case (.Float(let a), .Float(let b)): return a == b
    case (.Float, _): return false
    case (.String(let a), .String(let b)): return a == b
    case (.String, _): return false
    case (.Array(let a), .Array(let b)): return a.items == b.items
    case (.Array, _): return false
    case (.Table(let a), .Table(let b)): return a.items == b.items
    case (.Table, _): return false
    }
}


// MARK: Lexer

private extension String {
    /// Convenience for accessing UTF8 constant values.
    var utf8Constant: UInt8 {
        assert(utf8.startIndex.successor() == utf8.endIndex)
        return utf8[utf8.startIndex]
    }
}

/// Extensions to check TOML character classes.
private extension UInt8 {
    /// Check if this is a space.
    func isSpace() -> Bool {
        return self == " ".utf8Constant || self == "\t".utf8Constant
    }

    /// Check if this is a valid initial character of a number constant.
    func isNumberInitialChar() -> Bool {
        switch self {
        case "+".utf8Constant: fallthrough
        case "-".utf8Constant: fallthrough
        case "0".utf8Constant..."9".utf8Constant:
            return true
        default:
            return false
        }
    }

    /// Check if this is a valid character of a number constant.
    func isNumberChar() -> Bool {
        switch self {
        case "_".utf8Constant: fallthrough
        case "+".utf8Constant: fallthrough
        case "-".utf8Constant: fallthrough
        case ".".utf8Constant: fallthrough
        case "e".utf8Constant: fallthrough
        case "E".utf8Constant: fallthrough
        case "0".utf8Constant..."9".utf8Constant:
            return true
        default:
            return false
        }
    }

    /// Check if this is a "bare key" identifier character.
    func isIdentifierChar() -> Bool {
        switch self {
        case "a".utf8Constant..."z".utf8Constant: fallthrough
        case "A".utf8Constant..."Z".utf8Constant: fallthrough
        case "0".utf8Constant..."9".utf8Constant: fallthrough
        case "_".utf8Constant: fallthrough
        case "-".utf8Constant:
            return true
        default:
            return false
        }
    }
}

/// A basic TOML lexer.
///
/// This implementation doesn't yet support multi-line strings.
private struct Lexer {
    private enum Token {
        /// Any comment.
        case Comment
        /// Any whitespace.
        case Whitespace
        /// A newline.
        case Newline
        /// A literal string.
        case StringLiteral(value: String)
        /// An identifier (i.e., 'foo').
        case Identifier(value: String)
        /// A boolean constant.
        case Boolean(value: Bool)
        /// A numeric constant (which may not be well formed).
        case Number(value: String)
        /// The end of file marker.
        case EOF
        /// An unknown character.
        case Unknown(value: UInt8)

        /// A ',' character.
        case Comma
        /// An '=' character.
        case Equals
        /// A left square bracket ('[').
        case LSquare
        /// A right square bracket (']').
        case RSquare
        /// A '.' character.
        case Period
    }

    /// The string being lexed.
    let data: String

    /// The current lexer position.
    var index: String.UTF8View.Index

    /// The UTF8 view of the data being lexed.
    var utf8: String.UTF8View {
        return data.utf8
    }

    /// The lookahead character, if computed.
    var lookahead: UInt8? = nil

    /// The next index, if the lookahead character is active.
    var nextIndex: String.UTF8View.Index? = nil
    
    init(_ data: String) {
        self.data = data
        self.index = self.data.utf8.startIndex
    }

    /// Look ahead at the next character.
    private mutating func look() -> UInt8? {
        // Return the cached look ahead character, if present.
        if let c = lookahead {
            return c
        }

        // Check if we are at the end of the string.
        if index == utf8.endIndex {
            return nil
        }

        // Consume and cache the next character.
        lookahead = utf8[index]
        nextIndex = index.successor()

        // Normalize line endings.
        if lookahead == "\r".utf8Constant && utf8[nextIndex!] == "\n".utf8Constant {
            nextIndex = nextIndex!.successor()
            lookahead = "\n".utf8Constant
        }

        return lookahead
    }

    /// Consume and return one character.
    private mutating func eat() -> UInt8? {
        guard let c = look() else { return nil }
        
        // Commit the character.
        lookahead = nil
        index = nextIndex!
        return c
    }
    
    /// Consume the next token from the lexer.
    mutating func next() -> Token {
        let startIndex = index
        guard let c = eat() else { return .EOF }
        
        switch c {
        case "\n".utf8Constant:
            return .Newline
            
        // Comments.
        case "#".utf8Constant:
            // Scan to the end of the line.
            while let c = look() {
                eat()
                if c == "\n".utf8Constant {
                    break
                }
            }
            return .Comment

        // Whitespace.
        case let c where c.isSpace():
            // Scan to the end of the whitespace
            while let c = look() where c.isSpace() {
                eat()
            }
            return .Whitespace

        // Strings.
        case "\"".utf8Constant:
            // Scan to the end of the string.
            //
            // FIXME: Diagnose non-terminated strings.
            var endIndex = index
            while let c = look() {
                // Update the end index before consuming the character.
                endIndex = index
                eat()

                if c == "\"".utf8Constant {
                    break
                }
            }
            return .StringLiteral(value: String(utf8[startIndex.successor()..<endIndex]))

        // Numeric literals.
        //
        // NOTE: It is important we parse this ahead of identifiers, as
        // numbers are valid identifiers but should be reconfigured as such.
        case let c where c.isNumberInitialChar():
            // Scan to the end of the number.
            while let c = look() where c.isNumberChar() {
                eat()
            }
            return .Number(value: String(utf8[startIndex..<index]))

        // Identifiers.
        case let c where c.isIdentifierChar():
            // Scan to the end of the identifier.
            while let c = look() where c.isIdentifierChar() {
                eat()
            }

            // Match special strings.
            let value: String = String(utf8[startIndex..<index])
            switch value {
            case "true":
                return .Boolean(value: true)
            case "false":
                return .Boolean(value: false)
            default:
                return .Identifier(value: value)
            }
            
        // Punctuation.
        case ",".utf8Constant:
            return .Comma
        case "=".utf8Constant:
            return .Equals
        case "[".utf8Constant:
            return .LSquare
        case "]".utf8Constant:
            return .RSquare
        case ".".utf8Constant:
            return .Period
            
        default:
            return .Unknown(value: c)
            
        }
    }
}

// Define custom description for Lexer.Token. This works around an issue in string conversion of literals in older versions of the Swift compiler.
extension Lexer.Token : CustomStringConvertible {
    var description: String {
        switch self {
        case .Comment:
            return "Comment"
        case .Whitespace:
            return "Whitespace"
        case .Newline:
            return "Newline"
        case .StringLiteral(let value):
            return "StringLiteral(\"\(value)\")"
        case .Identifier(let value):
            return "Identifier(\"\(value)\")"
        case .Boolean(let value):
            return "Boolean(\(value))"
        case .Number(let value):
            return "Number(\"\(value)\")"
        case .EOF:
            return "EOF"
        case .Unknown(let value):
            return "Unknown(\(value))"

        case .Comma:
            return "Comma"
        case .Equals:
            return "Equals"
        case .LSquare:
            return "LSquare"
        case .RSquare:
            return "RSquare"
        case .Period:
            return "Period"
        }
    }
}

private struct LexerTokenGenerator : IteratorProtocol {
    var lexer: Lexer

    mutating func next() -> Lexer.Token? {
        let token =  lexer.next()
        if case .EOF = token {
            return nil
        }
        return token
    }
}

extension Lexer : LazySequenceProtocol {
    func makeIterator() -> LexerTokenGenerator {
        return LexerTokenGenerator(lexer: self)
    }
}

extension Lexer.Token : Equatable { }
private func ==(lhs: Lexer.Token, rhs: Lexer.Token) -> Bool {
    switch (lhs, rhs) {
    case (.Comment, .Comment): fallthrough
    case (.Whitespace, .Whitespace): fallthrough
    case (.Newline, .Newline): fallthrough
    case (.EOF, .EOF): fallthrough
    case (.Comma, .Comma): fallthrough
    case (.Equals, .Equals): fallthrough
    case (.LSquare, .LSquare): fallthrough
    case (.RSquare, .RSquare): fallthrough
    case (.Period, .Period):
        return true

    case (.StringLiteral(let a), .StringLiteral(let b)):
        return a == b
    case (.Identifier(let a), .Identifier(let b)):
        return a == b
    case (.Boolean(let a), .Boolean(let b)):
        return a == b
    case (.Number(let a), .Number(let b)):
        return a == b
    case (.Unknown(let a), .Unknown(let b)):
        return a == b

    default:
        return false
    }
}

// MARK: Parser

private struct Parser {
    /// The lexer in use.
    private var lexer: Lexer

    /// The lookahead token.
    private var lookahead: Lexer.Token

    /// The list of errors.
    var errors: [String] = []
    
    init(_ data: String) {
        lexer = Lexer(data)
        lookahead = .EOF
        
        // Prime the lookahead.
        eat()
    }

    /// Parse the string to an item.
    mutating func parse() -> TOMLItem {
        // This is the main parsing loop, which handles parsing of the top-level and all nested tables.

        // The top-level table.
        let topLevelTable = TOMLItemTable()
        // The table currently being inserted into.
        var into = topLevelTable

        // Parse the file until we reach EOF.
        while lookahead != .EOF {
            // Parse the current table contents.
            parseTableContents(into)

            // If we stopped at the next nested table definition, process it.
            let startToken = lookahead
            if consumeIf({ $0 == .LSquare }) {
                // Check if we have a double-square (indicating an array-of-tables).
                let isAppend = consumeIf({ $0 == .LSquare })

                // Process the table specifier.
                guard let specifiers = parseTableSpecifier(isAppend) else {
                    // If there was an error parsing the table specifier, ignore this.
                    continue
                }

                // Otherwise, adjust the table we are writing into.
                into = findInsertPoint(topLevelTable, specifiers, isAppend: isAppend, startToken: startToken)
            }
        }

        return .Table(contents: topLevelTable)
    }

    /// Find the new table to insert into given the top-level table and a list of specifiers.
    private mutating func findInsertPoint(topLevelTable: TOMLItemTable, _ specifiers: [String], isAppend: Bool, startToken: Lexer.Token) -> TOMLItemTable {
        // FIXME: Handle TOML requirements (sole definition).
        var into = topLevelTable
        for (i,specifier) in specifiers.enumerated() {
            // If this is an append, then the last key is handled as a special case.
            if isAppend && i == specifiers.count - 1 {
                if let existing = into.items[specifier] {
                    guard case .Array(let array) = existing else {
                        error("cannot insert table for key path: \(specifiers)", at: startToken)
                        return topLevelTable
                    }
                    into = TOMLItemTable()
                    array.items.append(.Table(contents: into))
                } else {
                    let array = TOMLItemArray()
                    let table = TOMLItemTable()
                    array.items.append(.Table(contents: table))
                    into.items[specifier] = .Array(contents: array)
                    into = table
                }
                continue
            }
                    
            if let existing = into.items[specifier] {
                switch existing {
                case .Array(let contents):
                    guard case .Table(let table) = contents.items.last! else {
                        error("cannot insert table for key path: \(specifiers)", at: startToken)
                        return topLevelTable
                    }
                    into = table
                case .Table(let contents):
                    into = contents
                default:
                    error("cannot insert table for key path: \(specifiers)", at: startToken)
                    return topLevelTable
                }
            } else {
                let table = TOMLItemTable()
                into.items[specifier] = .Table(contents: table)
                into = table
            }
        }
        return into
    }

    /// Parse a table specifier (list of keys describing the key path to the
    /// item), including the terminating brackets.
    ///
    /// - Parameter isAppend: Whether the specifier should end with double brackets.
    private mutating func parseTableSpecifier(isAppend: Bool) -> [String]? {
        let startToken = lookahead
            
        // Parse all of the specifiers.
        var specifiers: [String] = []
        while lookahead != .EOF && lookahead != .RSquare {
            // Parse the next specifier.
            switch eat() {
            case .StringLiteral(let value):
                specifiers.append(value)
            case .Identifier(let value):
                specifiers.append(value)

            case let token:
                error("unexpected token in table specifier", at: token)
                skipToEndOfLine()
                return nil
            }

            // Consume the specifier separator, if present.
            if !consumeIf({ $0 == .Period }) {
                // If we didn't have a period, then should be at the end of the specifier.
                break
            }
        }

        // Consume the trailing brackets.
        if !consumeIf({ $0 == .RSquare }) {
            error("expected terminating ']' in table specifier", at: lookahead)
            skipToEndOfLine()
            return specifiers
        }
        if isAppend && !consumeIf({ $0 == .RSquare }) {
            error("expected terminating ']]' in table specifier", at: lookahead)
            skipToEndOfLine()
            return specifiers
        }

        // Consume the trailing newline.
        if !consumeIf({ $0 == .EOF || $0 == .Newline }) {
            error("unexpected trailing token after table specifier", at: lookahead)
            skipToEndOfLine()
        }

        // Require that the specifiers be non-empty.
        if specifiers.isEmpty {
            error("invalid table specifier (empty key path)", at: startToken)
            return nil
        }
            
        return specifiers
    }
    
    // MARK: Parser Implementation
    
    /// Report an error at the given token.
    private mutating func error(message: String, at: Lexer.Token) {
        errors.append(message)
    }
    
    /// Consume the next token from the lexer, skipping whitespace and comments.
    private mutating func eat() -> Lexer.Token {
        let result = lookahead
        // Get the next token, skipping whitespace and comments.
        repeat {
            lookahead = lexer.next()
        } while lookahead == .Comment || lookahead == .Whitespace
        return result
    }

    /// Consume a token if it matches a particular block.
    private mutating func consumeIf(match: (Lexer.Token) -> Bool) -> Bool {
        if match(lookahead) {
            eat()
            return true
        }
        return false
    }
    
    /// Skip tokens until the next newline (or EOF) is reached.
    private mutating func skipToEndOfLine() {
        loop: while true {
            switch eat() {
            case .EOF: fallthrough
            case .Newline:
                break loop
            default:
                continue
            }
        }
    }

    /// Parse the contents of a table, stopping at the next table marker.
    private mutating func parseTableContents(table: TOMLItemTable) {
        // Parse assignments until we reach the EOF or a new table record.
        while lookahead != .EOF && lookahead != .LSquare {
            // If we have a bare newline, ignore it.
            if consumeIf({ $0 == .Newline }) {
                continue
            }

            // Otherwise, we should have an assignment.
            parseAssignment(table)
        }
    }

    /// Parse an individual table assignment.
    private mutating func parseAssignment(table: TOMLItemTable) {
        // Parse the LHS.
        let key: String
        switch eat() {
        case .Number(let value):
            key = value
        case .Identifier(let value):
            key = value
        case .StringLiteral(let value):
            key = value

        case let token:
            error("unexpected token while parsing assignment", at: token)
            skipToEndOfLine()
            return
        }

        // Expect an '='.
        guard consumeIf({ $0 == .Equals }) else {
            error("unexpected token while parsing assignment", at: lookahead)
            skipToEndOfLine()
            return
        }

        // Parse the RHS.
        let result: TOMLItem = parseItem()

        // Expect a newline or EOF.
        if !consumeIf({ $0 == .EOF || $0 == .Newline }) {
            error("unexpected trailing token in assignment", at: lookahead)
            skipToEndOfLine()
        }
        
        table.items[key] = result
    }

    /// Parse an individual item.
    private mutating func parseItem() -> TOMLItem {
        let token = eat()
        switch token {
        case .Number(let spelling):
            if let numberItem = parseNumberItem(spelling) {
                return numberItem
            } else {
                error("invalid number value in assignment", at: token)
                skipToEndOfLine()
                return .String(value: "<<invalid>>")
            }
        case .Identifier(let string):
            return .String(value: string)
        case .StringLiteral(let string):
            return .String(value: string)
        case .Boolean(let value):
            return .Bool(value: value)

        case .LSquare:
            return parseInlineArray()
            
        default:
            error("unexpected token while parsing assignment", at: token)
            skipToEndOfLine()
            return .String(value: "<<invalid>>")
        }
    }
    
    /// Parse an inline array.
    ///
    /// The token stream is assumed to be positioned immediately after the opening bracket.
    private mutating func parseInlineArray() -> TOMLItem {
        // Parse items until we reach the closing bracket.
        let array = TOMLItemArray()
        while lookahead != .EOF && lookahead != .RSquare {
            // Skip newline tokens in arrays.
            if consumeIf({ $0 == .Newline }) {
                continue
            }

            // Otherwise, we should have a valid item.
            //
            // FIXME: We need to arrange for this to handle recovery properly,
            // by not just skipping to the end of the line.
            array.items.append(parseItem())

            // Consume the trailing comma, if present.
            if !consumeIf({ $0 == .Comma }) {
                // If we didn't have a comma, then should be at the end of the array.
                break
            }
        }

        // Consume the trailing bracket.
        if !consumeIf({ $0 == .RSquare }) {
            error("missing closing array square bracket", at: lookahead)
            // FIXME: This should skip respecting the current bracket nesting level.
            skipToEndOfLine()
        }

        // FIXME: The TOML spec requires that arrays consist of homogeneous
        // types. We should validate that.

        return .Array(contents: array)
    }
    
    private func parseNumberItem(spelling: String) -> TOMLItem? {
        
        let normalized = String(spelling.characters.filter { $0 != "_" })

        if let value = Int(normalized) {
            return .Int(value: value)
        } else if let value = Float(normalized) {
            return .Float(value: value)
        } else {
            return nil
        }
    }
}

/// Generic error thrown for any TOML error.
public struct TOMLParsingError : ErrorProtocol {
    /// The raw errors.
    public let errors: [String]
}

/// Public interface to parsing TOML.
public extension TOMLItem {
    static func parse(data: Swift.String) throws -> TOMLItem {
        // Parse the string.
        var parser = Parser(data)
        let result = parser.parse()

        // Throw an error if any diagnostics were generated.
        if !parser.errors.isEmpty {
            throw TOMLParsingError(errors: parser.errors)
        }
        
        return result
    }
}

// MARK: Testing API

/// Internal function for testing the lexer.
///
/// returns: A list of the lexed tokens' string representations.
internal func lexTOML(data: String) -> [String] {
    let lexer = Lexer(data)
    return lexer.map { String($0) }
}
