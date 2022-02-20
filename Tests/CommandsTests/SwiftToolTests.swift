/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Basics
@testable import Commands
import SPMTestSupport
import TSCBasic
import XCTest

final class SwiftToolTests: CommandsTestCase {
    
    func testVerbosityLogLevel() throws {
        try fixture(name: "Miscellaneous/Simple") { fixturePath in
            do {
                let outputStream = BufferedOutputByteStream()
                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftTool(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .warning)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString, "--verbose"])
                let tool = try SwiftTool(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString, "-v"])
                let tool = try SwiftTool(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString, "--very-verbose"])
                let tool = try SwiftTool(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString, "--vv"])
                let tool = try SwiftTool(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }
        }
    }

    func testNetrcAuthorizationProviders() throws {
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem
            let localPath = fixturePath.appending(component: ".netrc")

            // custom .netrc file
            do {
                let customPath = fs.homeDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(customPath) {
                    "machine mymachine.labkey.org login custom@labkey.org password custom"
                }

                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftTool(options: options)

                let authorizationProvider = try tool.getAuthorizationProvider() as? CompositeAuthorizationProvider
                let netrcProviders = authorizationProvider?.providers.compactMap{ $0 as? NetrcAuthorizationProvider } ?? []
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(netrcProviders.first.map { resolveSymlinks($0.path) }, resolveSymlinks(customPath))

                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getAuthorizationProvider(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("Did not find .netrc file at \(customPath)."))
                }
            }

            // local .netrc file
            do {
                try fs.writeFileContents(localPath) {
                    return "machine mymachine.labkey.org login local@labkey.org password local"
                }

                let options = try SwiftToolOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftTool(options: options)

                let authorizationProvider = try tool.getAuthorizationProvider() as? CompositeAuthorizationProvider
                let netrcProviders = authorizationProvider?.providers.compactMap{ $0 as? NetrcAuthorizationProvider } ?? []
                XCTAssertTrue(netrcProviders.count >= 1) // This might include .netrc in user's home dir
                XCTAssertNotNil(netrcProviders.first { resolveSymlinks($0.path) == resolveSymlinks(localPath) })

                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "local@labkey.org")
                XCTAssertEqual(auth?.password, "local")
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }
}
