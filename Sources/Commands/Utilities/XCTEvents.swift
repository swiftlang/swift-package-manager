//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

struct TestEventRecord: Codable {
    let caseFailure: TestCaseFailureRecord?
    let suiteFailure: TestSuiteFailureRecord?

    let bundleEvent: TestBundleEventRecord?
    let suiteEvent: TestSuiteEventRecord?
    let caseEvent: TestCaseEventRecord?

    init(
        caseFailure: TestCaseFailureRecord? = nil,
        suiteFailure: TestSuiteFailureRecord? = nil,
        bundleEvent: TestBundleEventRecord? = nil,
        suiteEvent: TestSuiteEventRecord? = nil,
        caseEvent: TestCaseEventRecord? = nil
    ) {
        self.caseFailure = caseFailure
        self.suiteFailure = suiteFailure
        self.bundleEvent = bundleEvent
        self.suiteEvent = suiteEvent
        self.caseEvent = caseEvent
    }
}

// MARK: - Records

struct TestBundleEventRecord: Codable {
    let bundle: TestBundle
    let event: TestEvent
}

struct TestCaseEventRecord: Codable {
    let testCase: TestCase
    let event: TestEvent
}

struct TestCaseFailureRecord: Codable, CustomStringConvertible {
    let testCase: TestCase
    let issue: TestIssue
    let failureKind: TestFailureKind

    var description: String {
        return "\(issue.sourceCodeContext.description)\(testCase) \(issue.compactDescription)"
    }
}

struct TestSuiteEventRecord: Codable {
    let suite: TestSuiteRecord
    let event: TestEvent
}

struct TestSuiteFailureRecord: Codable {
    let suite: TestSuiteRecord
    let issue: TestIssue
    let failureKind: TestFailureKind
}

// MARK: Primitives

struct TestBundle: Codable {
    let bundleIdentifier: String?
    let bundlePath: String
}

struct TestCase: Codable {
    let name: String
}

struct TestErrorInfo: Codable {
    let description: String
    let type: String
}

enum TestEvent: Codable {
    case start
    case finish
}

enum TestFailureKind: Codable, Equatable {
    case unexpected
    case expected(failureReason: String?)

    var isExpected: Bool {
        switch self {
        case .expected: return true
        case .unexpected: return false
        }
    }
}

struct TestIssue: Codable {
    let type: TestIssueType
    let compactDescription: String
    let detailedDescription: String?
    let associatedError: TestErrorInfo?
    let sourceCodeContext: TestSourceCodeContext
    // TODO: Handle `var attachments: [XCTAttachment]`
}

enum TestIssueType: Codable {
    case assertionFailure
    case performanceRegression
    case system
    case thrownError
    case uncaughtException
    case unmatchedExpectedFailure
    case unknown
}

struct TestLocation: Codable, CustomStringConvertible {
    let file: String
    let line: Int

    var description: String {
        return "\(file):\(line) "
    }
}

struct TestSourceCodeContext: Codable, CustomStringConvertible {
    // TODO: Handle `var callStack: [XCTSourceCodeFrame]`
    let location: TestLocation?

    var description: String {
        return location?.description ?? ""
    }
}

struct TestSuiteRecord: Codable {
    let name: String
}

// MARK: XCTest compatibility

#if false // This is just here for pre-flighting the code generation done in `SwiftTargetBuildDescription`.
import XCTest

extension TestBundle {
    init(_ testBundle: Bundle) {
        self.init(
            bundleIdentifier: testBundle.bundleIdentifier,
            bundlePath: testBundle.bundlePath
        )
    }
}

extension TestCase {
    init(_ testCase: XCTestCase) {
        self.init(name: testCase.name)
    }
}

extension TestErrorInfo {
    init(_ error: Swift.Error) {
        self.init(description: "\(error)", type: "\(Swift.type(of: error))")
    }
}

extension TestIssue {
    init(_ issue: XCTIssue) {
        self.init(
            type: .init(issue.type),
            compactDescription: issue.compactDescription,
            detailedDescription: issue.detailedDescription,
            associatedError: issue.associatedError.map { .init($0) },
            sourceCodeContext: .init(issue.sourceCodeContext)
        )
    }
}

extension TestIssueType {
    init(_ type: XCTIssue.IssueType) {
        switch type {
        case .assertionFailure: self = .assertionFailure
        case .thrownError: self = .thrownError
        case .uncaughtException: self = .uncaughtException
        case .performanceRegression: self = .performanceRegression
        case .system: self = .system
        case .unmatchedExpectedFailure: self = .unmatchedExpectedFailure
        @unknown default: self = .unknown
        }
    }
}

extension TestLocation {
    init(_ location: XCTSourceCodeLocation) {
        self.init(
            file: location.fileURL.absoluteString,
            line: location.lineNumber
        )
    }
}

extension TestSourceCodeContext {
    init(_ context: XCTSourceCodeContext) {
        self.init(
            location: context.location.map { .init($0) }
        )
    }
}

extension TestSuiteRecord {
    init(_ testSuite: XCTestSuite) {
        self.init(name: testSuite.name)
    }
}
#endif
