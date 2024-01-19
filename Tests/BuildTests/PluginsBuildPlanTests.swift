//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import SPMTestSupport
import XCTest

final class PluginsBuildPlanTests: XCTestCase {
    func testBuildToolsDatabasePath() throws {
        try fixture(name: "Miscellaneous/Plugins/MySourceGenPlugin") { fixturePath in
            let (stdout, stderr) = try executeSwiftBuild(fixturePath)
            XCTAssertMatch(stdout, .contains("Build complete!"))
            XCTAssertTrue(localFileSystem.exists(fixturePath.appending(RelativePath(".build/plugins/tools/build.db"))))
        }
    }
}
