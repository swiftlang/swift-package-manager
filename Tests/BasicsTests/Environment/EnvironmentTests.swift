//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@_spi(SwiftPMInternal)
@testable
import Basics

import Testing
import _InternalTestSupport

struct EnvironmentTests {
    @Test
    func initialize() {
        let environment = Environment()
        #expect(environment.isEmpty)
    }

    @Test
    func setting_and_accessing_via_subscript() {
        var environment = Environment()
        let key = EnvironmentKey("TestKey")
        environment[key] = "TestValue"
        #expect(environment[key] == "TestValue")
    }

    @Test
    func initDictionaryFromSelf() {
        let dictionary = [
            "TestKey": "TestValue",
            "testKey": "TestValue2",
        ]
        let environment = Environment(dictionary)
        let expectedValue: String
        let expectedCount: Int

        #if os(Windows)
            expectedValue = "TestValue2"  // uppercase sorts before lowercase, so the second value overwrites the first
            expectedCount = 1
        #else
            expectedValue = "TestValue"
            expectedCount = 2
        #endif
        #expect(environment["TestKey"] == expectedValue)
        #expect(environment.count == expectedCount)
    }

    @Test
    func initSelfFromDictionary() {
        let dictionary = ["TestKey": "TestValue"]
        let environment = Environment(dictionary)
        #expect(environment["TestKey"] == "TestValue")
        #expect(environment.count == 1)
    }

    func path(_ components: String...) -> String {
        components.joined(separator: Environment.pathEntryDelimiter)
    }

    @Test
    func prependPath() {
        var environment = Environment()
        let key = EnvironmentKey(UUID().uuidString)
        #expect(environment[key] == nil)

        environment.prependPath(key: key, value: "/bin")
        #expect(environment[key] == path("/bin"))

        environment.prependPath(key: key, value: "/usr/bin")
        #expect(environment[key] == path("/usr/bin", "/bin"))

        environment.prependPath(key: key, value: "/usr/local/bin")
        #expect(environment[key] == path("/usr/local/bin", "/usr/bin", "/bin"))

        environment.prependPath(key: key, value: "")
        #expect(environment[key] == path("/usr/local/bin", "/usr/bin", "/bin"))
    }

    @Test
    func appendPath() {
        var environment = Environment()
        let key = EnvironmentKey(UUID().uuidString)
        #expect(environment[key] == nil)

        environment.appendPath(key: key, value: "/bin")
        #expect(environment[key] == path("/bin"))

        environment.appendPath(key: key, value: "/usr/bin")
        #expect(environment[key] == path("/bin", "/usr/bin"))

        environment.appendPath(key: key, value: "/usr/local/bin")
        #expect(environment[key] == path("/bin", "/usr/bin", "/usr/local/bin"))

        environment.appendPath(key: key, value: "")
        #expect(environment[key] == path("/bin", "/usr/bin", "/usr/local/bin"))
    }

    @Test
    func pathEntryDelimiter() {
        let expectedPathDelimiter: String
        #if os(Windows)
            expectedPathDelimiter = ";"
        #else
            expectedPathDelimiter = ":"
        #endif
        #expect(Environment.pathEntryDelimiter == expectedPathDelimiter)
    }

    /// Important: This test is inherently race-prone, if it is proven to be
    /// flaky, it should run in a singled threaded environment/removed entirely.
    @Test
    func current() throws {
        #if os(Windows)
        let pathEnvVarName = "Path"
        #else
        let pathEnvVarName = "PATH"
        #endif

        #expect(Environment.current["PATH"] == ProcessInfo.processInfo.environment[pathEnvVarName])
    }

    /// Important: This test is inherently race-prone, if it is proven to be
    /// flaky, it should run in a singled threaded environment/removed entirely.
    @Test
    func makeCustom() async throws {
        let key = EnvironmentKey(UUID().uuidString)
        let value = "TestValue"

        var customEnvironment = Environment()
        customEnvironment[key] = value

        #expect(Environment.current[key] == nil)
        try Environment.makeCustom(customEnvironment) {
            #expect(Environment.current[key] == value)
        }
        #expect(Environment.current[key] == nil)
    }

    /// Important: This test is inherently race-prone, if it is proven to be
    /// flaky, it should run in a singled threaded environment/removed entirely.
    @Test(
        .disabled(if: CiEnvironment.runningInSmokeTestPipeline || CiEnvironment.runningInSelfHostedPipeline, "This test can disrupt other tests running in parallel."),
    )
    func makeCustomPathEnv() async throws {
        let customEnvironment: Environment = .current
        let origPath = customEnvironment[.path]

        try Environment.makeCustom(["PATH": "/foo/bar"]) {
            #expect(Environment.current[.path] == "/foo/bar")
        }
        #expect(Environment.current[.path] == origPath)
    }

    /// Important: This test is inherently race-prone, if it is proven to be
    /// flaky, it should run in a singled threaded environment/removed entirely.
    @Test
    func process() throws {
        let key = EnvironmentKey(UUID().uuidString)
        let value = "TestValue"

        var environment = Environment.current
        #expect(environment[key] == nil)

        try Environment.set(key: key, value: value)
        environment = Environment.current // reload
        #expect(environment[key] == value)

        try Environment.set(key: key, value: nil)
        #expect(environment[key] == value)  // this is a copy!

        environment = Environment.current // reload
        #expect(environment[key] == nil)
    }

    @Test
    func cachable() {
        let term = EnvironmentKey("TERM")
        var environment = Environment()
        environment[.path] = "/usr/bin"
        environment[term] = "xterm-256color"

        let cachableEnvironment = environment.cachable
        #expect(cachableEnvironment[.path] != nil)
        #expect(cachableEnvironment[term] == nil)
    }

    @Test
    func collection() {
        let environment: Environment = ["TestKey": "TestValue"]
        #expect(environment.count == 1)
        #expect(environment.first?.key == EnvironmentKey("TestKey"))
        #expect(environment.first?.value == "TestValue")
    }

    @Test
    func description() {
        var environment = Environment()
        environment[EnvironmentKey("TestKey")] = "TestValue"
        #expect(environment.description == #"["TestKey=TestValue"]"#)
    }

    @Test
    func encodable() throws {
        var environment = Environment()
        environment["TestKey"] = "TestValue"
        let data = try JSONEncoder().encode(environment)
        let jsonString = String(data: data, encoding: .utf8)
        #expect(jsonString == #"{"TestKey":"TestValue"}"#)
    }

    @Test
    func equatable() {
        let environment0: Environment = ["TestKey": "TestValue"]
        let environment1: Environment = ["TestKey": "TestValue"]
        #expect(environment0 == environment1)

#if os(Windows)
        // Test case insensitivity on windows
        let environment2: Environment = ["testKey": "TestValue"]
            #expect(environment0 == environment2)
#endif
    }

    @Test
    func expressibleByDictionaryLiteral() {
        let environment: Environment = ["TestKey": "TestValue"]
        #expect(environment["TestKey"] == "TestValue")
    }


    @Test
    func decodable() throws {
        let jsonString = #"{"TestKey":"TestValue"}"#
        let data = jsonString.data(using: .utf8)!
        let environment = try JSONDecoder().decode(Environment.self, from: data)
        #expect(environment[EnvironmentKey("TestKey")] == "TestValue")
    }
}
