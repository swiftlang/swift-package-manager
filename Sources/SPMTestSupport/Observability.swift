/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import struct TSCBasic.Lock
import func XCTest.XCTFail
import func XCTest.XCTAssertEqual

extension ObservabilitySystem {
    public static func bootstrapForTesting() -> TestingObservability {
        let testingObservability = TestingObservability()
        Self.bootstrapGlobal(factory: testingObservability.factory)
        return testingObservability
    }
}

public struct TestingObservability {
    fileprivate let factory = Factory()

    public var diagnostics: [Basics.Diagnostic] {
        self.factory.diagnosticsCollector.diagnostics
    }

    public var hasErrorDiagnostics: Bool {
        self.factory.diagnosticsCollector.hasErrors
    }

    public var hasWarningDiagnostics: Bool {
        self.factory.diagnosticsCollector.hasWarnings
    }

    struct Factory: ObservabilityFactory {
        fileprivate let diagnosticsCollector = AccumulatingDiagnosticsCollector()

        var diagnosticsHandler: DiagnosticsHandler {
            return diagnosticsCollector.handle
        }
    }
}

private final class AccumulatingDiagnosticsCollector: CustomStringConvertible {
    public private (set) var diagnostics: [Basics.Diagnostic]
    private let lock = Lock()

    public init() {
        self.diagnostics = .init()
    }

    public func handle(_ diagnostic: Basics.Diagnostic) {
        self.lock.withLock {
            self.diagnostics.append(diagnostic)
        }
    }

    public var hasErrors: Bool {
        let diagnostics = self.lock.withLock { self.diagnostics }
        return diagnostics.contains(where: { $0.severity == .error })
    }

    public var hasWarnings: Bool {
        let diagnostics = self.lock.withLock { self.diagnostics }
        return diagnostics.contains(where: { $0.severity == .warning })
    }

    public var description: String {
        let diagnostics = self.lock.withLock { self.diagnostics }
        return "\(diagnostics)"
    }
}

public func XCTAssertNoDiagnostics(_ diagnostics: [Basics.Diagnostic], file: StaticString = #file, line: UInt = #line) {
    if diagnostics.isEmpty { return }
    let description = diagnostics.map({ "- " + $0.description }).joined(separator: "\n")
    XCTFail("Found unexpected diagnostics: \n\(description)", file: file, line: line)
}

public func testDiagnostics(
    _ diagnostics: [Basics.Diagnostic],
    ignoreNotes: Bool = false,
    file: StaticString = #file,
    line: UInt = #line,
    handler: (DiagnosticsTestResult) throws -> Void
) {
    let testResult = DiagnosticsTestResult(diagnostics, ignoreNotes: ignoreNotes)

    do {
        try handler(testResult)
    } catch {
        XCTFail("error \(String(describing: error))", file: file, line: line)
    }

    if !testResult.uncheckedDiagnostics.isEmpty {
        XCTFail("unchecked diagnostics \(testResult.uncheckedDiagnostics)", file: file, line: line)
    }
}

/// Helper to check diagnostics in the engine.
public class DiagnosticsTestResult {
    fileprivate var uncheckedDiagnostics: [Basics.Diagnostic]

    init(_ diagnostics: [Basics.Diagnostic], ignoreNotes: Bool = false) {
        self.uncheckedDiagnostics = diagnostics
    }

    public func check(
        diagnostic message: StringPattern,
        severity: DiagnosticMessage.Severity,
        context: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !self.uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let diagnostic: Basics.Diagnostic = self.uncheckedDiagnostics.removeFirst()

        XCTAssertMatch(diagnostic.message, message, file: file, line: line)
        XCTAssertEqual(diagnostic.severity, severity, file: file, line: line)
        XCTAssertEqual(diagnostic.context?.description, context?.description, file: file, line: line)
    }

    public func checkUnordered(
        diagnostic diagnosticPattern: StringPattern,
        severity: DiagnosticMessage.Severity,
        context: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !self.uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let matching = self.uncheckedDiagnostics.filter { diagnosticPattern ~= $0.message }
        if matching.isEmpty {
            return XCTFail("No diagnostics match \(diagnosticPattern)", file: file, line: line)
        } else if matching.count == 1, let diagnostic = matching.first, let index = self.uncheckedDiagnostics.firstIndex(where: { $0 == diagnostic }) {
            XCTAssertEqual(diagnostic.severity, severity, file: file, line: line)
            XCTAssertEqual(diagnostic.context?.description, context?.description, file: file, line: line)
            self.uncheckedDiagnostics.remove(at: index)
        } else {
            if let index = matching.firstIndex(where: { diagnostic in
                diagnostic.severity == severity &&
                diagnostic.context?.description == context?.description
            }) {
                self.uncheckedDiagnostics.remove(at: index)
            }
        }
    }
}
