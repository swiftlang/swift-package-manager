//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import TSCTestSupport
import XCTest

final class ConcurrencyHelpersTest: XCTestCase {
    let queue = DispatchQueue(label: "ConcurrencyHelpersTest", attributes: .concurrent)

    func testThreadSafeKeyValueStore() {
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

            switch sync.wait(timeout: .now() + .seconds(2)) {
            case .timedOut:
                XCTFail("timeout")
            case .success:
                expected.forEach { key, value in
                    XCTAssertEqual(cache[key], value)
                }
            }
        }
    }

    func testThreadSafeArrayStore() {
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

            switch sync.wait(timeout: .now() + .seconds(2)) {
            case .timedOut:
                XCTFail("timeout")
            case .success:
                let expectedSorted = expected.sorted()
                let resultsSorted = cache.get().sorted()
                XCTAssertEqual(expectedSorted, resultsSorted)
            }
        }
    }

    func testThreadSafeBox() {
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

            switch sync.wait(timeout: .now() + .seconds(2)) {
            case .timedOut:
                XCTFail("timeout")
            case .success:
                XCTAssertEqual(cache.get(), winner)
            }
        }
    }
}
