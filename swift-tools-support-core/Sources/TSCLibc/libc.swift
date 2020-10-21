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
@_exported import CRT
@_exported import WinSDK
#else
@_exported import Darwin.C
#endif

@_exported import TSCclibc

#if os(Windows)
private func __randname(_ buffer: UnsafeMutablePointer<CChar>) {
  let alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  _ = (0 ..< 6).map { index in
      buffer[index] = CChar(alpha.shuffled().randomElement()!.utf8.first!)
  }
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

  // Attempt to create the directory
  var retries: Int = 100
  repeat {
    __randname(template + length - 6)
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
  guard length >= 6, memcmp(template + length - Int(suffixlen) - 6, "XXXXXX", 6) == 0 else {
    _set_errno(EINVAL)
    return -1
  }

  // Attempt to create file
  var retries: Int = 100
  repeat {
    __randname(template + length - Int(suffixlen) - 6)
    var fd: CInt = -1
    if _sopen_s(&fd, template, _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT,
                _SH_DENYNO, _S_IREAD | _S_IWRITE) == 0 {
      return fd
    }
    retries = retries - 1
  } while retries > 0

  return -1
}
#endif
