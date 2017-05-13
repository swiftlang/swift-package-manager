/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

import XCTest

public enum StringCheck: ExpressibleByStringLiteral {
    case equal(String)
    case contains(String)

    func check(
        input: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        switch self {
        case .equal(let str):
            XCTAssertEqual(str, input, file: file, line: line)
        case .contains(let str):
            XCTAssert(input.contains(str), "\(str) does not contain \(input)", file: file, line: line)
        }
    }

    public init(stringLiteral value: String) {
        self = .equal(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

public func DiagnosticsEngineTester(
    _ engine: DiagnosticsEngine,
    file: StaticString = #file,
    line: UInt = #line,
    result: (DiagnosticsEngineResult) throws -> Void
) {
    let engineResult = DiagnosticsEngineResult(engine)

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

    init(_ engine: DiagnosticsEngine) {
        self.uncheckedDiagnostics = engine.diagnostics
    }

    public func check(
        diagnostic: StringCheck,
        checkContains: Bool = false,
        behavior: Diagnostic.Behavior,
        location: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let location = location ?? UnknownLocation.location.localizedDescription
        let theDiagnostic = uncheckedDiagnostics.removeFirst()

        diagnostic.check(input: theDiagnostic.localizedDescription, file: file, line: line)
        XCTAssertEqual(theDiagnostic.behavior, behavior, file: file, line: line)
        XCTAssertEqual(theDiagnostic.location.localizedDescription, location, file: file, line: line)
    }
}
