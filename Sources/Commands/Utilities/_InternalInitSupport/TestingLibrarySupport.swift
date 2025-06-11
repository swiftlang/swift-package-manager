//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_spi(SwiftPMInternal)
import CoreCommands
import Workspace

/// Computes the set of supported testing libraries to be included in a package template
/// based on the user's specified testing options, the type of package being initialized,
/// and the Swift command state.
///
/// This function takes into account whether the testing libraries were explicitly requested
/// (via command-line flags or configuration) or implicitly enabled based on package type.
///
/// - Parameters:
///   - testLibraryOptions: The testing library preferences specified by the user.
///   - initMode: The type of package being initialized (e.g., executable, library, macro).
///   - swiftCommandState: The command state which includes environment and context information.
///
/// - Returns: A set of `TestingLibrary` values that should be included in the generated template.
func computeSupportedTestingLibraries(
    for testLibraryOptions: TestLibraryOptions,
    initMode: InitPackage.PackageType,
    swiftCommandState: SwiftCommandState
) -> Set<TestingLibrary> {
    var supportedTemplateTestingLibraries: Set<TestingLibrary> = .init()

    // XCTest is enabled either explicitly, or implicitly for macro packages.
    if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
        (initMode == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState))
    {
        supportedTemplateTestingLibraries.insert(.xctest)
    }

    // Swift Testing is enabled either explicitly, or implicitly for non-macro packages.
    if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
        (initMode != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState))
    {
        supportedTemplateTestingLibraries.insert(.swiftTesting)
    }

    return supportedTemplateTestingLibraries
}
