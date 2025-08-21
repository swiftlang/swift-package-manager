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

import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration

/// A utility struct that represents a list of traits that would be passed through the command line.
/// This is used for testing purposes, and its use is currently specific to the `TraitTests.swift`
public struct TraitArgumentData {
    public var traitsArgument: String
    public var expectedOutput: String
}

public func getTraitCombinations(_ traitsAndMessage: (traits: String, output: String)...) -> [TraitArgumentData] {
    traitsAndMessage.map { traitListAndMessage in
        TraitArgumentData(traitsArgument: traitListAndMessage.traits, expectedOutput: traitListAndMessage.output)
    }
}
