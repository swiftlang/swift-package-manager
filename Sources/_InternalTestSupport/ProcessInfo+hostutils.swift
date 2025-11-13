/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import Foundation

extension ProcessInfo {
    package static func isHostOs(prettyName: String, content: String? = nil) -> Bool {
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
        let name = "PRETTY_NAME=\"\(prettyName)\""
        return contentString.contains(name)

    }
    public static func isHostAmazonLinux2() -> Bool {
        return Self.isHostOs(prettyName: "Amazon Linux 2")
    }

    public static func isHostDebian12() -> Bool {
        return Self.isHostOs(prettyName: "Debian GNU/Linux 12 (bookworm)")
    }

}
