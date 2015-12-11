import XCTest
import XCTestCaseProvider

XCTMain([
	// PathTests.swift
	PathTests(),
	WalkTests(),
	StatTests(),
	RelativePathTests(),

	// ResourcesTests.swift
	ResourcesTests(),

	// ShellTests.swift
	ShellTests(),

	// StringTests.swift
	StringTests(),
	URLTests(),

	// TOMLTests.swift
	TOMLTests(),

    // FileTests.swift
    FileTests(),
])
