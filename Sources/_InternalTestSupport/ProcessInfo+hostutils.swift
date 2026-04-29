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
import Foundation

extension ProcessInfo {
    package static func isHost(osName: String, _ content: String? = nil) -> Bool {
        let contentString: String
        if let content {
            contentString = content
        } else {
            let osReleasePath = "/etc/os-release"
            do {
                contentString = try String(contentsOfFile: osReleasePath, encoding: .utf8)
            } catch {
                return false
            }
        }
        return contentString.contains(osName)
    }

    public static func isHostAmazonLinux2() -> Bool {
        let name = "PRETTY_NAME=\"Amazon Linux 2\""
        return Self.isHost(osName: name)
    }

    public static func isHostUbuntu20_04_bookworm() -> Bool {
        let name = "PRETTY_NAME=\"Ubuntu 20.04"
        return Self.isHost(osName: name)
    }

    public static func isHostUbuntu22_04_jammy() -> Bool {
        let name = "PRETTY_NAME=\"Ubuntu 22.04"
        return Self.isHost(osName: name)
    }

    public static func isHostUbuntu24_04_noble() -> Bool {
        let name = "PRETTY_NAME=\"Ubuntu 24.04"
        return Self.isHost(osName: name)
    }

    public static func isHostRHEL9() -> Bool {
        do {
            let name = "PRETTY_NAME=\"Red Hat Enterprise Linux 9"
            return Self.isHost(osName: name)
        } catch {
            return false
        }
    }
}
