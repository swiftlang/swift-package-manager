/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.setenv
import func libc.exit
import ASTParser
import Utility
import Multitool

// Initialize the resource support.
public var globalSymbolInMainBinary = 0
Resources.initialize(&globalSymbolInMainBinary)

do {
    let dir = try directories()

    //FIXME this is a hack for SwiftPM’s own tests
    setenv("SPM_INSTALL_PATH", dir.build, 0)

    let yamlPath = Path.join(dir.build, "debug.yaml")

    guard yamlPath.exists else { throw Error.DebugYAMLNotFound }

    try build(YAMLPath: yamlPath, target: "tests-ast")
    let testModules = try parseAST(Path.join(dir.build, "debug", "TestsAST"))

    try generate(testModules, prefix: Path.join(dir.build, "debug"))

//    print(a)

//    try build(YAMLPath: yamlPath, target: "test")
//    let success = test(dir.build, "debug")
    exit(0)

} catch {
    handleError(error, usage: { _ in })
}
