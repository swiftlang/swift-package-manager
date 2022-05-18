//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import TSCBasic
import XCTest

final class EnvironmentVariablesTests: XCTestCase {
#if os(Windows)
    let pathDelimiter = ";"
#else
    let pathDelimiter = ":"
#endif
    
    func testPrependPath() throws {
        let key = UUID().uuidString
        var env = EnvironmentVariables()
        
        XCTAssertNil(env[key])
        
        env.prependPath(key, value: "a")
        XCTAssertEqual(env[key], "a")
        
        env.prependPath(key, value: "b")
        XCTAssertEqual(env[key], ["b", "a"].joined(separator: pathDelimiter))
        
        env.prependPath(key, value: "c")
        XCTAssertEqual(env[key], ["c", "b", "a"].joined(separator: pathDelimiter))
        
        env.prependPath(key, value: "")
        XCTAssertEqual(env[key], ["c", "b", "a"].joined(separator: pathDelimiter))
    }
    
    func testAppendPath() throws {
        let key = UUID().uuidString
        var env = EnvironmentVariables()
        
        XCTAssertNil(env[key])
        
        env.appendPath(key, value: "a")
        XCTAssertEqual(env[key], "a")
        
        env.appendPath(key, value: "b")
        XCTAssertEqual(env[key], ["a", "b"].joined(separator: pathDelimiter))
        
        env.appendPath(key, value: "c")
        XCTAssertEqual(env[key], ["a", "b", "c"].joined(separator: pathDelimiter))
        
        env.appendPath(key, value: "")
        XCTAssertEqual(env[key], ["a", "b", "c"].joined(separator: pathDelimiter))
    }
    
    func testProcess() throws {
        let key = UUID().uuidString
        let value = UUID().uuidString
        
        var env = EnvironmentVariables.process()
        XCTAssertNil(env[key])
        
        try ProcessEnv.setVar(key, value: value)
        env = EnvironmentVariables.process() // read from process
        XCTAssertEqual(env[key], value)
        
        try ProcessEnv.unsetVar(key)
        XCTAssertEqual(env[key], value) // this is a copy!
        
        env = EnvironmentVariables.process() // read again from process
        XCTAssertNil(env[key])
    }
}
