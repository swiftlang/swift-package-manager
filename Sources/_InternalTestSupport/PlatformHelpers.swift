

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics

import Testing

public func isWindows() -> Bool {
    #if os(Windows)
    return true
    #else
    return false
    #endif
}

public func isLinux() -> Bool {
    #if os(Linux)
    return true
    #else
    return false
    #endif
}

public func isMacOS() -> Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
}

public func isRealSigningIdentityTestEnabled() -> Bool {
    #if ENABLE_REAL_SIGNING_IDENTITY_TEST
    return true
    #else
    return false
    #endif
}

public func isEnvironmentVariableSet(_ variableName: EnvironmentKey) -> Bool {
    guard let value = Environment.current[variableName] else { return false }
    return !value.isEmpty
}
