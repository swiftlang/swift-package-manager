/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCLibc

public final class DLHandle {
  #if os(Windows)
    typealias Handle = HMODULE
  #else
    typealias Handle = UnsafeMutableRawPointer
  #endif
    var rawValue: Handle? = nil

    init(rawValue: Handle) {
        self.rawValue = rawValue
    }

    deinit {
        precondition(rawValue == nil, "DLHandle must be closed or explicitly leaked before destroying")
    }

    public func close() throws {
        if let handle = rawValue {
          #if os(Windows)
            guard FreeLibrary(handle) else {
                throw DLError.close("Failed to FreeLibrary: \(GetLastError())")
            }
          #else
            guard dlclose(handle) == 0 else {
                throw DLError.close(dlerror() ?? "unknown error")
            }
          #endif
        }
        rawValue = nil
    }

    public func leak() {
        rawValue = nil
    }
}

public struct DLOpenFlags: RawRepresentable, OptionSet {

  #if !os(Windows)
    public static let lazy: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LAZY)
    public static let now: DLOpenFlags = DLOpenFlags(rawValue: RTLD_NOW)
    public static let local: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LOCAL)
    public static let global: DLOpenFlags = DLOpenFlags(rawValue: RTLD_GLOBAL)

    // Platform-specific flags.
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    public static let first: DLOpenFlags = DLOpenFlags(rawValue: RTLD_FIRST)
    public static let deepBind: DLOpenFlags = DLOpenFlags(rawValue: 0)
  #else
    public static let first: DLOpenFlags = DLOpenFlags(rawValue: 0)
  #if !os(Android)
    public static let deepBind: DLOpenFlags = DLOpenFlags(rawValue: RTLD_DEEPBIND)
  #endif
  #endif
  #endif

    public var rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public enum DLError: Swift.Error {
    case `open`(String)
    case close(String)
}

public func dlopen(_ path: String?, mode: DLOpenFlags) throws -> DLHandle {
  #if os(Windows)
    guard let handle = path?.withCString(encodedAs: UTF16.self, LoadLibraryW) else {
        throw DLError.open("LoadLibraryW failed: \(GetLastError())")
    }
  #else
    guard let handle = TSCLibc.dlopen(path, mode.rawValue) else {
        throw DLError.open(dlerror() ?? "unknown error")
    }
  #endif
    return DLHandle(rawValue: handle)
}

public func dlsym<T>(_ handle: DLHandle, symbol: String) -> T? {
  #if os(Windows)
    guard let ptr = GetProcAddress(handle.rawValue!, symbol) else {
        return nil
    }
  #else
    guard let ptr = dlsym(handle.rawValue!, symbol) else {
        return nil
    }
  #endif
    return unsafeBitCast(ptr, to: T.self)
}

public func dlclose(_ handle: DLHandle) throws {
    try handle.close()
}

#if !os(Windows)
public func dlerror() -> String? {
    if let err: UnsafeMutablePointer<Int8> = dlerror() {
        return String(cString: err)
    }
    return nil
}
#endif
