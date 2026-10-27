//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import SPMBuildCore

/// The testability flags shared by the commands that build products (`swift build` and `swift run`).
struct TestabilityOptions: ParsableArguments {
    @Flag(
        name: .customLong("testability"),
        inversion: .prefixedEnableDisable,
        help: "Determines whether to build with testability enabled. By default, testability is enabled for debug builds and disabled for release builds."
    )
    var enableTestability: Bool?

    /// Applies an explicit `--enable-testability` / `--disable-testability` choice to `parameters`.
    func apply(to parameters: inout BuildParameters) {
        if let enableTestability {
            parameters.testingParameters.explicitlyEnabledTestability = enableTestability
        }
    }
}
