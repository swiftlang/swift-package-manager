//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// BuildSystem delegate
public protocol BuildSystemDelegate: AnyObject {
    ///Called when build command is about to start.
    func buildSystem(_ buildSystem: BuildSystem, willStartCommand command: BuildSystemCommand)

    /// Called when build command did start.
    func buildSystem(_ buildSystem: BuildSystem, didStartCommand command: BuildSystemCommand)

    /// Called when build task did update progress.
    func buildSystem(_ buildSystem: BuildSystem, didUpdateTaskProgress text: String)

    /// Called when build command did finish.
    func buildSystem(_ buildSystem: BuildSystem, didFinishCommand command: BuildSystemCommand)

    func buildSystemDidDetectCycleInRules(_ buildSystem: BuildSystem)

    /// Called when build did finish.
    func buildSystem(_ buildSystem: BuildSystem, didFinishWithResult success: Bool)

    /// Called when build did cancel
    func buildSystemDidCancel(_ buildSystem: BuildSystem)
}

public extension BuildSystemDelegate {
    func buildSystem(_ buildSystem: BuildSystem, willStartCommand command: BuildSystemCommand) { }
    func buildSystem(_ buildSystem: BuildSystem, didStartCommand command: BuildSystemCommand) { }
    func buildSystem(_ buildSystem: BuildSystem, didUpdateTaskProgress text: String) { }
    func buildSystem(_ buildSystem: BuildSystem, didFinishCommand command: BuildSystemCommand) { }
    func buildSystemDidDetectCycleInRules(_ buildSystem: BuildSystem) { }
    func buildSystem(_ buildSystem: BuildSystem, didFinishWithResult success: Bool) { }
    func buildSystemDidCancel(_ buildSystem: BuildSystem) { }
}
