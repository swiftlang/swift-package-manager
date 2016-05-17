/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import struct Utility.Path
import func POSIX.mkdir
import func POSIX.system
import func Utility.rmtree

//// Create a test fixture with empty files at the given paths.
func fixture(files: [String], body: @noescape (String) throws -> ()) {
    mktmpdir { prefix in
        try mkdir(prefix)
        for file in files {
            try system("touch", Path.join(prefix, file))
        }
        try body(prefix)
    }
}


@testable import Transmute
import PackageDescription
import PackageType

/// Check the behavior of a test project with the given file paths.
func fixture(files: [String], file: StaticString = #file, line: UInt = #line, body: @noescape (PackageType.Package, [Module]) throws -> ()) throws {
    fixture(files: files) { (prefix: String) in
        let manifest = Manifest(path: Path.join(prefix, "Package.swift"), package: Package(name: "name"), products: [])
        let package = Package(manifest: manifest, url: prefix)
        let modules = try package.modules()
        try body(package, modules)
    }
}
