import XCTest

// Support building the "enumerated"-tests style, on OS X.
#if !os(Linux)
public protocol XCTestCaseProvider {
    var allTests : [(String, () -> ())] { get }
}
#endif

// DependencyGraphTests.swift
VersionGraphTests().invokeTest()

// ManifestTests.swift
ManifestTests().invokeTest()

// FunctionalBuildTests.swift
FunctionalBuildTests().invokeTest()

// TargetTests.swift
TargetTests().invokeTest()

// UidTests.swift
ProjectTests().invokeTest()

// VersionTests.swift
VersionTests().invokeTest()
