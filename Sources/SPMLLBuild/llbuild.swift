/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// We either export the llbuildSwift shared library or the llbuild framework.
#if canImport(llbuildSwift)
@_exported import llbuildSwift
@_exported import llbuild
#else
@_exported import llbuild
#endif

import Foundation

/// An llbuild value.
public protocol LLBuildValue: Codable {
}

/// An llbuild key.
public protocol LLBuildKey: Codable {
    /// The value that this key computes.
    associatedtype BuildValue: LLBuildValue

    /// The rule that this key operates on.
    associatedtype BuildRule: LLBuildRule
}

public protocol LLBuildEngineDelegate {
    func lookupRule(rule: String, key: Key) -> Rule
}

public final class LLBuildEngine {

    private final class Delegate: BuildEngineDelegate {
        let delegate: LLBuildEngineDelegate

        init(_ delegate: LLBuildEngineDelegate) {
            self.delegate = delegate
        }

        func lookupRule(_ key: Key) -> Rule {
            let ruleKey = RuleKey(key)
            return delegate.lookupRule(
                rule: ruleKey.rule, key: Key(ruleKey.data))
        }
    }

    private let engine: BuildEngine

    public init(delegate: LLBuildEngineDelegate) {
        engine = BuildEngine(delegate: Delegate(delegate))
    }

    deinit {
        engine.close()
    }

    public func build<T: LLBuildKey>(key: T) -> T.BuildValue {
        let encodedKey = RuleKey(
            rule: T.BuildRule.ruleName, data: key.toKey().data).toKey()
        let value = engine.build(key: encodedKey)
        return T.BuildValue(value)
    }

    public func attachDB(path: String, schemaVersion: Int = 0) throws {
        try engine.attachDB(path: path, schemaVersion: schemaVersion)
    }

    public func close() {
        engine.close()
    }
}

// FIXME: Rename to something else.
public class LLTaskBuildEngine {

    let engine: TaskBuildEngine

    init(_ engine: TaskBuildEngine) {
        self.engine = engine
    }

    public func taskNeedsInput<T: LLBuildKey>(_ key: T, inputID: Int) {
        let encodedKey = RuleKey(
            rule: T.BuildRule.ruleName, data: key.toKey().data).toKey()
        engine.taskNeedsInput(encodedKey, inputID: inputID)
    }

    public func taskIsComplete<T: LLBuildValue>(_ result: T) {
        engine.taskIsComplete(result.toValue(), forceChange: false)
    }
}

/// An individual build rule.
open class LLBuildRule: Rule, Task {

    /// The name of the rule.
    ///
    /// This name will be available in the delegate's lookupRule(rule:key:).
    open class var ruleName: String {
        fatalError("subclass responsibility")
    }

    public init() {
    }

    public func createTask() -> Task {
        return self
    }

    public func start(_ engine: TaskBuildEngine) {
        self.start(LLTaskBuildEngine(engine))
    }

    public func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
        self.provideValue(LLTaskBuildEngine(engine), inputID: inputID, value: value)
    }

    public func inputsAvailable(_ engine: TaskBuildEngine) {
        self.inputsAvailable(LLTaskBuildEngine(engine))
    }

    // MARK:-

    open func isResultValid(_ priorValue: Value) -> Bool {
        return true
    }

    open func start(_ engine: LLTaskBuildEngine) {
    }

    open func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
    }

    open func inputsAvailable(_ engine: LLTaskBuildEngine) {
    }
}

// MARK:- Helpers

private struct RuleKey: Codable {

    let rule: String
    let data: [UInt8]

    init(rule: String, data: [UInt8]) {
        self.rule = rule
        self.data = data
    }

    init(_ key: Key) {
        self.init(key.data)
    }

    init(_ data: [UInt8]) {
        self = try! fromBytes(data)
    }

    func toKey() -> Key {
        return try! Key(toBytes(self))
    }
}

public extension LLBuildKey {
    init(_ key: Key) {
        self.init(key.data)
    }

    init(_ data: [UInt8]) {
        self = try! fromBytes(data)
    }

    func toKey() -> Key {
        return try! Key(toBytes(self))
    }
}

public extension LLBuildValue {
    init(_ value: Value) {
        self = try! fromBytes(value.data)
    }

    func toValue() -> Value {
        return try! Value(toBytes(self))
    }
}

private func fromBytes<T: Decodable>(_ bytes: [UInt8]) throws -> T {
    var bytes = bytes
    let data = Data(bytes: &bytes, count: bytes.count)
    return try JSONDecoder().decode(T.self, from: data)
}

private func toBytes<T: Encodable>(_ value: T) throws -> [UInt8] {
    let encoder = JSONEncoder()
      if #available(macOS 10.13, *) {
          encoder.outputFormatting = [.sortedKeys]
      }
    let encoded = try encoder.encode(value)
    return [UInt8](encoded)
}
