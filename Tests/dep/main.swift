import XCTest
import XCTestCaseProvider

XCTMain([
	// DependencyGraphTests.swift
	VersionGraphTests(),

	// ManifestTests.swift
	ManifestTests(),

	// FunctionalBuildTests.swift
	FunctionalBuildTests(),

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
])
