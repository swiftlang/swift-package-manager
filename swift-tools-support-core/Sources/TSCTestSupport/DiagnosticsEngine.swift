/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

import XCTest

public func DiagnosticsEngineTester(
    _ engine: DiagnosticsEngine,
    ignoreNotes: Bool = false,
    file: StaticString = #file,
    line: UInt = #line,
    result: (DiagnosticsEngineResult) throws -> Void
) {
    let engineResult = DiagnosticsEngineResult(engine, ignoreNotes: ignoreNotes)

    do {
        try result(engineResult)
    } catch {
        XCTFail("error \(String(describing: error))", file: file, line: line)
    }

    if !engineResult.uncheckedDiagnostics.isEmpty {
        XCTFail("unchecked diagnostics \(engineResult.uncheckedDiagnostics)", file: file, line: line)
    }
}

/// Helper to check diagnostics in the engine.
final public class DiagnosticsEngineResult {

    fileprivate var uncheckedDiagnostics: [Diagnostic]

    init(_ engine: DiagnosticsEngine, ignoreNotes: Bool = false) {
        self.uncheckedDiagnostics = engine.diagnostics
    }

    public func check(
        diagnostic: StringPattern,
        checkContains: Bool = false,
        behavior: Diagnostic.Behavior,
        location: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let location = location ?? UnknownLocation.location.description
        let theDiagnostic = uncheckedDiagnostics.removeFirst()

        XCTAssertMatch(theDiagnostic.description, diagnostic, file: file, line: line)
        XCTAssertEqual(theDiagnostic.message.behavior, behavior, file: file, line: line)
        XCTAssertEqual(theDiagnostic.location.description, location, file: file, line: line)
    }

    public func checkUnordered(
        diagnostic diagnosticPattern: StringPattern,
        checkContains: Bool = false,
        behavior: Diagnostic.Behavior,
        location: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let locationDescription = location ?? UnknownLocation.location.description
        let matchIndex = uncheckedDiagnostics.firstIndex(where: { diagnostic in
            diagnosticPattern ~= diagnostic.description &&
            diagnostic.message.behavior == behavior &&
            diagnostic.location.description == locationDescription
        })

        if let index = matchIndex {
            uncheckedDiagnostics.remove(at: index)
        }
    }
}
