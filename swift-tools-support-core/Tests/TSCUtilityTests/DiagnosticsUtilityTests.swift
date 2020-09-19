/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility

class DiagnosticsTests: XCTestCase {
    
    func testDiagnosticsLocationProviding() throws {
        let diagnostics = DiagnosticsEngine()
        
        struct BazLocation: DiagnosticLocation {
            let name: String

            var description: String {
                return name
            }
        }

        struct CustomError: Error, CustomStringConvertible, DiagnosticLocationProviding {
            var location: String?
            var diagnosticLocation: DiagnosticLocation? {
                return location.flatMap{ BazLocation(name: $0) }
            }
            var description: String {
                return "provided location is '\(location ?? "nil")'"
            }
        }

        diagnostics.with(location: BazLocation(name: "elsewhere")) { diagnostics in
            diagnostics.wrap {
                throw CustomError(location: "somewhere")
            }
            diagnostics.wrap {
                throw CustomError(location: nil)
            }
        }
        
        XCTAssertEqual(diagnostics.diagnostics.count, 2)
        
        let firstDiagnostic = try XCTUnwrap(diagnostics.diagnostics.first)
        XCTAssertEqual(firstDiagnostic.location.description, "somewhere")
        XCTAssertEqual(firstDiagnostic.description, "provided location is 'somewhere'")
        XCTAssertEqual(firstDiagnostic.message.behavior, .error)
        
        let secondDiagnostic = try XCTUnwrap(diagnostics.diagnostics.last)
        XCTAssertEqual(secondDiagnostic.location.description, "elsewhere")
        XCTAssertEqual(secondDiagnostic.description, "provided location is 'nil'")
        XCTAssertEqual(secondDiagnostic.message.behavior, .error)
    }
}
