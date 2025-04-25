//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import XCTest
import _InternalTestSupport // for skipOnWindowsAsTestCurrentlyFails

final class SerializedJSONTests: XCTestCase {
    func testPathInterpolation() throws {
        var path = try AbsolutePath(validating: #"/test\backslashes"#)
        var json: SerializedJSON = "\(path)"

#if os(Windows)
        XCTAssertEqual(json.underlying, #"\\test\\backslashes"#)
#else
        XCTAssertEqual(json.underlying, #"/test\\backslashes"#)
#endif

        #if os(Windows)
        path = try AbsolutePath(validating: #"\??\Volumes{b79de17a-a1ed-4c58-a353-731b7c4885a6}\\"#)
        json = "\(path)"

        XCTAssertEqual(json.underlying, #"\\??\\Volumes{b79de17a-a1ed-4c58-a353-731b7c4885a6}"#)
        #endif
    }

    func testPathInterpolationFailsOnWindows() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: "Expectations are not met")

#if os(Windows)
        var path = try AbsolutePath(validating: #"\\?\C:\Users"#)
        var json: SerializedJSON = "\(path)"

        XCTAssertEqual(json.underlying, #"C:\\Users"#)

        path = try AbsolutePath(validating: #"\\.\UNC\server\share\"#)
        json = "\(path)"

        XCTAssertEqual(json.underlying, #"\\.\\UNC\\server\\share"#)
#endif
    }
}
