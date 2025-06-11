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

func computeSupportedTestingLibraries(
    for testLibraryOptions: TestLibraryOptions,
    initMode: InitPackage.PackageType,
    swiftCommandState: SwiftCommandState
) -> Set<TestingLibrary> {

    var supportedTemplateTestingLibraries: Set<TestingLibrary> = .init()
    if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
        (initMode == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
        supportedTemplateTestingLibraries.insert(.xctest)
    }
    if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
        (initMode != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
        supportedTemplateTestingLibraries.insert(.swiftTesting)
    }

    return supportedTemplateTestingLibraries

}

