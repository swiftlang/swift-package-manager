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
private extension String {
  func withCStringW<Result>(_ body: (UnsafePointer<wchar_t>, Int) throws -> Result) rethrows -> Result {
    return try withCString(encodedAs: UTF16.self) {
      let capacity: Int = wcslen($0) + 1
      return try $0.withMemoryRebound(to: wchar_t.self, capacity: capacity) {
        try body($0, capacity)
      }
    }
  }
}

private extension UnsafeMutablePointer where Pointee == CChar {
  func assign(from source: UnsafePointer<wchar_t>) {
    String(decodingCString: source, as: UTF16.self).utf8CString.withUnsafeBytes {
      assign(from: $0.bindMemory(to: CChar.self).baseAddress!,
             count: $0.count)
    }
  }
}

// char *realpath(const char *path, char *resolved_path);
public func realpath(
    _ path: String,
    _ resolvedPath: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  let result: UnsafeMutablePointer<CChar>
  if let resolvedPath = resolvedPath {
    result = resolvedPath
  } else {
    result = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAX_PATH))
  }
  return String(cString: result).withCStringW { resultW, capacity in
    return path.withCStringW { pathW, _ in
      guard _wfullpath(UnsafeMutablePointer(mutating: resultW), pathW, capacity) != nil else {
        return nil
      }
      result.assign(from: resultW)
      return result
    }
  }
}

// char *mkdtemp(char *template);
public func mkdtemp(
    _ template: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  guard let template = template else { return nil }

  func createDirectory() -> UnsafeMutablePointer<CChar>? {
    let path = String(String(cString: template).dropLast(6) +
               String(Int.random(in: 1..<1000000)))
    return path.withCStringW { pathW, _ in
      guard CreateDirectoryW(pathW, nil) else {
        return nil
      }
      template.assign(from: pathW)
      return template
    }
  }

  var result: UnsafeMutablePointer<CChar>?
  repeat {
    result = createDirectory()
  } while result == nil && Int32(GetLastError()) == ERROR_ALREADY_EXISTS

  return result
}

// int mkstemps(char *template, int suffixlen);
public func mkstemps(
    _ template: UnsafeMutablePointer<CChar>?,
    _ suffixlen: Int32
) -> Int32 {
  guard let template = template else { return -EINVAL }
  return String(cString: template).withCStringW { templateW, capacity in
    guard _wmktemp_s(UnsafeMutablePointer(mutating: templateW), capacity) == 0 else {
      return -EINVAL
    }

    var fd: Int32 = -1
    _wsopen_s(&fd, templateW, _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT,
              _SH_DENYNO, _S_IREAD | _S_IWRITE)

    template.assign(from: templateW)
    return fd
  }
}
#endif
