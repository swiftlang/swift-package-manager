/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import POSIX
import func libc.fclose

public func generate(testModules: [TestModule], prefix: String) throws {

    let testManifestFolder = Path.join(prefix, "XCTestGen")
    try mkdir(testManifestFolder)

    for module in testModules {
        let path = Path.join(testManifestFolder, "\(module.name)-XCTestManifest.swift")
        try writeXCTestManifest(module, path: path)
    }

    let main = Path.join(testManifestFolder, "XCTestMain.swift")
    try writeXCTestMain(testModules, path: main)
}

private func writeXCTestManifest(module: TestModule, path: String) throws {

    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }

    //imports
    try fputs("import XCTest\n", file)
    try fputs("\n", file)

    try fputs("#if os(Linux)\n", file)

    //for each class
    try module.classes.sort { $0.name < $1.name }.forEach { moduleClass in
        try fputs("extension \(moduleClass.name) {\n", file)
        try fputs("    static var allTests : [(String, \(moduleClass.name) -> () throws -> Void)] {\n", file)
        try fputs("        return [\n", file)

        try moduleClass.testMethods.sort().forEach {
            try fputs("            (\"\($0)\", \($0)),\n", file)
        }

        try fputs("        ]\n", file)
        try fputs("    }\n", file)
        try fputs("}\n", file)
    }

    try fputs("#endif\n\n", file)
}

private func writeXCTestMain(testModules: [TestModule], path: String) throws {

    //don't write anything if no classes are available
    guard testModules.count > 0 else { return }

    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }

    //imports
    try fputs("import XCTest\n", file)
    try testModules.flatMap { $0.name }.sort().forEach {
        try fputs("@testable import \($0)\n", file)
    }
    try fputs("\n", file)

    try fputs("XCTMain([\n", file)

    //for each class
    for module in testModules {
        try module
            .classes
            .sort { $0.name < $1.name }
            .forEach { moduleClass in
                try fputs("    testCase(\(module.name).\(moduleClass.name).allTests),\n", file)
        }
    }

    try fputs("])\n\n", file)
}