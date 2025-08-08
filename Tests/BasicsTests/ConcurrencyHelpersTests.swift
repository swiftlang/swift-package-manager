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
    @Suite
    struct ThreadSafeKeyValueStoreTests {

        @Test(
            .bug("https://github.com/swiftlang/swift-package-manager/issues/8770"),
        )
        func threadSafeKeyValueStore() async throws {
            for num in 0..<100 {
                var expected = [Int: Int]()
                let lock = NSLock()

                let cache = ThreadSafeKeyValueStore<Int, Int>()

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0..<1000 {
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100...300) * 1000))
                            let value = Int.random(in: Int.min..<Int.max)
                            lock.withLock {
                                expected[index] = value
                            }
                            cache.memoize(index) {
                                value
                            }
                            cache.memoize(index) {
                                Int.random(in: Int.min..<Int.max)
                            }
                        }
                    }
                    try await group.waitForAll()
                }

                expected.forEach { key, value in
                    #expect(cache[key] == value, "Iteration \(num) failed")
                }
            }
        }

        @Test(
            .bug("https://github.com/swiftlang/swift-package-manager/issues/8770"),
        )
        func threadSafeArrayStore() async throws {
            for num in 0..<100 {
                var expected = [Int]()
                let lock = NSLock()

                let cache = ThreadSafeArrayStore<Int>()

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<1000 {
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100...300) * 1000))
                            let value = Int.random(in: Int.min..<Int.max)
                            lock.withLock {
                                expected.append(value)
                            }
                            cache.append(value)
                        }
                    }
                    try await group.waitForAll()
                }

                let expectedSorted = expected.sorted()
                let resultsSorted = cache.get().sorted()
                #expect(expectedSorted == resultsSorted, "Iteration \(num) failed")
            }
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8770"),
    )
    func threadSafeBox() async throws {
        // Actor to serialize the critical section that was previously handled by the serial queue
        actor SerialCoordinator {
            func processTask(_ index: Int, winner: inout Int?, cache: ThreadSafeBox<Int>) {
                // This simulates the serial queue behavior - both winner determination
                // and cache memoization happen atomically in the same serial context
                if winner == nil {
                    winner = index
                }
                cache.memoize {
                    index
                }
            }
        }

        for num in 0..<100 {
            var winner: Int?
            let cache = ThreadSafeBox<Int>()
            let coordinator = SerialCoordinator()

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<1000 {
                    group.addTask {
                        // Random sleep to simulate concurrent access timing
                        try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100...300) * 1000))

                        // Process both winner determination and cache memoization serially
                        await coordinator.processTask(index, winner: &winner, cache: cache)
                    }
                }
                try await group.waitForAll()
            }
            #expect(cache.get() == winner, "Iteration \(num) failed")
        }
    }

    @Suite
    struct AsyncOperationQueueTests {
        fileprivate actor ResultsTracker {
            var results = [Int]()
            var maxConcurrent = 0
            var currentConcurrent = 0

            func incrementConcurrent() {
                currentConcurrent += 1
                maxConcurrent = max(maxConcurrent, currentConcurrent)
            }

            func decrementConcurrent() {
                currentConcurrent -= 1
            }

            func appendResult(_ value: Int) {
                results.append(value)
            }
        }

        @Test
        func limitsConcurrentOperations() async throws {
            let queue = AsyncOperationQueue(concurrentTasks: 5)

            let totalTasks = 20
            let tracker = ResultsTracker()

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<totalTasks {
                    group.addTask {
                        try await queue.withOperation {
                            await tracker.incrementConcurrent()
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            await tracker.decrementConcurrent()
                            await tracker.appendResult(index)
                        }
                    }
                }
                try await group.waitForAll()
            }

            let maxConcurrent = await tracker.maxConcurrent
            let results = await tracker.results

            // Check that at no point did we exceed 5 concurrent operations
            #expect(maxConcurrent == 5)
            #expect(results.count == totalTasks)
        }

        @Test
        func passesThroughWhenUnderConcurrencyLimit() async throws {
            let queue = AsyncOperationQueue(concurrentTasks: 5)

            let totalTasks = 5
            let tracker = ResultsTracker()

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<totalTasks {
                    group.addTask {
                        try await queue.withOperation {
                            await tracker.incrementConcurrent()
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            await tracker.decrementConcurrent()
                            await tracker.appendResult(index)
                        }
                    }
                }
                try await group.waitForAll()
            }

            let maxConcurrent = await tracker.maxConcurrent
            let results = await tracker.results

            // Check that we never exceeded the concurrency limit
            #expect(maxConcurrent <= 5)
            #expect(results.count == totalTasks)
        }

        @Test
        func handlesImmediateCancellation() async throws {
            let queue = AsyncOperationQueue(concurrentTasks: 5)
            let totalTasks = 20
            let tracker = ResultsTracker()

            await #expect(throws: _Concurrency.CancellationError.self) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Cancel the task group immediately
                    group.cancelAll()

                    for index in 0..<totalTasks {
                        group.addTask {
                            try await queue.withOperation {
                                if Task.isCancelled {
                                    throw _Concurrency.CancellationError()
                                }
                                await tracker.incrementConcurrent()
                                // sleep for a long time to ensure cancellation can occur.
                                // If this is too short the cancellation may be triggered after
                                // all tasks have completed.
                                try await Task.sleep(nanoseconds: 10_000_000_000)
                                await tracker.decrementConcurrent()
                                await tracker.appendResult(index)
                            }
                        }
                    }
                    try await group.waitForAll()
                }
            }

            let maxConcurrent = await tracker.maxConcurrent
            let results = await tracker.results

            #expect(maxConcurrent <= 5)
            #expect(results.count < totalTasks)
        }

        @Test
        func handlesCancellationDuringWait() async throws {
            let queue = AsyncOperationQueue(concurrentTasks: 5)
            let totalTasks = 20
            let tracker = ResultsTracker()

            await #expect(throws: _Concurrency.CancellationError.self) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0..<totalTasks {
                        group.addTask {
                            try await queue.withOperation {
                                if Task.isCancelled {
                                    throw _Concurrency.CancellationError()
                                }
                                await tracker.incrementConcurrent()
                                try? await Task.sleep(nanoseconds: 5_000_000)
                                await tracker.decrementConcurrent()
                                await tracker.appendResult(index)
                            }
                        }
                    }

                    group.addTask { [group] in
                        group.cancelAll()
                    }
                    try await group.waitForAll()
                }
            }

            let maxConcurrent = await tracker.maxConcurrent
            let results = await tracker.results

            #expect(maxConcurrent <= 5)
            #expect(results.count < totalTasks)
        }
    }
}
