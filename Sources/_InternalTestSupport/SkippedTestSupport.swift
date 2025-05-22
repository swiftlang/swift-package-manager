
/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.FileManager
import class Foundation.ProcessInfo
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

    /// Constructs a condition trait that causes a test to be disabled if the Foundation process spawning implementation
    /// is not using `posix_spawn_file_actions_addchdir`.
    public static var requireThreadSafeWorkingDirectory: Self {
        disabled("Thread-safe process working directory support is unavailable.") {
            // Amazon Linux 2 has glibc 2.26, and glibc 2.29 is needed for posix_spawn_file_actions_addchdir_np support
            FileManager.default.contents(atPath: "/etc/system-release")
                .map { String(decoding: $0, as: UTF8.self) == "Amazon Linux release 2 (Karoo)\n" } ?? false
        }
    }

    /// Skips the test if running on a platform which lacks the ability for build tasks to set a working directory due to lack of requisite system API.
    ///
    /// Presently, relevant platforms include Amazon Linux 2 and OpenBSD.
    ///
    /// - seealso: https://github.com/swiftlang/swift-package-manager/issues/8560
    public static var disableIfWorkingDirectoryUnsupported: Self {
        disabled("https://github.com/swiftlang/swift-package-manager/issues/8560: Thread-safe process working directory support is unavailable on this platform.") {
            !workingDirectoryIsSupported()
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
}

extension Tag.Feature.Command {
    @Tag public static var Package: Tag
    @Tag public static var Build: Tag
    @Tag public static var Test: Tag
    @Tag public static var Run: Tag
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
