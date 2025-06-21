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

/// A BuildSystemDelegate implementation which captures serialized diagnostics paths for all completed tasks.
package class DiagnosticsCapturingBuildSystemDelegate: BuildSystemDelegate {
    package private(set) var serializedDiagnosticsPathsByTarget: [String?: Set<AbsolutePath>] = [:]

    package init() {}

    package func buildSystem(_ buildSystem: any BuildSystem, didFinishCommand command: BuildSystemCommand) {
        serializedDiagnosticsPathsByTarget[command.targetName, default: []].formUnion(command.serializedDiagnosticPaths)
    }
}
