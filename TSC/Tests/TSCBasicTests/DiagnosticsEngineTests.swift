/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic

private struct FooDiag: DiagnosticData {
    let arr: [String]
    let str: String
    let int: Int

    var description: String {
        return "literal \(arr.joined(separator: ", ")) \(int) \(str) bar \(str)"
    }
}

private struct FooLocation: DiagnosticLocation {
    let name: String

    var description: String {
        return name
    }
}

class DiagnosticsEngineTests: XCTestCase {
    func testBasics() {
        let diagnostics = DiagnosticsEngine() 
        diagnostics.emit(.error(
            FooDiag(arr: ["foo", "bar"], str: "str", int: 2)),
            location: FooLocation(name: "foo loc")
        )
        let diag = diagnostics.diagnostics[0]

        XCTAssertEqual(diagnostics.diagnostics.count, 1)
        XCTAssertEqual(diag.location.description, "foo loc")
        XCTAssertEqual(diag.description, "literal foo, bar 2 str bar str")
        XCTAssertEqual(diag.message.behavior, .error)
    }

    func testMerging() {
        let engine1 = DiagnosticsEngine() 
        engine1.emit(
            .error(FooDiag(arr: ["foo", "bar"], str: "str", int: 2)),
            location: FooLocation(name: "foo loc")
        )
        XCTAssertEqual(engine1.diagnostics.count, 1)

        let engine2 = DiagnosticsEngine() 
        engine2.emit(
            .error(FooDiag(arr: ["foo", "bar"], str: "str", int: 2)),
            location: FooLocation(name: "foo loc")
        )
        engine2.emit(
            .error(FooDiag(arr: ["foo", "bar"], str: "str", int: 2)),
            location: FooLocation(name: "foo loc")
        )
        XCTAssertEqual(engine2.diagnostics.count, 2)

        engine1.merge(engine2)
        XCTAssertEqual(engine1.diagnostics.count, 3)
        XCTAssertEqual(engine2.diagnostics.count, 2)
    }

    func testHandlers() {
        var handledDiagnostics: [Diagnostic] = []
        let handler: DiagnosticsEngine.DiagnosticsHandler = { diagnostic in 
            handledDiagnostics.append(diagnostic)
        }

        let diagnostics = DiagnosticsEngine(handlers: [handler])
        let location = FooLocation(name: "location")
        diagnostics.emit(
            .error(FooDiag(arr: ["foo", "bar"], str: "str", int: 2)),
            location: location
        )
        diagnostics.emit(.error(StringDiagnostic("diag 2")), location: location)
        diagnostics.emit(.note(StringDiagnostic("diag 3")), location: location)
        diagnostics.emit(.remark(StringDiagnostic("diag 4")), location: location)
        diagnostics.emit(.error(StringDiagnostic("end")), location: location)

        XCTAssertEqual(handledDiagnostics.count, 5)
        for diagnostic in handledDiagnostics {
            XCTAssertEqual(diagnostic.location.description, location.description)
        }
        XCTAssertEqual(handledDiagnostics[0].description, "literal foo, bar 2 str bar str")
        XCTAssertEqual(handledDiagnostics[1].description, "diag 2")
        XCTAssertEqual(handledDiagnostics[2].description, "diag 3")
        XCTAssertEqual(handledDiagnostics[3].description, "diag 4")
        XCTAssertEqual(handledDiagnostics[4].description, "end")
    }
}
