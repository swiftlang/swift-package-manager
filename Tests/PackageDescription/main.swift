import XCTest

#if !os(Linux)
public protocol XCTestCaseProvider {
    var allTests : [(String, () -> ())] { get }
}
#endif

// SharesTests.swift
PackageTests().invokeTest()
