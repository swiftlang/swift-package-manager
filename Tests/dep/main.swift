import XCTest
import XCTestCaseProvider

XCTMain([
	// DependencyGraphTests.swift
	VersionGraphTests(),

	// ManifestTests.swift
	ManifestTests(),

	// TargetTests.swift
	TargetTests(),

	// UidTests.swift
	ProjectTests(),

	// VersionTests.swift
	VersionTests(),

    // PackageTests.swift
    PackageTests(),
    
    // GetTests.swift
    GetTests(),

    // GitTests.swift
    GitTests(),
])
