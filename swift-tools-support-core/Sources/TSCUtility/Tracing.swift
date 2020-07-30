/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

public enum TracingEventType: String, Codable {
    case asyncBegin
    case asyncEnd
}

public protocol TracingEventProtocol {
    /// The category of the event.
    var cat: String { get }

    /// The name of the event.
    var name: String { get }

    /// The free form id of the event.
    var id: String { get }

    /// The phase of the event.
    var ph: TracingEventType { get }

    /// The process id of the process where the event occured.
    var pid: Int { get }

    /// The thread id of the process where the event occured.
    var tid: Int { get }

    /// The timestamp of the event.
    var ts: Int { get }

    /// The start time of the process where the event occured.
    var startTs: Int { get }
    init(
        cat: String,
        name: String,
        id: String,
        ph: TracingEventType,
        pid: Int,
        tid: Int,
        ts: Int,
        startTs: Int
    )
}

public protocol TracingCollectionProtocol {
    var events: [TracingEventProtocol] { get set }
    init(_ events: [TracingEventProtocol])
}

extension TracingCollectionProtocol {
    public mutating func append(_ tracingCollection: TracingCollectionProtocol) {
        self.events.append(contentsOf: tracingCollection.events)
    }
}

public struct TracingEvent: TracingEventProtocol, Codable {
    public let cat: String
    public let name: String
    public let id: String
    public let ph: TracingEventType
    public let pid: Int
    public let tid: Int
    public let ts: Int
    public let startTs: Int

    #if canImport(Darwin)
    public init(
        cat: String,
        name: String,
        id: String,
        ph: TracingEventType,
        pid: Int = Int(getpid()),
        tid: Int = Int(pthread_mach_thread_np(pthread_self())),
        ts: Int = Int(DispatchTime.now().uptimeNanoseconds),
        startTs: Int = 0
    ) {
        self.cat = cat
        self.name = name
        self.id = id
        self.ph = ph
        self.pid = pid
        self.tid = tid
        self.ts = ts
        self.startTs = startTs
    }
    #elseif canImport(Glibc)
    public init(
        cat: String,
        name: String,
        id: String,
        ph: TracingEventType,
        pid: Int = Int(getpid()),
        tid: Int = 1,
        ts: Int = Int(DispatchTime.now().uptimeNanoseconds),
        startTs: Int = 0
    ) {
        self.cat = cat
        self.name = name
        self.id = id
        self.ph = ph
        self.pid = pid
        self.tid = tid
        self.ts = ts
        self.startTs = startTs
    }
    #else
    public init(
        cat: String,
        name: String,
        id: String,
        ph: TracingEventType,
        pid: Int = 1,
        tid: Int = 1,
        ts: Int = Int(DispatchTime.now().uptimeNanoseconds),
        startTs: Int = 0
    ) {
        self.cat = cat
        self.name = name
        self.id = id
        self.ph = ph
        self.pid = pid
        self.tid = tid
        self.ts = ts
        self.startTs = startTs
    }
    #endif
}

public class TracingCollection: TracingCollectionProtocol {
    public var events: [TracingEventProtocol] = []
    public required init(_ events: [TracingEventProtocol] = []) {
        self.events = events
    }
}

extension Context {
    public static func withTracing(_ collection: TracingCollectionProtocol) -> Context {
        return Context(dictionaryLiteral: (ObjectIdentifier(TracingCollectionProtocol.self), collection as Any))
    }

    public mutating func enrichWithTracing(_ collection: TracingCollectionProtocol) -> Context {
        self[ObjectIdentifier(TracingCollectionProtocol.self)] = collection
        return self
    }

    public var tracing: TracingCollectionProtocol? {
        get {
            guard let collection = self[ObjectIdentifier(TracingCollectionProtocol.self)] as? TracingCollectionProtocol else {
                return nil
            }
            return collection
        }
        set {
            self[ObjectIdentifier(TracingCollectionProtocol.self)] = newValue
        }
    }
}
