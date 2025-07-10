
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

extension Trait where Self == Testing.Bug {
    public static func SWBINTTODO(_ comment: Comment) -> Self {
        bug(nil, id: 0, comment)
    }
}
extension Tag {
    public enum TestSize {}
    public enum Feature {}
    @Tag public static var UserWorkflow: Tag
}

extension Tag.TestSize {
    @Tag public static var small: Tag
    @Tag public static var medium: Tag
    @Tag public static var large: Tag
}

extension Tag.Feature {
    public enum Command {}
    public enum PackageType {}

    @Tag public static var CodeCoverage: Tag
    @Tag public static var Resource: Tag
    @Tag public static var SpecialCharacters: Tag
    @Tag public static var Traits: Tag
}


extension Tag.Feature.Command {
    public enum Package {}
    @Tag public static var Build: Tag
    @Tag public static var Test: Tag
    @Tag public static var Run: Tag
}


extension Tag.Feature.Command.Package {
    @Tag public static var Init: Tag
    @Tag public static var DumpPackage: Tag
    @Tag public static var DumpSymbolGraph: Tag
    @Tag public static var Plugin: Tag
}
extension Tag.Feature.PackageType {
    @Tag public static var Library: Tag
    @Tag public static var Executable: Tag
    @Tag public static var Tool: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var BuildToolPlugin: Tag
    @Tag public static var CommandPlugin: Tag
    @Tag public static var Macro: Tag
}
