import XCTest

// Support building the "enumerated"-tests style, on OS X.
#if !os(Linux)
public protocol XCTestCaseProvider {
    var allTests : [(String, () -> ())] { get }
}
#endif

// POSIXTests.swift
PathTests().invokeTest()
WalkTests().invokeTest()
StatTests().invokeTest()
RelativePathTests().invokeTest()

// ResourcesTests.swift
ResourcesTests().invokeTest()

// ShellTests.swift
ShellTests().invokeTest()

// StringTests.swift
StringTests().invokeTest()
URLTests().invokeTest()

// TOMLTests.swift
TOMLTests().invokeTest()
