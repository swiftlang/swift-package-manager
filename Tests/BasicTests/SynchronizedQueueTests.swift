/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class SyncronizedQueueTests: XCTestCase {
    func testSingleProducerConsumer() {
        let queue = SynchronizedQueue<Int?>()
        let queueElements = Set(0..<10)
        var consumed = Set<Int>()

        let producer = Thread {
            for element in queueElements {
                queue.enqueue(element)
            }
            queue.enqueue(nil)
        }

        let consumer = Thread {
            while let element = queue.dequeue() {
                consumed.insert(element)
            }
        }

        consumer.start()
        producer.start()
        consumer.join()
        producer.join()

       XCTAssertEqual(consumed, queueElements)
    }

    func testMultipleProducerConsumer() {
        let queue = SynchronizedQueue<Int?>()

        let queueElementsOne = Set(0..<100)
        let queueElementsTwo = Set(100..<500)

        var consumed = Set<Int>()
        let consumedLock = Basic.Lock()

        // Create two producers.
        let producers = [queueElementsOne, queueElementsTwo].map { queueElements in
            return Thread {
                for element in queueElements {
                    queue.enqueue(element)
                }
                queue.enqueue(nil)
            }
        }

        // Create two consumers.
        let consumers = [0, 1].map { _ in
            return Thread {
                while let element = queue.dequeue() {
                    consumedLock.withLock {
                        _ = consumed.insert(element)
                    }
                }
            }
        }

        consumers.forEach { $0.start() }
        producers.forEach { $0.start() }
        // Block until all producers and consumers are done.
        consumers.forEach { $0.join() }
        producers.forEach { $0.join() }

        // Make sure everything was consumed.
        XCTAssertEqual(consumed, queueElementsOne.union(queueElementsTwo))
    }


    // Stress test for queue. Can produce an element only when current element gets consumed so
    // the consumer will get repeatedly blocked waiting to be singaled before start again.
    func testMultipleProducerConsumer2() {
        let queue = SynchronizedQueue<Int?>()

        let queueElementsOne = Set(0..<1000)
        let queueElementsTwo = Set(1000..<5000)

        var consumed = Set<Int>()

        let canProduceCondition = Condition()
        // Initially we should be able to produce.
        var canProduce = true

        // Create two producers.
        let producers = [queueElementsOne, queueElementsTwo].map { queueElements in
            return Thread {
                for element in queueElements {
                    canProduceCondition.whileLocked {
                        // If we shouldn't produce, block.
                        while !canProduce {
                            canProduceCondition.wait()
                        }
                        // We're producing one element so don't produce next until its consumed.
                        canProduce = false
                        queue.enqueue(element)
                    }
                }
                queue.enqueue(nil)
            }
        }

        // Create two consumers.
        let consumers = [0, 1].map { _ in
            return Thread {
                while let element = queue.dequeue() {
                    canProduceCondition.whileLocked {
                        consumed.insert(element)
                        canProduce = true
                        canProduceCondition.signal()
                    }
                }
            }
        }

        consumers.forEach { $0.start() }
        producers.forEach { $0.start() }
        // Block until all producers and consumers are done.
        consumers.forEach { $0.join() }
        producers.forEach { $0.join() }

        // Make sure everything was consumed.
        XCTAssertEqual(consumed, queueElementsOne.union(queueElementsTwo))
    }

    static var allTests = [
        ("testSingleProducerConsumer", testSingleProducerConsumer),
        ("testMultipleProducerConsumer", testMultipleProducerConsumer),
        ("testMultipleProducerConsumer2", testMultipleProducerConsumer2),
    ]
}
