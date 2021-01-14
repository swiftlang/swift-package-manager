/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public protocol BuildSystemDelegate: AnyObject {
    func buildSystem(_ buildSystem: BuildSystem, willStartCommand command: BuildSystemCommand)
    func buildSystem(_ buildSystem: BuildSystem, didStartCommand command: BuildSystemCommand)
    func buildSystem(_ buildSystem: BuildSystem, didFinishCommand command: BuildSystemCommand)

    func buildSystemDidDetectCycleInRules(_ buildSystem: BuildSystem)

    func buildSystem(_ buildSystem: BuildSystem, didFinishWithResult success: Bool)
    func buildSystemDidCancel(_ buildSystem: BuildSystem)
}

extension BuildSystemDelegate {
    func buildSystem(_ buildSystem: BuildSystem, willStartCommand command: BuildSystemCommand) { }
    func buildSystemDidDetectCycleInRules(_ buildSystem: BuildSystem) { }
    func buildSystemDidCancel(_ buildSystem: BuildSystem) { }
}
