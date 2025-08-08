/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import Foundation

extension ProcessInfo {
    public static func isHostAmazonLinux2(_ content: String? = nil) -> Bool {
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
        let al2_name = "PRETTY_NAME=\"Amazon Linux 2\""
        return contentString.contains(al2_name)
    }

}
