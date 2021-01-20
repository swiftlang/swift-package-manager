/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public protocol BuildSystemDelegate: AnyObject {
    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, willStartCommand command: BuildSystemCommand)
    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, didStartCommand command: BuildSystemCommand)
    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, didFinishCommand command: BuildSystemCommand)
    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, didUpdateProgressWithText: String, finishedCount: Int, totalCount: Int)

    func buildSystemDidDetectCycleInRules(_ buildSystem: SPMBuildCore.BuildSystem)

    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, didFinishWithResult success: Bool)
    func buildSystemDidCancel(_ buildSystem: SPMBuildCore.BuildSystem)
}

public extension BuildSystemDelegate {
    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, willStartCommand command: BuildSystemCommand) { }

    func buildSystem(_ buildSystem: SPMBuildCore.BuildSystem, didUpdateProgressWithText: String, finishedCount: Int, totalCount: Int) { }

    func buildSystemDidDetectCycleInRules(_ buildSystem: SPMBuildCore.BuildSystem) { }
    func buildSystemDidCancel(_ buildSystem: SPMBuildCore.BuildSystem) { }
}
