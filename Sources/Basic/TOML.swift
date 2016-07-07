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
    case bool(value: Swift.Bool)
    case int(value: Swift.Int)
    case float(value: Swift.Float)
    case string(value: Swift.String)
    case array(contents: TOMLItemArray)
    case table(contents: TOMLItemTable)
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
        case .bool(let value): return value.description
        case .int(let value): return value.description
        case .float(let value): return value.description
        case .string(let value): return "\"\(value)\""
        case .array(let values): return values.description
        case .table(let values): return values.description
        }
    }
}

extension TOMLItem: Equatable { }
public func ==(lhs: TOMLItem, rhs: TOMLItem) -> Bool {
    switch (lhs, rhs) {
    case (.bool(let a), .bool(let b)): return a == b
    case (.bool, _): return false
    case (.int(let a), .int(let b)): return a == b
    case (.int, _): return false
    case (.float(let a), .float(let b)): return a == b
    case (.float, _): return false
    case (.string(let a), .string(let b)): return a == b
    case (.string, _): return false
    case (.array(let a), .array(let b)): return a.items == b.items
    case (.array, _): return false
    case (.table(let a), .table(let b)): return a.items == b.items
    case (.table, _): return false
    }
}


// MARK: Lexer

/// Extensions to check TOML character classes.
private extension UInt8 {
    /// Check if this is a space.
    func isSpace() -> Bool {
        return self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
    }

    /// Check if this is a valid initial character of a number constant.
    func isNumberInitialChar() -> Bool {
        switch self {
        case UInt8(ascii: "+"),
             UInt8(ascii: "-"),
             UInt8(ascii: "0")...UInt8(ascii:"9"):
            return true
        default:
            return false
        }
    }

    /// Check if this is a valid character of a number constant.
    func isNumberChar() -> Bool {
        switch self {
        case UInt8(ascii: "_"),
             UInt8(ascii: "+"),
             UInt8(ascii: "-"),
             UInt8(ascii: "."),
             UInt8(ascii: "e"),
             UInt8(ascii: "E"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return false
        }
    }

    /// Check if this is a "bare key" identifier character.
    func isIdentifierChar() -> Bool {
        switch self {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "_"),
             UInt8(ascii: "-"):
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
        case comment
        /// Any whitespace.
        case whitespace
        /// A newline.
        case newline
        /// A literal string.
        case stringLiteral(value: String)
        /// An identifier (i.e., 'foo').
        case identifier(value: String)
        /// A boolean constant.
        case boolean(value: Bool)
        /// A numeric constant (which may not be well formed).
        case number(value: String)
        /// The end of file marker.
        case eof
        /// An unknown character.
        case unknown(value: UInt8)

        /// A ',' character.
        case comma
        /// An '=' character.
        case equals
        /// A left square bracket ('[').
        case lSquare
        /// A right square bracket (']').
        case rSquare
        /// A '.' character.
        case period
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
        nextIndex = utf8.index(after: index)

        // Normalize line endings.
        if lookahead == UInt8(ascii: "\r") && utf8[nextIndex!] == UInt8(ascii: "\n") {
            nextIndex = utf8.index(after: nextIndex!)
            lookahead = UInt8(ascii: "\n")
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
        guard let c = eat() else { return .eof }
        
        switch c {
        case UInt8(ascii: "\n"):
            return .newline
            
        // Comments.
        case UInt8(ascii: "#"):
            // Scan to the end of the line.
            while let c = eat() {
                if c == UInt8(ascii: "\n") {
                    break
                }
            }
            return .comment

        // Whitespace.
        case let c where c.isSpace():
            // Scan to the end of the whitespace
            while let c = look() , c.isSpace() {
                let _ = eat()
            }
            return .whitespace

        // Strings.
        case UInt8(ascii: "\""):
            // Scan to the end of the string.
            //
            // FIXME: Diagnose non-terminated strings.
            var endIndex = index
            while let c = look() {
                // Update the end index before consuming the character.
                endIndex = index
                let _ = eat()

                if c == UInt8(ascii: "\"") {
                    break
                }
            }
            return .stringLiteral(value: String(utf8[utf8.index(after: startIndex)..<endIndex]))

        // Numeric literals.
        //
        // NOTE: It is important we parse this ahead of identifiers, as
        // numbers are valid identifiers but should be reconfigured as such.
        case let c where c.isNumberInitialChar():
            // Scan to the end of the number.
            while let c = look(), c.isNumberChar() {
                let _ = eat()
            }
            return .number(value: String(utf8[startIndex..<index]))

        // Identifiers.
        case let c where c.isIdentifierChar():
            // Scan to the end of the identifier.
            while let c = look(), c.isIdentifierChar() {
                let _ = eat()
            }

            // Match special strings.
            let value: String = String(utf8[startIndex..<index])
            switch value {
            case "true":
                return .boolean(value: true)
            case "false":
                return .boolean(value: false)
            default:
                return .identifier(value: value)
            }
            
        // Punctuation.
        case UInt8(ascii: ","):
            return .comma
        case UInt8(ascii: "="):
            return .equals
        case UInt8(ascii: "["):
            return .lSquare
        case UInt8(ascii: "]"):
            return .rSquare
        case UInt8(ascii: "."):
            return .period
            
        default:
            return .unknown(value: c)
            
        }
    }
}

// Define custom description for Lexer.Token. This works around an issue in string conversion of literals in older versions of the Swift compiler.
extension Lexer.Token : CustomStringConvertible {
    var description: String {
        switch self {
        case .comment:
            return "Comment"
        case .whitespace:
            return "Whitespace"
        case .newline:
            return "Newline"
        case .stringLiteral(let value):
            return "StringLiteral(\"\(value)\")"
        case .identifier(let value):
            return "Identifier(\"\(value)\")"
        case .boolean(let value):
            return "Boolean(\(value))"
        case .number(let value):
            return "Number(\"\(value)\")"
        case .eof:
            return "EOF"
        case .unknown(let value):
            return "Unknown(\(value))"

        case .comma:
            return "Comma"
        case .equals:
            return "Equals"
        case .lSquare:
            return "LSquare"
        case .rSquare:
            return "RSquare"
        case .period:
            return "Period"
        }
    }
}

private struct LexerTokenGenerator : IteratorProtocol {
    var lexer: Lexer

    mutating func next() -> Lexer.Token? {
        let token =  lexer.next()
        if case .eof = token {
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
    case (.comment, .comment): fallthrough
    case (.whitespace, .whitespace): fallthrough
    case (.newline, .newline): fallthrough
    case (.eof, .eof): fallthrough
    case (.comma, .comma): fallthrough
    case (.equals, .equals): fallthrough
    case (.lSquare, .lSquare): fallthrough
    case (.rSquare, .rSquare): fallthrough
    case (.period, .period):
        return true

    case (.stringLiteral(let a), .stringLiteral(let b)):
        return a == b
    case (.identifier(let a), .identifier(let b)):
        return a == b
    case (.boolean(let a), .boolean(let b)):
        return a == b
    case (.number(let a), .number(let b)):
        return a == b
    case (.unknown(let a), .unknown(let b)):
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
        lookahead = .eof
        
        // Prime the lookahead.
        let _ = eat()
    }

    /// Parse the string to an item.
    mutating func parse() -> TOMLItem {
        // This is the main parsing loop, which handles parsing of the top-level and all nested tables.

        // The top-level table.
        let topLevelTable = TOMLItemTable()
        // The table currently being inserted into.
        var into = topLevelTable

        // Parse the file until we reach EOF.
        while lookahead != .eof {
            // Parse the current table contents.
            parseTableContents(into)

            // If we stopped at the next nested table definition, process it.
            let startToken = lookahead
            if consumeIf({ $0 == .lSquare }) {
                // Check if we have a double-square (indicating an array-of-tables).
                let isAppend = consumeIf({ $0 == .lSquare })

                // Process the table specifier.
                guard let specifiers = parseTableSpecifier(isAppend) else {
                    // If there was an error parsing the table specifier, ignore this.
                    continue
                }

                // Otherwise, adjust the table we are writing into.
                into = findInsertPoint(topLevelTable, specifiers, isAppend: isAppend, startToken: startToken)
            }
        }

        return .table(contents: topLevelTable)
    }

    /// Find the new table to insert into given the top-level table and a list of specifiers.
    private mutating func findInsertPoint(_ topLevelTable: TOMLItemTable, _ specifiers: [String], isAppend: Bool, startToken: Lexer.Token) -> TOMLItemTable {
        // FIXME: Handle TOML requirements (sole definition).
        var into = topLevelTable
        for (i,specifier) in specifiers.enumerated() {
            // If this is an append, then the last key is handled as a special case.
            if isAppend && i == specifiers.count - 1 {
                if let existing = into.items[specifier] {
                    guard case .array(let array) = existing else {
                        error("cannot insert table for key path: \(specifiers)", at: startToken)
                        return topLevelTable
                    }
                    into = TOMLItemTable()
                    array.items.append(.table(contents: into))
                } else {
                    let array = TOMLItemArray()
                    let table = TOMLItemTable()
                    array.items.append(.table(contents: table))
                    into.items[specifier] = .array(contents: array)
                    into = table
                }
                continue
            }
                    
            if let existing = into.items[specifier] {
                switch existing {
                case .array(let contents):
                    guard case .table(let table) = contents.items.last! else {
                        error("cannot insert table for key path: \(specifiers)", at: startToken)
                        return topLevelTable
                    }
                    into = table
                case .table(let contents):
                    into = contents
                default:
                    error("cannot insert table for key path: \(specifiers)", at: startToken)
                    return topLevelTable
                }
            } else {
                let table = TOMLItemTable()
                into.items[specifier] = .table(contents: table)
                into = table
            }
        }
        return into
    }

    /// Parse a table specifier (list of keys describing the key path to the
    /// item), including the terminating brackets.
    ///
    /// - Parameter isAppend: Whether the specifier should end with double brackets.
    private mutating func parseTableSpecifier(_ isAppend: Bool) -> [String]? {
        let startToken = lookahead
            
        // Parse all of the specifiers.
        var specifiers: [String] = []
        while lookahead != .eof && lookahead != .rSquare {
            // Parse the next specifier.
            switch eat() {
            case .stringLiteral(let value):
                specifiers.append(value)
            case .identifier(let value):
                specifiers.append(value)

            case let token:
                error("unexpected token in table specifier", at: token)
                skipToEndOfLine()
                return nil
            }

            // Consume the specifier separator, if present.
            if !consumeIf({ $0 == .period }) {
                // If we didn't have a period, then should be at the end of the specifier.
                break
            }
        }

        // Consume the trailing brackets.
        if !consumeIf({ $0 == .rSquare }) {
            error("expected terminating ']' in table specifier", at: lookahead)
            skipToEndOfLine()
            return specifiers
        }
        if isAppend && !consumeIf({ $0 == .rSquare }) {
            error("expected terminating ']]' in table specifier", at: lookahead)
            skipToEndOfLine()
            return specifiers
        }

        // Consume the trailing newline.
        if !consumeIf({ $0 == .eof || $0 == .newline }) {
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
    private mutating func error(_ message: String, at: Lexer.Token) {
        errors.append(message)
    }
    
    /// Consume the next token from the lexer, skipping whitespace and comments.
    private mutating func eat() -> Lexer.Token {
        let result = lookahead
        // Get the next token, skipping whitespace and comments.
        repeat {
            lookahead = lexer.next()
        } while lookahead == .comment || lookahead == .whitespace
        return result
    }

    /// Consume a token if it matches a particular block.
    private mutating func consumeIf(_ match: (Lexer.Token) -> Bool) -> Bool {
        if match(lookahead) {
            let _ = eat()
            return true
        }
        return false
    }
    
    /// Skip tokens until the next newline (or EOF) is reached.
    private mutating func skipToEndOfLine() {
        loop: while true {
            switch eat() {
            case .eof: fallthrough
            case .newline:
                break loop
            default:
                continue
            }
        }
    }

    /// Parse the contents of a table, stopping at the next table marker.
    private mutating func parseTableContents(_ table: TOMLItemTable) {
        // Parse assignments until we reach the EOF or a new table record.
        while lookahead != .eof && lookahead != .lSquare {
            // If we have a bare newline, ignore it.
            if consumeIf({ $0 == .newline }) {
                continue
            }

            // Otherwise, we should have an assignment.
            parseAssignment(table)
        }
    }

    /// Parse an individual table assignment.
    private mutating func parseAssignment(_ table: TOMLItemTable) {
        // Parse the LHS.
        let key: String
        switch eat() {
        case .number(let value):
            key = value
        case .identifier(let value):
            key = value
        case .stringLiteral(let value):
            key = value

        case let token:
            error("unexpected token while parsing assignment", at: token)
            skipToEndOfLine()
            return
        }

        // Expect an '='.
        guard consumeIf({ $0 == .equals }) else {
            error("unexpected token while parsing assignment", at: lookahead)
            skipToEndOfLine()
            return
        }

        // Parse the RHS.
        let result: TOMLItem = parseItem()

        // Expect a newline or EOF.
        if !consumeIf({ $0 == .eof || $0 == .newline }) {
            error("unexpected trailing token in assignment", at: lookahead)
            skipToEndOfLine()
        }
        
        table.items[key] = result
    }

    /// Parse an individual item.
    private mutating func parseItem() -> TOMLItem {
        let token = eat()
        switch token {
        case .number(let spelling):
            if let numberItem = parseNumberItem(spelling) {
                return numberItem
            } else {
                error("invalid number value in assignment", at: token)
                skipToEndOfLine()
                return .string(value: "<<invalid>>")
            }
        case .identifier(let string):
            return .string(value: string)
        case .stringLiteral(let string):
            return .string(value: string)
        case .boolean(let value):
            return .bool(value: value)

        case .lSquare:
            return parseInlineArray()
            
        default:
            error("unexpected token while parsing assignment", at: token)
            skipToEndOfLine()
            return .string(value: "<<invalid>>")
        }
    }
    
    /// Parse an inline array.
    ///
    /// The token stream is assumed to be positioned immediately after the opening bracket.
    private mutating func parseInlineArray() -> TOMLItem {
        // Parse items until we reach the closing bracket.
        let array = TOMLItemArray()
        while lookahead != .eof && lookahead != .rSquare {
            // Skip newline tokens in arrays.
            if consumeIf({ $0 == .newline }) {
                continue
            }

            // Otherwise, we should have a valid item.
            //
            // FIXME: We need to arrange for this to handle recovery properly,
            // by not just skipping to the end of the line.
            array.items.append(parseItem())

            // Consume the trailing comma, if present.
            if !consumeIf({ $0 == .comma }) {
                // If we didn't have a comma, then should be at the end of the array.
                break
            }
        }

        // Consume the trailing bracket.
        if !consumeIf({ $0 == .rSquare }) {
            error("missing closing array square bracket", at: lookahead)
            // FIXME: This should skip respecting the current bracket nesting level.
            skipToEndOfLine()
        }

        // FIXME: The TOML spec requires that arrays consist of homogeneous
        // types. We should validate that.

        return .array(contents: array)
    }
    
    private func parseNumberItem(_ spelling: String) -> TOMLItem? {
        
        let normalized = String(spelling.characters.filter { $0 != "_" })

        if let value = Int(normalized) {
            return .int(value: value)
        } else if let value = Float(normalized) {
            return .float(value: value)
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
    static func parse(_ data: Swift.String) throws -> TOMLItem {
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
internal func lexTOML(_ data: String) -> [String] {
    let lexer = Lexer(data)
    return lexer.map { String($0) }
}
