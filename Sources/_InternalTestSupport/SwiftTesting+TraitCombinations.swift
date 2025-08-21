/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration

/// A utility struct that represents a list of traits that would be passed through the command line.
public struct TraitCombination {
    public var traitsArgument: String
    public var expectedOutput: String
}

public func getTraitCombinations(_ traitsAndMessage: (traits: String, output: String)...) -> [TraitCombination] {
    traitsAndMessage.map { traitListAndMessage in
        TraitCombination(traitsArgument: traitListAndMessage.traits, expectedOutput: traitListAndMessage.output)
    }
}

// TODO bp: to remove once https://github.com/swiftlang/swift-package-manager/pull/9012 is merged.
public struct BuildData {
    public let buildSystem: BuildSystemProvider.Kind
    public let config: BuildConfiguration
}

public func getBuildData(for buildSystems: [BuildSystemProvider.Kind]) -> [BuildData] {
    buildSystems.flatMap { buildSystem in
        BuildConfiguration.allCases.compactMap { config in
            return BuildData(buildSystem: buildSystem, config: config)
        }
    }
 }
