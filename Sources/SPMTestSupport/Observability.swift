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
    public static func makeForTesting() -> TestingObservability {
        let collector = TestingObservability.Collector()
        let observabilitySystem = ObservabilitySystem(collector)
        return TestingObservability(collector: collector, topScope: observabilitySystem.topScope)
    }

    public static var NOOP: ObservabilityScope {
        ObservabilitySystem({ _, _ in }).topScope
    }
}

public struct TestingObservability {
    private let collector: Collector
    public let topScope: ObservabilityScope

    fileprivate init(collector: Collector, topScope: ObservabilityScope) {
        self.collector = collector
        self.topScope = topScope
    }

    public var diagnostics: [Basics.Diagnostic] {
        self.collector.diagnostics.get()
    }

    public var hasErrorDiagnostics: Bool {
        self.collector.hasErrors
    }

    public var hasWarningDiagnostics: Bool {
        self.collector.hasWarnings
    }

    struct Collector: ObservabilityHandlerProvider, DiagnosticsHandler, CustomStringConvertible {
        var diagnosticsHandler: DiagnosticsHandler { return self }

        let diagnostics: ThreadSafeArrayStore<Basics.Diagnostic>

        init() {
            self.diagnostics = .init()
        }

        // TODO: do something useful with scope
        func handleDiagnostic(scope: ObservabilityScope, diagnostic: Basics.Diagnostic) {
            self.diagnostics.append(diagnostic)
        }

        var hasErrors: Bool {
            let diagnostics = self.diagnostics.get()
            return diagnostics.contains(where: { $0.severity == .error })
        }

        var hasWarnings: Bool {
            let diagnostics = self.diagnostics.get()
            return diagnostics.contains(where: { $0.severity == .warning })
        }

        var description: String {
            let diagnostics = self.diagnostics.get()
            return "\(diagnostics)"
        }
    }
}

public func XCTAssertNoDiagnostics(_ diagnostics: [Basics.Diagnostic], problemsOnly: Bool = true, file: StaticString = #file, line: UInt = #line) {
    let diagnostics = problemsOnly ? diagnostics.filter({ $0.severity >= .warning }) : diagnostics
    if diagnostics.isEmpty { return }
    let description = diagnostics.map({ "- " + $0.description }).joined(separator: "\n")
    XCTFail("Found unexpected diagnostics: \n\(description)", file: file, line: line)
}

public func testDiagnostics(
    _ diagnostics: [Basics.Diagnostic],
    problemsOnly: Bool = true,
    file: StaticString = #file,
    line: UInt = #line,
    handler: (DiagnosticsTestResult) throws -> Void
) {
    let diagnostics = problemsOnly ? diagnostics.filter({ $0.severity >= .warning }) : diagnostics
    let testResult = DiagnosticsTestResult(diagnostics)

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

    init(_ diagnostics: [Basics.Diagnostic]) {
        self.uncheckedDiagnostics = diagnostics
    }

    public func check(
        diagnostic message: StringPattern,
        severity: Basics.Diagnostic.Severity,
        metadata: ObservabilityMetadata? = .none,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !self.uncheckedDiagnostics.isEmpty else {
            return XCTFail("No diagnostics left to check", file: file, line: line)
        }

        let diagnostic: Basics.Diagnostic = self.uncheckedDiagnostics.removeFirst()

        XCTAssertMatch(diagnostic.message, message, file: file, line: line)
        XCTAssertEqual(diagnostic.severity, severity, file: file, line: line)
        // FIXME: (diagnostics) compare complete metadata when legacy bridge is removed
        //XCTAssertEqual(diagnostic.metadata, metadata, file: file, line: line)
        XCTAssertEqual(diagnostic.metadata?.droppingLegacyKeys(), metadata?.droppingLegacyKeys(), file: file, line: line)
    }

    public func checkUnordered(
        diagnostic diagnosticPattern: StringPattern,
        severity: Basics.Diagnostic.Severity,
        metadata: ObservabilityMetadata? = .none,
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
            // FIXME: (diagnostics) compare complete metadata when legacy bridge is removed
            //XCTAssertEqual(diagnostic.metadata, metadata, file: file, line: line)
            XCTAssertEqual(diagnostic.metadata?.droppingLegacyKeys(), metadata?.droppingLegacyKeys(), file: file, line: line)
            self.uncheckedDiagnostics.remove(at: index)
        // FIXME: (diagnostics) compare complete metadata when legacy bridge is removed
        //} else if let index = self.uncheckedDiagnostics.firstIndex(where: { diagnostic in diagnostic.severity == severity && diagnostic.metadata == metadata}) {
        } else if let index = self.uncheckedDiagnostics.firstIndex(where: { diagnostic in diagnostic.severity == severity && diagnostic.metadata?.droppingLegacyKeys() == metadata?.droppingLegacyKeys()}) {
            self.uncheckedDiagnostics.remove(at: index)
        }
    }
}
