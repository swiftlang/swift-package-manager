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
// NOTE(compnerd) this is unsafe!  This assumes that the template is *ASCII*.
public func mkdtemp(
    _ template: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  // Although the signature of the function is `char *(*)(char *)`, the C
  // library treats it as `char *(*)(char * _Nonull)`.  Most implementations
  // will simply use and trigger a segmentation fault on x86 (and similar faults
  // on other architectures) when the memory is accessed.  This roughly emulates
  // that by terminating in the case even though it is possible for us to return
  // an error.
  guard let template = template else { fatalError() }

  let length: Int = strlen(template)

  // Validate the precondition: the template must terminate with 6 `X` which
  // will be filled in to generate a unique directory.
  guard length >= 6, memcmp(template + length - 6, "XXXXXX", 6) == 0 else {
    _set_errno(EINVAL)
    return nil
  }

  let stampSuffix = { (buffer: UnsafeMutablePointer<CChar>) in
    let alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    _ = (0 ..< 6).map { index in
        buffer[index] = CChar(alpha.shuffled().randomElement()!.utf8.first!)
    }
  }

  // Attempt to create the directory
  var retries: Int = 100
  repeat {
    stampSuffix(template + length - 6)
    if _mkdir(template) == 0 {
      return template
    }
    retries = retries - 1
  } while retries > 0

  return nil
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
