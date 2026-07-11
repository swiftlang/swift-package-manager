//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//
//
// Vendored from swift-async-algorithms to avoid a package dependency. See Vendor/README.md.
// Changes: none.
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

internal struct Lock {
#if canImport(Darwin)
  typealias Primitive = os_unfair_lock
#elseif canImport(Glibc)
  typealias Primitive = pthread_mutex_t
#elseif canImport(WinSDK)
  typealias Primitive = SRWLOCK
#else
  typealias Primitive = Int
#endif
  
  typealias PlatformLock = UnsafeMutablePointer<Primitive>
  let platformLock: PlatformLock

  private init(_ platformLock: PlatformLock) {
    self.platformLock = platformLock
  }
  
  fileprivate static func initialize(_ platformLock: PlatformLock) {
#if canImport(Darwin)
    platformLock.initialize(to: os_unfair_lock())
#elseif canImport(Glibc)
    let result = pthread_mutex_init(platformLock, nil)
    precondition(result == 0, "pthread_mutex_init failed")
#elseif canImport(WinSDK)
    InitializeSRWLock(platformLock)
#endif
  }
  
  fileprivate static func deinitialize(_ platformLock: PlatformLock) {
#if canImport(Glibc)
    let result = pthread_mutex_destroy(platformLock)
    precondition(result == 0, "pthread_mutex_destroy failed")
#endif
    platformLock.deinitialize(count: 1)
  }
  
  fileprivate static func lock(_ platformLock: PlatformLock) {
#if canImport(Darwin)
    os_unfair_lock_lock(platformLock)
#elseif canImport(Glibc)
    pthread_mutex_lock(platformLock)
#elseif canImport(WinSDK)
    AcquireSRWLockExclusive(platformLock)
#endif
  }
  
  fileprivate static func unlock(_ platformLock: PlatformLock) {
#if canImport(Darwin)
    os_unfair_lock_unlock(platformLock)
#elseif canImport(Glibc)
    let result = pthread_mutex_unlock(platformLock)
    precondition(result == 0, "pthread_mutex_unlock failed")
#elseif canImport(WinSDK)
    ReleaseSRWLockExclusive(platformLock)
#endif
  }

  static func allocate() -> Lock {
    let platformLock = PlatformLock.allocate(capacity: 1)
    initialize(platformLock)
    return Lock(platformLock)
  }

  func deinitialize() {
    Lock.deinitialize(platformLock)
  }

  func lock() {
    Lock.lock(platformLock)
  }

  func unlock() {
    Lock.unlock(platformLock)
  }

    /// Acquire the lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }

    // specialise Void return (for performance)
    func withLockVoid(_ body: () throws -> Void) rethrows -> Void {
        try self.withLock(body)
    }
}

struct ManagedCriticalState<State> {
  private final class LockedBuffer: ManagedBuffer<State, Lock.Primitive> {
    deinit {
      withUnsafeMutablePointerToElements { Lock.deinitialize($0) }
    }
  }
  
  private let buffer: ManagedBuffer<State, Lock.Primitive>
  
  init(_ initial: State) {
    buffer = LockedBuffer.create(minimumCapacity: 1) { buffer in
      buffer.withUnsafeMutablePointerToElements { Lock.initialize($0) }
      return initial
    }
  }
  
  func withCriticalRegion<R>(_ critical: (inout State) throws -> R) rethrows -> R {
    try buffer.withUnsafeMutablePointers { header, lock in
      Lock.lock(lock)
      defer { Lock.unlock(lock) }
      return try critical(&header.pointee)
    }
  }
}

extension ManagedCriticalState: @unchecked Sendable where State: Sendable { }
