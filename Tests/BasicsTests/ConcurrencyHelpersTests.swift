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
            for num in 0 ..< 100 {
                var expected = [Int: Int]()
                let lock = NSLock()

                let cache = ThreadSafeKeyValueStore<Int, Int>()

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0 ..< 1000 {
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100 ... 300) * 1000))
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
            for num in 0 ..< 100 {
                var expected = [Int]()
                let lock = NSLock()

                let cache = ThreadSafeArrayStore<Int>()

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0 ..< 1000 {
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100 ... 300) * 1000))
                            let value = Int.random(in: Int.min ..< Int.max)
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

extension ConcurrencyHelpersTest {
    @Suite struct ThreadSafeBoxTests {
        // MARK: - Basic Functionality Tests

        @Test
        func basicGetAndPut() {
            let box = ThreadSafeBox(42)
            #expect(box.get() == 42)

            box.put(100)
            #expect(box.get() == 100)
        }

        @Test
        func mutateReturningNewValue() {
            let box = ThreadSafeBox(10)
            box.mutate { value in
                value * 2
            }
            #expect(box.get() == 20)
        }

        @Test
        func mutateInPlace() {
            let box = ThreadSafeBox([1, 2, 3])
            box.mutate { value in
                value.append(4)
            }
            #expect(box.get() == [1, 2, 3, 4])
        }

        // MARK: - Optional Value Tests

        @Test
        func optionalInitEmpty() {
            let box = ThreadSafeBox<Int?>()
            #expect(box.get() == nil)
        }

        @Test
        func optionalClear() {
            let box = ThreadSafeBox<Int?>(42)
            #expect(box.get() == 42)

            box.clear()
            #expect(box.get() == nil)
        }

        @Test
        func optionalGetWithDefault() {
            let emptyBox = ThreadSafeBox<Int?>()
            #expect(emptyBox.get(default: 999) == 999)

            let filledBox = ThreadSafeBox<Int?>(42)
            #expect(filledBox.get(default: 999) == 42)
        }

        @Test
        func memoizeComputesOnce() {
            let box = ThreadSafeBox<Int?>()
            var computeCount = 0

            let result1 = box.memoize {
                computeCount += 1
                return 42
            }
            #expect(result1 == 42)
            #expect(computeCount == 1)

            let result2 = box.memoize {
                computeCount += 1
                return 99
            }
            #expect(result2 == 42)
            #expect(computeCount == 1)
        }

        @Test
        func memoizeOptionalNilValue() {
            let box = ThreadSafeBox<Int?>()
            var computeCount = 0

            let result1 = box.memoizeOptional {
                computeCount += 1
                return nil
            }
            #expect(result1 == nil)
            #expect(computeCount == 1)

            // Should recompute since result was nil
            let result2 = box.memoizeOptional {
                computeCount += 1
                return 42
            }
            #expect(result2 == 42)
            #expect(computeCount == 2)

            // Now should use cached value
            let result3 = box.memoizeOptional {
                computeCount += 1
                return 99
            }
            #expect(result3 == 42)
            #expect(computeCount == 2)
        }

        // MARK: - Int Extension Tests

        @Test
        func intIncrement() {
            let box = ThreadSafeBox(0)
            box.increment()
            #expect(box.get() == 1)
            box.increment()
            #expect(box.get() == 2)
        }

        @Test
        func intDecrement() {
            let box = ThreadSafeBox(10)
            box.decrement()
            #expect(box.get() == 9)
            box.decrement()
            #expect(box.get() == 8)
        }

        // MARK: - String Extension Tests

        @Test
        func stringAppend() {
            let box = ThreadSafeBox("Hello")
            box.append(" World")
            #expect(box.get() == "Hello World")
            box.append("!")
            #expect(box.get() == "Hello World!")
        }

        // MARK: - Dynamic Member Lookup Tests

        @Test
        func dynamicMemberReadOnly() {
            struct Person {
                let name: String
                let age: Int
            }

            let box = ThreadSafeBox(Person(name: "Alice", age: 30))
            #expect(box.name == "Alice")
            #expect(box.age == 30)
        }

        @Test
        func dynamicMemberWritable() {
            struct Counter {
                var count: Int
                var label: String
            }

            let box = ThreadSafeBox(Counter(count: 0, label: "Test"))
            #expect(box.count == 0)
            #expect(box.label == "Test")

            box.count = 42
            #expect(box.count == 42)
            #expect(box.label == "Test")

            box.label = "Updated"
            #expect(box.count == 42)
            #expect(box.label == "Updated")
        }

        // MARK: - Thread Safety Tests

        @Test(
            .bug("https://github.com/swiftlang/swift-package-manager/issues/8770"),
        )
        func concurrentMemoization() async throws {
            actor SerialCoordinator {
                func processTask(_ index: Int, winner: inout Int?, cache: ThreadSafeBox<Int?>) {
                    if winner == nil {
                        winner = index
                    }
                    cache.memoize {
                        index
                    }
                }
            }

            for num in 0 ..< 100 {
                var winner: Int?
                let cache = ThreadSafeBox<Int?>()
                let coordinator = SerialCoordinator()

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0 ..< 1000 {
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 100 ... 300) * 1000))
                            await coordinator.processTask(index, winner: &winner, cache: cache)
                        }
                    }
                    try await group.waitForAll()
                }
                #expect(cache.get() == winner, "Iteration \(num) failed")
            }
        }

        @Test
        func concurrentIncrements() async throws {
            let box = ThreadSafeBox(0)
            let iterations = 1000

            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<iterations {
                    group.addTask {
                        box.increment()
                    }
                }
                try await group.waitForAll()
            }

            #expect(box.get() == iterations)
        }

        @Test
        func concurrentMutations() async throws {
            let box = ThreadSafeBox([Int]())

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<100 {
                    group.addTask {
                        box.mutate { value in
                            value.append(index)
                        }
                    }
                }
                try await group.waitForAll()
            }

            let result = box.get()
            #expect(result.count == 100)
            #expect(Set(result).count == 100)
        }

        @Test
        func concurrentDynamicMemberWrites() async throws {
            struct Counter {
                var value: Int
            }

            let box = ThreadSafeBox(Counter(value: 0))

            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<1000 {
                    group.addTask {
                        box.value = i
                    }
                }
                try await group.waitForAll()
            }

            // Value should be one of the concurrent writes
            let finalValue = box.value
            #expect(finalValue >= 0 && finalValue < 1000)
        }
    }

    @Suite struct AsyncThrowingValueMemoizerTests {
        // MARK: - Basic Functionality Tests

        @Test
        func memoizeComputesOnlyOnce() async throws {
            let memoizer = AsyncThrowingValueMemoizer<Int>()
            nonisolated(unsafe) var computeCount = 0

            let result1 = try await memoizer.memoize {
                computeCount += 1
                return 42
            }
            #expect(result1 == 42)
            #expect(computeCount == 1)

            let result2 = try await memoizer.memoize {
                computeCount += 1
                return 99
            }
            #expect(result2 == 42)
            #expect(computeCount == 1)
        }

        @Test
        func memoizeWithAsyncWork() async throws {
            let memoizer = AsyncThrowingValueMemoizer<String>()

            let result = try await memoizer.memoize {
                try await Task.sleep(nanoseconds: 1_000_000)
                return "computed"
            }

            #expect(result == "computed")
        }

        @Test
        func memoizeCachesError() async throws {
            struct TestError: Error, Equatable {}
            let memoizer = AsyncThrowingValueMemoizer<Int>()

            await #expect(throws: TestError.self) {
                try await memoizer.memoize {
                    throw TestError()
                }
            }

            // After error, subsequent calls should return the cached error
            await #expect(throws: TestError.self) {
                try await memoizer.memoize {
                    100
                }
            }
        }

        // MARK: - Concurrency Tests

        @Test
        func concurrentMemoizationSharesWork() async throws {
            let memoizer = AsyncThrowingValueMemoizer<Int>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try await memoizer.memoize {
                            lock.withLock {
                                computeCount += 1
                            }
                            try await Task.sleep(nanoseconds: 10_000_000)
                            return 42
                        }
                    }
                }

                var results = [Int]()
                for try await result in group {
                    results.append(result)
                }

                #expect(results.count == 100)
                #expect(results.allSatisfy { $0 == 42 })
            }

            // Should only compute once despite 100 concurrent calls
            #expect(computeCount == 1)
        }

        @Test
        func concurrentMemoizationWithQuickCompletion() async throws {
            let memoizer = AsyncThrowingValueMemoizer<String>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            try await withThrowingTaskGroup(of: String.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        try await memoizer.memoize {
                            lock.withLock {
                                computeCount += 1
                            }
                            return "value-\(i)"
                        }
                    }
                }

                var results = [String]()
                for try await result in group {
                    results.append(result)
                }

                #expect(results.count == 50)
                // All results should be the same (from the first caller)
                #expect(Set(results).count == 1)
            }

            #expect(computeCount == 1)
        }

        @Test
        func concurrentErrorPropagation() async throws {
            struct TestError: Error {}
            let memoizer = AsyncThrowingValueMemoizer<Int>()
            var errorCount = 0
            let lock = NSLock()

            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        do {
                            _ = try await memoizer.memoize {
                                try await Task.sleep(nanoseconds: 5_000_000)
                                throw TestError()
                            }
                        } catch {
                            lock.withLock {
                                errorCount += 1
                            }
                        }
                    }
                }

                // Consume all results (ignoring errors)
                while let _ = try? await group.next() {}
            }

            // All concurrent calls should receive the error
            #expect(errorCount == 20)
        }

        @Test
        func sequentialMemoizationAfterSuccess() async throws {
            let memoizer = AsyncThrowingValueMemoizer<Int>()

            let first = try await memoizer.memoize {
                try await Task.sleep(nanoseconds: 1_000_000)
                return 42
            }
            #expect(first == 42)

            let second = try await memoizer.memoize {
                try await Task.sleep(nanoseconds: 1_000_000)
                return 99
            }
            #expect(second == 42)
        }

        @Test
        func complexValueType() async throws {
            struct ComplexValue: Sendable, Equatable {
                let id: Int
                let name: String
                let tags: [String]
            }

            let memoizer = AsyncThrowingValueMemoizer<ComplexValue>()

            let result = try await memoizer.memoize {
                try await Task.sleep(nanoseconds: 1_000_000)
                return ComplexValue(id: 1, name: "Test", tags: ["a", "b", "c"])
            }

            #expect(result.id == 1)
            #expect(result.name == "Test")
            #expect(result.tags == ["a", "b", "c"])
        }

        @Test
        func memoizeWithVariableDelay() async throws {
            let memoizer = AsyncThrowingValueMemoizer<Int>()
            nonisolated(unsafe) var firstCallComplete = false
            let lock = NSLock()

            try await withThrowingTaskGroup(of: Int.self) { group in
                // First task with delay
                group.addTask {
                    try await memoizer.memoize {
                        try await Task.sleep(nanoseconds: 20_000_000)
                        lock.withLock {
                            firstCallComplete = true
                        }
                        return 100
                    }
                }

                // Wait a bit then add more tasks
                try await Task.sleep(nanoseconds: 5_000_000)

                for _ in 0..<10 {
                    group.addTask {
                        try await memoizer.memoize {
                            return 999
                        }
                    }
                }

                var results = [Int]()
                for try await result in group {
                    results.append(result)
                }

                #expect(results.count == 11)
                #expect(results.allSatisfy { $0 == 100 })
            }

            let wasFirstCallComplete = lock.withLock { firstCallComplete }
            #expect(wasFirstCallComplete == true)
        }
    }

    @Suite struct AsyncKeyValueMemoizerTests {
        // MARK: - Basic Functionality Tests

        @Test
        func memoizeComputesOncePerKey() async {
            let memoizer = AsyncKeyValueMemoizer<String, Int>()
            nonisolated(unsafe) var computeCount = 0

            let result1 = await memoizer.memoize("key1") {
                computeCount += 1
                return 42
            }
            #expect(result1 == 42)
            #expect(computeCount == 1)

            let result2 = await memoizer.memoize("key1") {
                computeCount += 1
                return 99
            }
            #expect(result2 == 42)
            #expect(computeCount == 1)

            let result3 = await memoizer.memoize("key2") {
                computeCount += 1
                return 100
            }
            #expect(result3 == 100)
            #expect(computeCount == 2)
        }

        @Test
        func memoizeWithAsyncWork() async {
            let memoizer = AsyncKeyValueMemoizer<Int, String>()

            let result = await memoizer.memoize(1) {
                await Task.yield()
                return "computed"
            }

            #expect(result == "computed")
        }

        @Test
        func memoizeMultipleKeys() async {
            let memoizer = AsyncKeyValueMemoizer<Int, String>()

            let result1 = await memoizer.memoize(1) { "value1" }
            let result2 = await memoizer.memoize(2) { "value2" }
            let result3 = await memoizer.memoize(3) { "value3" }

            #expect(result1 == "value1")
            #expect(result2 == "value2")
            #expect(result3 == "value3")

            // Verify cached values
            let cached1 = await memoizer.memoize(1) { "different" }
            let cached2 = await memoizer.memoize(2) { "different" }
            let cached3 = await memoizer.memoize(3) { "different" }

            #expect(cached1 == "value1")
            #expect(cached2 == "value2")
            #expect(cached3 == "value3")
        }

        // MARK: - Concurrency Tests

        @Test
        func concurrentMemoizationSharesWorkPerKey() async {
            let memoizer = AsyncKeyValueMemoizer<String, Int>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        await memoizer.memoize("shared-key") {
                            lock.withLock {
                                computeCount += 1
                            }
                            try? await Task.sleep(nanoseconds: 10_000_000)
                            return 42
                        }
                    }
                }

                var results = [Int]()
                for await result in group {
                    results.append(result)
                }

                #expect(results.count == 100)
                #expect(results.allSatisfy { $0 == 42 })
            }

            // Should only compute once despite 100 concurrent calls
            #expect(computeCount == 1)
        }

        @Test
        func concurrentMemoizationDifferentKeys() async {
            let memoizer = AsyncKeyValueMemoizer<Int, String>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            await withTaskGroup(of: String.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        await memoizer.memoize(i) {
                            lock.withLock {
                                computeCount += 1
                            }
                            return "value-\(i)"
                        }
                    }
                }

                var results = [String]()
                for await result in group {
                    results.append(result)
                }

                #expect(results.count == 50)
                #expect(Set(results).count == 50)
            }

            #expect(computeCount == 50)
        }

        @Test
        func complexKeyAndValueTypes() async {
            struct Key: Hashable, Sendable {
                let id: Int
                let category: String
            }

            struct Value: Sendable, Equatable {
                let data: [String]
            }

            let memoizer = AsyncKeyValueMemoizer<Key, Value>()

            let key = Key(id: 1, category: "test")
            let result = await memoizer.memoize(key) {
                try? await Task.sleep(nanoseconds: 1_000_000)
                return Value(data: ["a", "b", "c"])
            }

            #expect(result.data == ["a", "b", "c"])

            let cached = await memoizer.memoize(key) {
                Value(data: ["different"])
            }
            #expect(cached.data == ["a", "b", "c"])
        }
    }

    @Suite struct ThrowingAsyncKeyValueMemoizerTests {
        // MARK: - Basic Functionality Tests

        @Test
        func memoizeComputesOncePerKey() async throws {
            let memoizer = ThrowingAsyncKeyValueMemoizer<String, Int>()
            nonisolated(unsafe) var computeCount = 0

            let result1 = try await memoizer.memoize("key1") {
                computeCount += 1
                return 42
            }
            #expect(result1 == 42)
            #expect(computeCount == 1)

            let result2 = try await memoizer.memoize("key1") {
                computeCount += 1
                return 99
            }
            #expect(result2 == 42)
            #expect(computeCount == 1)

            let result3 = try await memoizer.memoize("key2") {
                computeCount += 1
                return 100
            }
            #expect(result3 == 100)
            #expect(computeCount == 2)
        }

        @Test
        func memoizeWithAsyncWork() async throws {
            let memoizer = ThrowingAsyncKeyValueMemoizer<Int, String>()

            let result = try await memoizer.memoize(1) {
                try await Task.sleep(nanoseconds: 1_000_000)
                return "computed"
            }

            #expect(result == "computed")
        }

        @Test
        func memoizeCachesErrorPerKey() async throws {
            struct TestError: Error, Equatable {}
            let memoizer = ThrowingAsyncKeyValueMemoizer<String, Int>()

            await #expect(throws: TestError.self) {
                try await memoizer.memoize("error-key") {
                    throw TestError()
                }
            }

            // Subsequent calls to same key should return cached error
            await #expect(throws: TestError.self) {
                try await memoizer.memoize("error-key") {
                    100
                }
            }

            // Different key should work fine
            let result = try await memoizer.memoize("success-key") {
                42
            }
            #expect(result == 42)
        }

        @Test
        func memoizeMultipleKeysWithMixedResults() async throws {
            struct TestError: Error {}
            let memoizer = ThrowingAsyncKeyValueMemoizer<Int, String>()

            let result1 = try await memoizer.memoize(1) { "value1" }
            #expect(result1 == "value1")

            await #expect(throws: TestError.self) {
                try await memoizer.memoize(2) {
                    throw TestError()
                }
            }

            let result3 = try await memoizer.memoize(3) { "value3" }
            #expect(result3 == "value3")

            // Verify cached values
            let cached1 = try await memoizer.memoize(1) { "different" }
            #expect(cached1 == "value1")

            await #expect(throws: TestError.self) {
                try await memoizer.memoize(2) { "different" }
            }

            let cached3 = try await memoizer.memoize(3) { "different" }
            #expect(cached3 == "value3")
        }

        // MARK: - Concurrency Tests

        @Test
        func concurrentMemoizationSharesWorkPerKey() async throws {
            let memoizer = ThrowingAsyncKeyValueMemoizer<String, Int>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try await memoizer.memoize("shared-key") {
                            lock.withLock {
                                computeCount += 1
                            }
                            try await Task.sleep(nanoseconds: 10_000_000)
                            return 42
                        }
                    }
                }

                var results = [Int]()
                for try await result in group {
                    results.append(result)
                }

                #expect(results.count == 100)
                #expect(results.allSatisfy { $0 == 42 })
            }

            // Should only compute once despite 100 concurrent calls
            #expect(computeCount == 1)
        }

        @Test
        func concurrentErrorPropagationPerKey() async throws {
            struct TestError: Error {}
            let memoizer = ThrowingAsyncKeyValueMemoizer<String, Int>()
            var errorCount = 0
            let lock = NSLock()

            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        do {
                            _ = try await memoizer.memoize("error-key") {
                                try await Task.sleep(nanoseconds: 5_000_000)
                                throw TestError()
                            }
                        } catch {
                            lock.withLock {
                                errorCount += 1
                            }
                        }
                    }
                }

                // Consume all results (ignoring errors)
                while let _ = try? await group.next() {}
            }

            // All concurrent calls should receive the error
            #expect(errorCount == 20)
        }

        @Test
        func concurrentMemoizationDifferentKeys() async throws {
            let memoizer = ThrowingAsyncKeyValueMemoizer<Int, String>()
            nonisolated(unsafe) var computeCount = 0
            let lock = NSLock()

            try await withThrowingTaskGroup(of: String.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        try await memoizer.memoize(i) {
                            lock.withLock {
                                computeCount += 1
                            }
                            return "value-\(i)"
                        }
                    }
                }

                var results = [String]()
                for try await result in group {
                    results.append(result)
                }

                #expect(results.count == 50)
                #expect(Set(results).count == 50)
            }

            #expect(computeCount == 50)
        }

        @Test
        func complexKeyAndValueTypes() async throws {
            struct Key: Hashable, Sendable {
                let id: Int
                let category: String
            }

            struct Value: Sendable, Equatable {
                let data: [String]
            }

            let memoizer = ThrowingAsyncKeyValueMemoizer<Key, Value>()

            let key = Key(id: 1, category: "test")
            let result = try await memoizer.memoize(key) {
                try await Task.sleep(nanoseconds: 1_000_000)
                return Value(data: ["a", "b", "c"])
            }

            #expect(result.data == ["a", "b", "c"])

            let cached = try await memoizer.memoize(key) {
                Value(data: ["different"])
            }
            #expect(cached.data == ["a", "b", "c"])
        }

        @Test
        func memoizeWithVariableDelayMultipleKeys() async throws {
            let memoizer = ThrowingAsyncKeyValueMemoizer<String, Int>()
            nonisolated(unsafe) var firstCallComplete = false
            let lock = NSLock()

            try await withThrowingTaskGroup(of: (String, Int).self) { group in
                // First task with delay for key1
                group.addTask {
                    let result = try await memoizer.memoize("key1") {
                        try await Task.sleep(nanoseconds: 20_000_000)
                        lock.withLock {
                            firstCallComplete = true
                        }
                        return 100
                    }
                    return ("key1", result)
                }

                // Wait a bit then add more tasks for both keys
                try await Task.sleep(nanoseconds: 5_000_000)

                for _ in 0..<10 {
                    group.addTask {
                        let result = try await memoizer.memoize("key1") {
                            return 999
                        }
                        return ("key1", result)
                    }
                }

                for _ in 0..<10 {
                    group.addTask {
                        let result = try await memoizer.memoize("key2") {
                            return 200
                        }
                        return ("key2", result)
                    }
                }

                var results: [String: [Int]] = [:]
                for try await (key, value) in group {
                    results[key, default: []].append(value)
                }

                #expect(results["key1"]?.count == 11)
                #expect(results["key1"]?.allSatisfy { $0 == 100 } == true)
                #expect(results["key2"]?.count == 10)
                #expect(results["key2"]?.allSatisfy { $0 == 200 } == true)
            }

            let wasFirstCallComplete = lock.withLock { firstCallComplete }
            #expect(wasFirstCallComplete == true)
        }
    }
}
