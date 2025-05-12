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

import struct Basics.AbsolutePath
import protocol Basics.FileSystem

import struct SwiftDiagnostics.Diagnostic
import struct SwiftDiagnostics.DiagnosticCategory
import protocol SwiftDiagnostics.DiagnosticMessage
import enum SwiftDiagnostics.DiagnosticSeverity
import struct SwiftDiagnostics.DiagnosticsFormatter
import struct SwiftDiagnostics.FixIt
import protocol SwiftDiagnostics.FixItMessage
import struct SwiftDiagnostics.GroupedDiagnostics
import struct SwiftDiagnostics.MessageID

@_spi(FixItApplier)
import enum SwiftIDEUtils.FixItApplier

import struct SwiftParser.Parser

import struct SwiftSyntax.AbsolutePosition
import struct SwiftSyntax.SourceFileSyntax
import class SwiftSyntax.SourceLocationConverter
import struct SwiftSyntax.Syntax

import struct TSCBasic.ByteString
import struct TSCUtility.SerializedDiagnostics

private enum Error: Swift.Error {
    case unexpectedDiagnosticSeverity
    case failedToResolveSourceLocation
}

// FIXME: An abstraction for tests to work around missing memberwise initializers in `TSCUtility.SerializedDiagnostics`.
protocol AnySourceLocation {
    var filename: String { get }
    var line: UInt64 { get }
    var column: UInt64 { get }
    var offset: UInt64 { get }
}

// FIXME: An abstraction for tests to work around missing memberwise initializers in `TSCUtility.SerializedDiagnostics`.
protocol AnyFixIt {
    associatedtype SourceLocation: AnySourceLocation

    var start: SourceLocation { get }
    var end: SourceLocation { get }
    var text: String { get }
}

// FIXME: An abstraction for tests to work around missing memberwise initializers in `TSCUtility.SerializedDiagnostics`.
protocol AnyDiagnostic {
    associatedtype SourceLocation: AnySourceLocation
    associatedtype FixIt: AnyFixIt where FixIt.SourceLocation == SourceLocation

    var text: String { get }
    var level: SerializedDiagnostics.Diagnostic.Level { get }
    var location: SourceLocation? { get }
    var category: String? { get }
    var categoryURL: String? { get }
    var flag: String? { get }
    var ranges: [(SourceLocation, SourceLocation)] { get }
    var fixIts: [FixIt] { get }
}

extension AnyDiagnostic {
    var isPrimary: Bool {
        self.level != .note
    }

    var isNote: Bool {
        !self.isPrimary
    }

    var isIgnored: Bool {
        self.level == .ignored
    }

    var hasFixIt: Bool {
        !self.fixIts.isEmpty
    }

    var hasNoLocation: Bool {
        self.location == nil
    }
}

extension SerializedDiagnostics.Diagnostic: AnyDiagnostic {}
extension SerializedDiagnostics.SourceLocation: AnySourceLocation {}
extension SerializedDiagnostics.FixIt: AnyFixIt {}

/// The backing API for `SwiftFixitCommand`.
package struct SwiftFixIt /*: ~Copyable */ {
    private typealias DiagnosticsPerFile = [SourceFile: [SwiftDiagnostics.Diagnostic]]

    private let fileSystem: any FileSystem

    private let diagnosticsPerFile: DiagnosticsPerFile

    package init(
        diagnosticFiles: [AbsolutePath],
        categories: Set<String> = [],
        fileSystem: any FileSystem
    ) throws {
        // Deserialize the diagnostics.
        let diagnostics = try diagnosticFiles.map { path in
            let fileContents = try fileSystem.readFileContents(path)
            return try TSCUtility.SerializedDiagnostics(bytes: fileContents).diagnostics
        }.joined()

        self = try SwiftFixIt(
            diagnostics: diagnostics,
            categories: categories,
            fileSystem: fileSystem
        )
    }

    init<Diagnostic: AnyDiagnostic>(
        diagnostics: some Collection<Diagnostic>,
        categories: Set<String>,
        fileSystem: any FileSystem
    ) throws {
        self.fileSystem = fileSystem

        func shouldSkip(primaryDiagnosticWithNotes: some Collection<Diagnostic>) -> Bool {
            let diagnostic = primaryDiagnosticWithNotes[primaryDiagnosticWithNotes.startIndex]

            // Skip if ignored.
            if diagnostic.isIgnored {
                return true
            }

            // Skip if no location.
            if diagnostic.hasNoLocation {
                return true
            }

            // Skip if categories were given and the diagnostic does not
            // belong to any of them.
            if !categories.isEmpty {
                guard let category = diagnostic.category, categories.contains(category) else {
                    return true
                }
            }

            let notes = primaryDiagnosticWithNotes.dropFirst()

            // Consider the diagnostic compromised if a note does not have a
            // location.
            if notes.contains(where: \.hasNoLocation) {
                return true
            }

            let numberOfNotesWithFixIts = notes.count(where: \.hasFixIt)
            switch numberOfNotesWithFixIts {
            case 0:
                // Skip if neither the primary diagnostic nor any of its notes
                // has a fix-it.
                return !diagnostic.hasFixIt
            case 1:
                return false
            default:
                // Skip if more than 1 note has a fix-it. These diagnostics
                // generally require user intervention.
                // TODO: This will have to done lazier once we support printing them.
                return true
            }
        }

        // Build a map from source files to `SwiftDiagnostics` diagnostics.
        var diagnosticsPerFile: DiagnosticsPerFile = [:]
        var diagnosticConverter = DiagnosticConverter(fileSystem: fileSystem)

        var nextPrimaryIndex = diagnostics.startIndex
        while nextPrimaryIndex != diagnostics.endIndex {
            let currentPrimaryIndex = nextPrimaryIndex
            precondition(diagnostics[currentPrimaryIndex].isPrimary)

            // Shift the index to the next primary diagnostic.
            repeat {
                diagnostics.formIndex(after: &nextPrimaryIndex)
            } while nextPrimaryIndex != diagnostics.endIndex && diagnostics[nextPrimaryIndex].isNote

            let primaryDiagnosticWithNotes = diagnostics[currentPrimaryIndex ..< nextPrimaryIndex]

            if shouldSkip(primaryDiagnosticWithNotes: primaryDiagnosticWithNotes) {
                continue
            }

            for diagnostic in primaryDiagnosticWithNotes {
                // We are only interested in diagnostics with fix-its.
                // TODO: This will have to change once we support printing them.
                guard diagnostic.hasFixIt else {
                    continue
                }

                let (sourceFile, convertedDiagnostic) = try diagnosticConverter.diagnostic(from: diagnostic)

                diagnosticsPerFile[consume sourceFile, default: []].append(consume convertedDiagnostic)
            }
        }

        self.diagnosticsPerFile = diagnosticsPerFile
    }

    package func applyFixIts() throws {
        // Bulk-apply fix-its to each file and write the results back.
        for (sourceFile, diagnostics) in self.diagnosticsPerFile {
            let result = SwiftIDEUtils.FixItApplier.applyFixes(
                from: diagnostics,
                filterByMessages: nil,
                to: sourceFile.syntax
            )

            try self.fileSystem.writeFileContents(sourceFile.path, string: consume result)
        }
    }
}

extension SwiftDiagnostics.DiagnosticSeverity {
    fileprivate init?(from level: TSCUtility.SerializedDiagnostics.Diagnostic.Level) {
        switch level {
        case .ignored:
            return nil
        case .note:
            self = .note
        case .warning:
            self = .warning
        case .error, .fatal:
            self = .error
        case .remark:
            self = .remark
        }
    }
}

private struct DeserializedDiagnosticMessage: SwiftDiagnostics.DiagnosticMessage {
    let message: String
    let severity: SwiftDiagnostics.DiagnosticSeverity
    let category: SwiftDiagnostics.DiagnosticCategory?

    var diagnosticID: SwiftDiagnostics.MessageID {
        .init(domain: "swift-fixit", id: "\(Self.self)")
    }
}

private struct DeserializedFixItMessage: SwiftDiagnostics.FixItMessage {
    var message: String { "" }

    var fixItID: SwiftDiagnostics.MessageID {
        .init(domain: "swift-fixit", id: "\(Self.self)")
    }
}

private struct SourceFile {
    let path: AbsolutePath
    let syntax: SwiftSyntax.SourceFileSyntax

    let sourceLocationConverter: SwiftSyntax.SourceLocationConverter

    init(path: AbsolutePath, in fileSystem: borrowing some FileSystem) throws {
        self.path = path

        let bytes = try fileSystem.readFileContents(path)

        self.syntax = bytes.contents.withUnsafeBufferPointer { pointer in
            SwiftParser.Parser.parse(source: pointer)
        }

        self.sourceLocationConverter = SwiftSyntax.SourceLocationConverter(
            fileName: path.pathString,
            tree: self.syntax
        )
    }

    func position(of location: borrowing some AnySourceLocation) throws -> AbsolutePosition {
        guard try AbsolutePath(validating: location.filename) == self.path else {
            // Wrong source file.
            throw Error.failedToResolveSourceLocation
        }

        guard location.offset == 0 else {
            return AbsolutePosition(utf8Offset: Int(location.offset))
        }

        return self.sourceLocationConverter.position(
            ofLine: Int(location.line),
            column: Int(location.column)
        )
    }

    func node(at location: some AnySourceLocation) throws -> Syntax {
        let position = try position(of: location)

        if let token = syntax.token(at: position) {
            return SwiftSyntax.Syntax(token)
        }

        if position == self.syntax.endPosition {
            // FIXME: EOF token is not included in '.token(at: position)'
            // We might want to include it, but want to avoid special handling.
            if let token = syntax.lastToken(viewMode: .all) {
                return SwiftSyntax.Syntax(token)
            }

            return Syntax(self.syntax)
        }

        // position out of range.
        throw Error.failedToResolveSourceLocation
    }
}

extension SourceFile: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.syntax == rhs.syntax
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.syntax)
    }
}

private struct DiagnosticConverter /*: ~Copyable */ {
    private struct SourceFileCache /*: ~Copyable */ {
        private let fileSystem: any FileSystem

        private var sourceFiles: [AbsolutePath: SourceFile]

        init(fileSystem: any FileSystem) {
            self.fileSystem = fileSystem
            self.sourceFiles = [:]
        }

        subscript(location: some AnySourceLocation) -> SourceFile {
            mutating get throws {
                let path = try AbsolutePath(validating: location.filename)

                if let cached = sourceFiles[path] {
                    return cached
                }

                let sourceFile = try SourceFile(path: path, in: fileSystem)
                sourceFiles[path] = sourceFile

                return sourceFile
            }
        }
    }

    private var sourceFileCache: SourceFileCache

    init(fileSystem: any FileSystem) {
        self.sourceFileCache = SourceFileCache(fileSystem: fileSystem)
    }
}

extension DiagnosticConverter {
    // We expect a fix-it to be in the same source file as the diagnostic it is
    // attached to. The opposite can hurt clarity and is more difficult and
    // less efficient to model and process in general. The compiler may want to
    // actually guard against this pattern and establish a convention to instead
    // emit notes with those fix-its.
    private static func fixIt(
        from diagnostic: borrowing some AnyDiagnostic,
        in sourceFile: /* borrowing */ SourceFile
    ) throws -> SwiftDiagnostics.FixIt {
        let changes = try diagnostic.fixIts.map { fixIt in
            let startPosition = try sourceFile.position(of: fixIt.start)
            let endPosition = try sourceFile.position(of: fixIt.end)

            return SwiftDiagnostics.FixIt.Change.replaceText(
                range: startPosition ..< endPosition,
                with: fixIt.text,
                in: Syntax(sourceFile.syntax)
            )
        }

        return SwiftDiagnostics.FixIt(message: DeserializedFixItMessage(), changes: changes)
    }

    private static func highlights(
        from diagnostic: borrowing some AnyDiagnostic,
        in sourceFile: /* borrowing */ SourceFile
    ) throws -> [Syntax] {
        try diagnostic.ranges.map { startLocation, endLocation in
            let startPosition = try sourceFile.position(of: startLocation)
            let endPosition = try sourceFile.position(of: endLocation)

            var highlightedNode = try sourceFile.node(at: startLocation)

            // Walk up from the start token until we find a syntax node that matches
            // the highlight range.
            while true {
                // If this syntax matches our starting/ending positions, add the
                // highlight and we're done.
                if highlightedNode.positionAfterSkippingLeadingTrivia == startPosition
                    && highlightedNode.endPositionBeforeTrailingTrivia == endPosition
                {
                    break
                }

                // Go up to the parent.
                guard let parent = highlightedNode.parent else {
                    break
                }

                highlightedNode = parent
            }

            return highlightedNode
        }
    }

    typealias Diagnostic = (sourceFile: SourceFile, diagnostic: SwiftDiagnostics.Diagnostic)

    mutating func diagnostic(
        from diagnostic: borrowing some AnyDiagnostic
    ) throws -> Diagnostic {
        guard !diagnostic.fixIts.isEmpty else {
            preconditionFailure("Expected diagnostic with fix-its")
        }

        guard let location = diagnostic.location else {
            preconditionFailure("Diagnostic without location cannot be converted")
        }

        let message: DeserializedDiagnosticMessage
        do {
            guard let severity = SwiftDiagnostics.DiagnosticSeverity(from: diagnostic.level) else {
                preconditionFailure("Diagnostic with 'ignored' severity cannot be converted")
            }

            let category: SwiftDiagnostics.DiagnosticCategory? =
                if let category = diagnostic.category {
                    .init(name: category, documentationURL: diagnostic.categoryURL)
                } else {
                    nil
                }

            message = .init(
                message: diagnostic.text,
                severity: severity,
                category: category
            )
        }

        let sourceFile = try sourceFileCache[location]

        return try Diagnostic(
            sourceFile: sourceFile,
            diagnostic: SwiftDiagnostics.Diagnostic(
                node: sourceFile.node(at: location),
                position: sourceFile.position(of: location),
                message: message,
                highlights: Self.highlights(from: diagnostic, in: sourceFile),
                fixIts: [
                    Self.fixIt(from: diagnostic, in: sourceFile),
                ]
            )
        )
    }
}
