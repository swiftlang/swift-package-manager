/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(Glibc)
@_exported import Glibc
#elseif os(Windows)
@_exported import MSVCRT
@_exported import WinSDK
#else
@_exported import Darwin.C
#endif

@_exported import TSCclibc

#if os(Windows)
// char *realpath(const char *path, char *resolved_path);
public func realpath(
    _ path: String,
    _ resolvedPath: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  fatalError("realpath is unimplemented")
}

// char *mkdtemp(char *template);
public func mkdtemp(
    _ template: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  fatalError("mkdtemp is unimplemented")
}

// int mkstemps(char *template, int suffixlen);
public func mkstemps(
    _ template: UnsafeMutablePointer<CChar>?,
    _ suffixlen: Int32
) -> Int32 {
  guard let template = template else { return -EINVAL }
  return String(cString: template).withCString(encodedAs: UTF16.self) {
    let capacity: Int = wcslen($0) + 1
    return $0.withMemoryRebound(to: wchar_t.self, capacity: capacity) {
      guard _wmktemp_s(UnsafeMutablePointer(mutating: $0), capacity) == 0 else {
        return -EINVAL
      }

      var fd: Int32 = -1
      _wsopen_s(&fd, $0, _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT,
                _SH_DENYNO, _S_IREAD | _S_IWRITE)

      String(decodingCString: $0, as: UTF16.self).utf8CString.withUnsafeBytes {
        template.assign(from: $0.bindMemory(to: CChar.self).baseAddress!,
                        count: $0.count)
      }
      return fd
    }
  }
}
#endif
