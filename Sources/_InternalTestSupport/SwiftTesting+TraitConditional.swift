
/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.FileManager
import class Foundation.ProcessInfo
import Basics
import Testing

extension Trait where Self == Testing.ConditionTrait {
    /// Skip test if the host operating system does not match the running OS.
    public static func requireHostOS(_ os: OperatingSystem, when condition: Bool = true) -> Self {
        enabled("This test requires a \(os) host OS.") {
            ProcessInfo.hostOperatingSystem == os && condition
        }
    }

    /// Skip test if the host operating system matches the running OS.
    public static func skipHostOS(_ os: OperatingSystem, _ comment: Comment? = nil) -> Self {
        disabled(comment ?? "This test cannot run on a \(os) host OS.") {
            ProcessInfo.hostOperatingSystem == os
        }
    }

    /// Skip test unconditionally
    public static func skip(_ comment: Comment? = nil) -> Self {
        disabled(comment ?? "Unconditional skip, a comment should be added for the reason") { true }
    }

    /// Skip test if the environment is self hosted.
    public static func skipSwiftCISelfHosted(_ comment: Comment? = nil) -> Self {
        disabled(comment ?? "SwiftCI is self hosted") {
            ProcessInfo.processInfo.environment["SWIFTCI_IS_SELF_HOSTED"] != nil
        }
    }

    /// Skip test if the test environment has a restricted network access, i.e. cannot get to internet.
    public static func requireUnrestrictedNetworkAccess(_ comment: Comment? = nil) -> Self {
        disabled(comment ?? "CI Environment has restricted network access") {
            ProcessInfo.processInfo.environment["SWIFTCI_RESTRICTED_NETWORK_ACCESS"] != nil
        }
    }

    /// Skip test if built by XCode.
    public static func skipIfXcodeBuilt() -> Self {
        disabled("Tests built by Xcode") {
            #if Xcode
            true
            #else
            false
            #endif
        }
    }

    /// Skip test if compiler is older than 6.2.
    public static var requireSwift6_2: Self {
        enabled("This test requires Swift 6.2, or newer.") {
            #if compiler(>=6.2)
            true
            #else
            false
            #endif
        }
    }
}
