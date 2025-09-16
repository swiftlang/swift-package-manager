/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

public import Foundation

public enum OperatingSystem: Hashable, Sendable {
    case macOS
    case windows
    case linux
    case android
    case freebsd
    case unknown
}


extension ProcessInfo {
    public static var hostOperatingSystem: OperatingSystem {
        #if os(macOS)
        .macOS
        #elseif os(Linux)
        .linux
        #elseif os(Windows)
        .windows
        #elseif os(FreeBSD)
        .freebsd
        #else
        .unknown
        #endif
    }

    #if os(Windows)
    public static let EOL = "\r\n"
    #else
    public static let EOL = "\n"
    #endif

    #if os(Windows)
    public static let exeSuffix = ".exe"
    #else
    public static let exeSuffix = ""
    #endif

    #if os(Windows)
    public static let batSuffix = ".bat"
    #else
    public static let batSuffix = ""
    #endif
}
