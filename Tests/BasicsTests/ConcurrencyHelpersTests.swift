//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@testable import Basics
import TSCTestSupport
import Testing

struct ConcurrencyHelpersTest {
    let queue = DispatchQueue(label: "ConcurrencyHelpersTest", attributes: .concurrent)

    @Test
    func threadSafeKeyValueStore() throws {
        for _ in 0 ..< 100 {
            let sync = DispatchGroup()

            var expected = [Int: Int]()
            let lock = NSLock()

            let cache = ThreadSafeKeyValueStore<Int, Int>()
            for index in 0 ..< 1000 {
                self.queue.async(group: sync) {
                    Thread.sleep(forTimeInterval: Double.random(in: 100 ... 300) * 1.0e-6)
                    let value = Int.random(in: Int.min ..< Int.max)
                    lock.withLock {
                        expected[index] = value
                    }
                    cache.memoize(index) {
                        value
                    }
                    cache.memoize(index) {
                        Int.random(in: Int.min ..< Int.max)
                    }
                }
            }

            try #require(sync.wait(timeout: .now() + .seconds(2)) == .success)
            expected.forEach { key, value in
                #expect(cache[key] == value)
            }
        }
    }

    @Test
    func threadSafeArrayStore() throws {
        for _ in 0 ..< 100 {
            let sync = DispatchGroup()

            var expected = [Int]()
            let lock = NSLock()

            let cache = ThreadSafeArrayStore<Int>()
            for _ in 0 ..< 1000 {
                self.queue.async(group: sync) {
                    Thread.sleep(forTimeInterval: Double.random(in: 100 ... 300) * 1.0e-6)
                    let value = Int.random(in: Int.min ..< Int.max)
                    lock.withLock {
                        expected.append(value)
                    }
                    cache.append(value)
                }
            }

            try #require(sync.wait(timeout: .now() + .seconds(2)) == .success)
            let expectedSorted = expected.sorted()
            let resultsSorted = cache.get().sorted()
            #expect(expectedSorted == resultsSorted)
        }
    }

    @Test
    func threadSafeBox() throws {
        for _ in 0 ..< 100 {
            let sync = DispatchGroup()

            var winner: Int?
            let lock = NSLock()

            let serial = DispatchQueue(label: "testThreadSafeBoxSerial")

            let cache = ThreadSafeBox<Int>()
            for index in 0 ..< 1000 {
                self.queue.async(group: sync) {
                    Thread.sleep(forTimeInterval: Double.random(in: 100 ... 300) * 1.0e-6)
                    serial.async(group: sync) {
                        lock.withLock {
                            if winner == nil {
                                winner = index
                            }
                        }
                        cache.memoize {
                            index
                        }
                    }
                }
            }

            try #require(sync.wait(timeout: .now() + .seconds(2)) == .success)
            #expect(cache.get() == winner)
        }
    }
}
