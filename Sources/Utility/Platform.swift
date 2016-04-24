/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.popen

public enum Platform {
    case Darwin
    case Linux(LinuxFlavor)
    
    public enum LinuxFlavor {
        case Debian
    }
    
    // Lazily return current platform.
    public static var currentPlatform = Platform.findCurrentPlatform()
    private static func findCurrentPlatform() -> Platform? {
        guard let uname = try? popen(["uname"]).chomp().lowercased() else { return nil }
        switch uname {
        case "darwin":
            return .Darwin
        case "linux":
            if "/etc/debian_version".isFile {
                return .Linux(.Debian)
            }
        default:
            return nil
        }
        return nil
    }
}
