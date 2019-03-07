/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX
import SPMLibc
import Foundation

#if os(macOS)
public typealias DistributedLock = NSDistributedLock
#else
public typealias DistributedLock = _DistributedLock
#endif

/// A lock that multiple applications on multiple hosts can use to restrict access to some shared resource, such as a file.
public final class _DistributedLock {

  private let path: String
  private let lock = NSLock()

  /// Returns the time the receiver was acquired by any of the `DistributedLock` objects using the same path.
  public var lockDate: Date? {
    guard let pathStat = try? POSIX.stat(self.path) else { return nil }

    #if canImport(Darwin)
      let seconds = pathStat.st_birthtimespec.tv_sec
      let nanoseconds = pathStat.st_birthtimespec.tv_nsec
    #else
      let seconds = pathStat.st_mtim.tv_sec
      let nanoseconds = pathStat.st_mtim.tv_nsec
    #endif

    return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds / 1_000_000_000))
  }

  /// Initializes an `DistributedLock` object to use as the lock the file-system entry specified by a given path.
  ///
  /// - Parameter path: All of `path` up to the last component itself must exist.
  ///                   You can use FileManager to create (and set permissions) for any nonexistent intermediate directories.
  public init?(path: String) {
    guard FileManager.default.directoryCanBeCreatedAtPath(path) else { return nil }
    self.path = path
  }

  deinit {
    invalidate()
  }

  /// Attempts to acquire the receiver and immediately returns a Boolean value that indicates whether the attempt was successful.
  ///
  /// - Returns: `true` if the attempt to acquire the receiver was successful, otherwise `false`.
  public func `try`() -> Bool {
    self.lock.lock()
    defer {
      self.lock.unlock()
    }

    let fileSystemPath = FileManager.default.fileSystemRepresentation(withPath: self.path)
    if SPMLibc.mkdir(fileSystemPath, SPMLibc.S_IRWXU | SPMLibc.S_IRGRP | SPMLibc.S_IXGRP | SPMLibc.S_IROTH | SPMLibc.S_IXOTH) != 0 {
      return false
    }

    return true
  }

  /// This method always succeeds unless the lock has been damaged.
  /// If another process has already unlocked or broken the lock, this method has no effect.
  /// You should generally use `unlock()` rather than `break()` to relinquish a lock.
  public func `break`() {
    lock.lock()
    try? FileManager.default.removeItem(atPath: self.path)
    lock.unlock()
  }

  /// Relinquishes the receiver.
  public func unlock() {
    `break`()
  }

  private func invalidate() {
    `break`()
  }
}

extension _DistributedLock: CustomStringConvertible {
  public var description: String {
    return "\(type(of:self))(\(Unmanaged.passUnretained(self).toOpaque())) locked: \(lock)  path: '\(self.path)'"
  }

}

private extension FileManager {

  @nonobjc func directoryCanBeCreatedAtPath(_ path: String) -> Bool {
    if self.fileAccessibleForMode((path as NSString).deletingLastPathComponent, mode: SPMLibc.F_OK) {
      let fileSystemPath = self.fileSystemRepresentation(withPath: path)
      if SPMLibc.mkdir(fileSystemPath, SPMLibc.S_IRWXU | SPMLibc.S_IRWXG) != 0 {
        return errno == EEXIST
      } else {
        SPMLibc.rmdir(fileSystemPath)
        return true
      }
    }
    return false
  }

  @nonobjc func fileAccessibleForMode(_ path: String, mode: Int32) -> Bool {
    let fileSystemPath = self.fileSystemRepresentation(withPath: path)
    return SPMLibc.access(fileSystemPath, mode) == 0
  }
}
